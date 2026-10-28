// WKWebView probe for sim/calibrate.ts. Compiles a Safari content-blocker JSON
// file, loads one page with the rules attached, waits, and prints one line:
//   RESULT {"rejected": "..."}                    the rule list did not compile
//   RESULT {"navigation": "failed"}               the top document did not load
//   RESULT {"hidden": ["id", ...]}                data-cs elements with display:none
// Request reachability is observed by the Node server, not here.
//
// Build: swiftc -O sim/calibrate.swift -o sim/.build/calibrate-probe
// Run:   sim/.build/calibrate-probe <rules.json> <page-url> <wait-seconds>

import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 4, let waitSeconds = Double(args[3]) else {
    print("usage: calibrate-probe <rules.json> <page-url> <wait-seconds>")
    exit(2)
}
let rulesJSON = try! String(contentsOfFile: args[1], encoding: .utf8)
let pageURL = URL(string: args[2])!

let collectHidden = """
JSON.stringify(Array.from(document.querySelectorAll('[data-cs]'))
  .filter(function (e) { return getComputedStyle(e).display === 'none'; })
  .map(function (e) { return e.getAttribute('data-cs'); }))
"""

final class Probe: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let waitSeconds: Double

    init(configuration: WKWebViewConfiguration, waitSeconds: Double) {
        webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        self.waitSeconds = waitSeconds
        super.init()
        webView.navigationDelegate = self
    }

    func report(_ line: String) {
        print("RESULT \(line)")
        fflush(stdout)
        exit(0)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + waitSeconds) {
            self.webView.evaluateJavaScript(collectHidden) { result, error in
                if let hidden = result as? String {
                    self.report("{\"hidden\": \(hidden)}")
                } else {
                    self.report("{\"error\": \"\(error.map { "\($0)" } ?? "no result")\"}")
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report("{\"navigation\": \"failed\"}")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report("{\"navigation\": \"failed\"}")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("calibrate-\(UUID().uuidString)")
let store = WKContentRuleListStore(url: storeDirectory)!
var probe: Probe!

store.compileContentRuleList(forIdentifier: "calibrate", encodedContentRuleList: rulesJSON) { list, error in
    if let error {
        print("RESULT {\"rejected\": \"\(error.localizedDescription)\"}")
        fflush(stdout)
        exit(0)
    }
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.userContentController.add(list!)
    probe = Probe(configuration: configuration, waitSeconds: waitSeconds)
    probe.webView.load(URLRequest(url: pageURL))
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        probe.report("{\"error\": \"timeout\"}")
    }
}

app.run()
