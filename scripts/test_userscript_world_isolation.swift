import AppKit
import WebKit

@MainActor final class WorldProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var webView: WKWebView!
    var nativeCalls: [[String: Any]] = []

    func start() throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let world = WKContentWorld.world(name: "wBlock-security-probe")
        configuration.userContentController.add(self, contentWorld: world, name: "probe")
        let descriptor: [String: Any] = [
            "id": "private-script", "name": "Private GM", "isEnabled": true,
            "isLocal": false, "sourceURL": "https://example.com/private.user.js",
            "injectInto": "page", "runAt": "document-start", "payloadRevision": 0, "grant": ["GM_setValue", "GM_xmlhttpRequest"],
            "content": "window.__privateExecution = true; GM_setValue('private-key', 'secret'); GM_xmlhttpRequest({url:'https://api.example/legitimate',onload:function(){window.__privateResponse = true;}});"
        ]
        let json = String(data: try JSONSerialization.data(withJSONObject: descriptor), encoding: .utf8)!
        let bootstrap = """
        console.error = function(...args) { window.webkit.messageHandlers.probe.postMessage({action:"error", detail:args.map(String).join(" ")}); };
        window.browser = {runtime:{onMessage:{addListener:function(){}},sendMessage:async function(message){
          window.webkit.messageHandlers.probe.postMessage(message);
          if(message.action === 'getUserScripts') return {userScripts:[\(json)]};
          if(message.action === 'gmXmlhttpRequest') return {status:200,responseText:'private-response'};
          return {ok:true};
        }}};
        """
        let injector = try String(contentsOfFile: "wBlock Scripts (iOS)/Resources/userscript-injector.js", encoding: .utf8)
        configuration.userContentController.addUserScript(WKUserScript(
            source: bootstrap + injector, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.loadHTMLString("<html><body>Isolated security fixture</body></html>", baseURL: URL(string: "https://example.com/"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            print("FAIL: WebKit world probe timed out")
            exit(1)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let value = message.body as? [String: Any] { nativeCalls.append(value) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                for _ in 0..<100 {
                    if nativeCalls.contains(where: { $0["action"] as? String == "gmXmlhttpRequest" }) { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                let leaked = try await webView.evaluateJavaScript("Boolean(window.__privateExecution || window.GM || window.browser)") as? Bool
                precondition(leaked == false, "isolated authority must not appear in MAIN")
                let originalCalls = nativeCalls.count
                _ = try await webView.evaluateJavaScript("""
                window.postMessage({type:'wblock-gm-xhr-request',bridgeId:'observed',scriptId:'private-script',id:'forged',url:'https://api.example/forged'},'*');
                window.postMessage({type:'wblock-gm-storage-set',bridgeId:'observed',scriptId:'private-script',key:'private-key',rawValue:'false',requestId:'forged'},'*');
                window.postMessage({type:'wblock:gm-port-message',portName:'observed::stream',message:'forged'},'*');
                true;
                """)
                try await Task.sleep(nanoseconds: 500_000_000)
                precondition(nativeCalls.count == originalCalls, "MAIN messages must not invoke native GM")
                precondition(nativeCalls.contains { $0["action"] as? String == "setUserScriptStorageValue" && $0["key"] as? String == "private-key" })
                precondition(nativeCalls.contains { $0["action"] as? String == "gmXmlhttpRequest" && $0["url"] as? String == "https://api.example/legitimate" })
                let privateResponse: Bool = try await withCheckedThrowingContinuation { continuation in
                    webView.evaluateJavaScript(
                        "Boolean(window.__privateExecution && window.__privateResponse)",
                        in: nil, in: WKContentWorld.world(name: "wBlock-security-probe")
                    ) { result in
                        switch result {
                        case .success(let value): continuation.resume(returning: value as? Bool == true)
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                    }
                }
                precondition(privateResponse == true, "genuine GM response must remain functional in the isolated world")
                print("PASS: real WebKit worlds isolate GM execution and reject forged page messages")
                exit(0)
            } catch {
                print("FAIL: \(error)")
                exit(1)
            }
        }
    }
}

@main struct WorldIsolationTest {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let probe = WorldProbe()
        try probe.start()
        withExtendedLifetime(probe) { app.run() }
    }
}
