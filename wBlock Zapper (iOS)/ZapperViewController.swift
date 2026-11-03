import UIKit
import UniformTypeIdentifiers
import WebKit
import wBlockCoreService

/// The share sheet's Element Zapper. In-app browsers can't run Safari
/// extensions, so this opens the shared page in its own web view and runs the
/// Safari Zapper there, saving to the same rules (#1074).
final class ZapperNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setViewControllers([ZapperViewController()], animated: false)
    }
}

final class ZapperViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandlerWithReply {
    /// The native actions the Zapper uses. Nothing else reaches the handler.
    private static let allowedActions: Set<String> = [
        "getSiteDisabledState", "getZapperRules", "syncZapperRules", "setSiteZapperDisabled",
    ]
    private let world = WKContentWorld.world(name: "wBlockZapper")
    private let messages = ZapperViewController.localizedMessages()
    private lazy var webView = makeWebView()

    override func loadView() {
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = messages["popup_element_zapper"]
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.finish() })
        Task { await loadSharedPage() }
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = configuration.userContentController
        contentController.addScriptMessageHandler(self, contentWorld: world, name: "wblock")
        let messagesJSON = (try? JSONSerialization.data(withJSONObject: messages))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let sources = [
            Self.resource("zapper-share-shim").map { $0.replacingOccurrences(of: "WBLOCK_MESSAGES", with: messagesJSON) },
            Self.resource("zapper-content"),
        ]
        for source in sources.compactMap({ $0 }) {
            contentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    private func loadSharedPage() async {
        let providers = (navigationController?.extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               ["http", "https"].contains(url.scheme?.lowercased()) {
                webView.load(URLRequest(url: url))
                return
            }
        }
        showUnavailable()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.callAsyncJavaScript(
            "return await wblockShareDispatch({ type: 'wblock:zapper:activate' })",
            in: nil, in: world, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showUnavailable()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              Self.allowedActions.contains(action)
        else {
            replyHandler(nil, "Unsupported message")
            return
        }
        WebExtensionRequestHandler.respond(to: body) { response in
            DispatchQueue.main.async { replyHandler(response, nil) }
        }
    }

    private func showUnavailable() {
        let alert = UIAlertController(
            title: messages["popup_element_zapper"],
            message: messages["popup_error_zapper_unavailable"],
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: messages["zapper_button_done"], style: .default) { [weak self] _ in
            self?.finish()
        })
        present(alert, animated: true)
    }

    private func finish() {
        navigationController?.extensionContext?.completeRequest(returningItems: nil)
    }

    private static func resource(_ name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// The Safari extension's strings, in the user's language over English.
    private static func localizedMessages() -> [String: String] {
        let folders = Locale.preferredLanguages.prefix(1).map { language -> String in
            if language.hasPrefix("zh") { return language.contains("Hant") ? "zh_TW" : "zh_CN" }
            if language.hasPrefix("pt") { return "pt_BR" }
            return String(language.prefix { $0 != "-" })
        }
        return (["en"] + folders).reduce(into: [:]) { result, folder in
            guard let url = Bundle.main.url(forResource: "messages", withExtension: "json", subdirectory: "_locales/\(folder)"),
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
            else { return }
            for (key, entry) in json {
                if let message = entry["message"] as? String { result[key] = message }
            }
        }
    }
}
