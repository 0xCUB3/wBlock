import SwiftUI
import WebKit

struct CodeMirrorDocumentAnalysis: Equatable {
    let isLargeDocument: Bool
    let hasLongLine: Bool
    let longestLine: Int
    let lineWrapping: Bool
    let syntaxHighlightingEnabled: Bool
}

@MainActor
final class CodeMirrorEditorController: ObservableObject {
    fileprivate let initialText: String
    fileprivate weak var bridge: (any CodeMirrorEditorBridge)?

    @Published private(set) var isDirty = false
    @Published private(set) var analysis: CodeMirrorDocumentAnalysis?

    init(text: String) {
        self.initialText = text
    }

    func currentText() async -> String {
        await bridge?.currentText() ?? initialText
    }

    func openSearch() {
        bridge?.openSearch()
    }

    func focus() {
        bridge?.focus()
    }

    func discardChanges() {
        bridge?.resetDocument(to: initialText, markClean: true)
    }

    fileprivate func bind(_ bridge: any CodeMirrorEditorBridge) {
        self.bridge = bridge
    }

    fileprivate func updateDirtyState(_ isDirty: Bool) {
        guard self.isDirty != isDirty else { return }
        self.isDirty = isDirty
    }

    fileprivate func updateAnalysis(_ analysis: CodeMirrorDocumentAnalysis) {
        guard self.analysis != analysis else { return }
        self.analysis = analysis
    }
}

@MainActor
private protocol CodeMirrorEditorBridge: AnyObject {
    func currentText() async -> String
    func openSearch()
    func focus()
    func resetDocument(to text: String, markClean: Bool)
}

private enum CodeMirrorResources {
    static let handlerName = "codeMirror"

    static var htmlURL: URL? {
        Bundle.main.url(forResource: "codemirror", withExtension: "html")
    }

    static var localizedPhrases: [String: String] {
        [
            "Go to line": LocalizedStrings.text("Go to line", comment: "CodeMirror go to line label"),
            "go": LocalizedStrings.text("go", comment: "CodeMirror go button"),
            "Find": LocalizedStrings.text("Find", comment: "CodeMirror find label"),
            "Replace": LocalizedStrings.text("Replace", comment: "CodeMirror replace label"),
            "next": LocalizedStrings.text("next", comment: "CodeMirror next match button"),
            "previous": LocalizedStrings.text("previous", comment: "CodeMirror previous match button"),
            "all": LocalizedStrings.text("all", comment: "CodeMirror all matches button"),
            "match case": LocalizedStrings.text("match case", comment: "CodeMirror match case toggle"),
            "by word": LocalizedStrings.text("by word", comment: "CodeMirror whole word toggle"),
            "replace": LocalizedStrings.text("replace", comment: "CodeMirror replace button"),
            "replace all": LocalizedStrings.text("replace all", comment: "CodeMirror replace all button"),
            "close": LocalizedStrings.text("close", comment: "CodeMirror close button"),
            "current match": LocalizedStrings.text("current match", comment: "CodeMirror current match summary"),
            "replaced $ matches": LocalizedStrings.text(
                "replaced $ matches",
                comment: "CodeMirror replacement summary"
            ),
            "replaced match on line $": LocalizedStrings.text(
                "replaced match on line $",
                comment: "CodeMirror replacement line summary"
            ),
            "on line": LocalizedStrings.text("on line", comment: "CodeMirror current match line label"),
        ]
    }
}

private struct CodeMirrorBootstrapConfig: Encodable {
    let text: String
    let editable: Bool
    let lineWrapping: Bool
    let phrases: [String: String]
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

#if os(macOS)
struct CodeMirrorTextEditor: NSViewRepresentable {
    let controller: CodeMirrorEditorController
    var isEditable: Bool
    var isLineWrappingEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> WKWebView {
        makeWebView(with: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView, coordinator: context.coordinator)
    }
}
#elseif os(iOS)
struct CodeMirrorTextEditor: UIViewRepresentable {
    let controller: CodeMirrorEditorController
    var isEditable: Bool
    var isLineWrappingEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        makeWebView(with: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView, coordinator: context.coordinator)
    }
}
#endif

private extension CodeMirrorTextEditor {
    func makeWebView(with coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        let messageProxy = WeakScriptMessageHandler(delegate: coordinator)
        userContentController.add(messageProxy, name: CodeMirrorResources.handlerName)
        configuration.userContentController = userContentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        coordinator.messageHandlerProxy = messageProxy
        coordinator.attach(webView)

        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #elseif os(iOS)
        let scrollView = webView.scrollView
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.bounces = false
        scrollView.bouncesZoom = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.pinchGestureRecognizer?.isEnabled = false
        #endif

        webView.navigationDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = false

        #if DEBUG
        if #available(macOS 13.3, iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        if let htmlURL = CodeMirrorResources.htmlURL {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        return webView
    }

    func update(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.attach(webView)
        coordinator.updateConfiguration(editable: isEditable, lineWrapping: isLineWrappingEnabled)
    }
}

extension CodeMirrorTextEditor {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, CodeMirrorEditorBridge {
        private let controller: CodeMirrorEditorController
        fileprivate var messageHandlerProxy: WeakScriptMessageHandler?
        private weak var webView: WKWebView?
        private var hasLoadedPage = false
        private var hasBootedEditor = false
        private var pendingEditable = false
        private var pendingLineWrapping = false
        private var lastAppliedEditable: Bool?
        private var lastAppliedLineWrapping: Bool?

        init(controller: CodeMirrorEditorController) {
            self.controller = controller
            super.init()
            controller.bind(self)
        }

        deinit {
            webView?.navigationDelegate = nil
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorResources.handlerName)
        }

        func attach(_ webView: WKWebView) {
            guard self.webView !== webView else { return }
            self.webView = webView
            controller.bind(self)
        }

        func updateConfiguration(editable: Bool, lineWrapping: Bool) {
            pendingEditable = editable
            pendingLineWrapping = lineWrapping

            guard hasLoadedPage else { return }
            guard hasBootedEditor else {
                bootEditorIfNeeded()
                return
            }

            if lastAppliedEditable != editable {
                runScript("window.wblockEditor.setEditable(\(editable ? "true" : "false"))")
                lastAppliedEditable = editable
            }

            if lastAppliedLineWrapping != lineWrapping {
                runScript(Self.lineWrappingScript(enabled: lineWrapping))
                lastAppliedLineWrapping = lineWrapping
            }
        }

        func openSearch() {
            guard hasBootedEditor else { return }
            runScript("window.wblockEditor.openSearch()")
        }

        func focus() {
            guard hasBootedEditor else { return }
            runScript("window.wblockEditor.focus()")
        }

        func resetDocument(to text: String, markClean: Bool) {
            guard hasBootedEditor, let encodedText = Self.encodedJSONString(text) else { return }
            runScript("window.wblockEditor.setDocument(\(encodedText), \(markClean ? "true" : "false"))")
        }

        func currentText() async -> String {
            guard hasBootedEditor, let webView else { return controller.initialText }
            return await webView.evaluateJavaScriptString("window.wblockEditor.getDocument()")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasLoadedPage = true
            bootEditorIfNeeded()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == CodeMirrorResources.handlerName else { return }
            guard let payload = message.body as? [String: Any], let type = payload["type"] as? String else { return }

            switch type {
            case "ready":
                hasBootedEditor = true
                lastAppliedEditable = pendingEditable
                lastAppliedLineWrapping = pendingLineWrapping
                controller.updateDirtyState(false)

                if let analysisPayload = payload["analysis"] as? [String: Any],
                   let analysis = Self.analysis(from: analysisPayload)
                {
                    controller.updateAnalysis(analysis)
                }
            case "dirtyStateChanged":
                if let isDirty = payload["isDirty"] as? Bool {
                    controller.updateDirtyState(isDirty)
                }
            default:
                break
            }
        }

        private func bootEditorIfNeeded() {
            guard hasLoadedPage, !hasBootedEditor else { return }
            guard let script = bootstrapScript() else { return }
            runScript(script)
        }

        private func bootstrapScript() -> String? {
            let config = CodeMirrorBootstrapConfig(
                text: controller.initialText,
                editable: pendingEditable,
                lineWrapping: pendingLineWrapping,
                phrases: CodeMirrorResources.localizedPhrases
            )
            guard let encodedConfig = Self.encodedJSON(config) else { return nil }
            return """
            window.wblockEditor.boot(\(encodedConfig));
            \(Self.lineWrappingScript(enabled: pendingLineWrapping))
            """
        }

        private func runScript(_ script: String) {
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        private static func encodedJSON<T: Encodable>(_ value: T) -> String? {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private static func encodedJSONString(_ value: String) -> String? {
            encodedJSON(value)
        }

        private static func lineWrappingScript(enabled: Bool) -> String {
            """
            window.wblockEditor.setLineWrapping(\(enabled ? "true" : "false"));
            document.body.classList.toggle("cm-wrap-lines", \(enabled ? "true" : "false"));
            """
        }

        private static func analysis(from payload: [String: Any]) -> CodeMirrorDocumentAnalysis? {
            guard let isLargeDocument = payload["isLargeDocument"] as? Bool,
                  let hasLongLine = payload["hasLongLine"] as? Bool,
                  let longestLine = payload["longestLine"] as? Int,
                  let lineWrapping = payload["lineWrapping"] as? Bool,
                  let syntaxHighlightingEnabled = payload["syntaxHighlightingEnabled"] as? Bool
            else {
                return nil
            }

            return CodeMirrorDocumentAnalysis(
                isLargeDocument: isLargeDocument,
                hasLongLine: hasLongLine,
                longestLine: longestLine,
                lineWrapping: lineWrapping,
                syntaxHighlightingEnabled: syntaxHighlightingEnabled
            )
        }
    }
}

@MainActor
private extension WKWebView {
    func evaluateJavaScriptString(_ script: String) async -> String {
        await withCheckedContinuation { continuation in
            evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }
}
