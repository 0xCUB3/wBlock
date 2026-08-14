//
//  UserStyleCompilerExecutionHost.swift
//  wBlockCoreService
//
// Public WebKit-only compiler isolation. Each call owns a nonpersistent web view
// and a Blob Worker; both are discarded after the call so a failed WebContent
// process cannot poison the next compilation.
//

import Foundation
import WebKit

private final class UserStyleCompilerResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<[String: Any], Error>?

    func store(_ value: Result<[String: Any], Error>) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func take() -> Result<[String: Any], Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
final class UserStyleCompilerExecutionHost {
    static let productionDeadline: TimeInterval = 10
    private let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
    }

    func execute(runtime: String, request: [String: Any], adapter: String) async throws -> [String: Any] {
        let deadline: TimeInterval = {
#if DEBUG
            return UserStyleCompiler.debugDeadlineOverride ?? Self.productionDeadline
#else
            return Self.productionDeadline
#endif
        }()
        let function = """
        const runtime = runtimeArgument;
        const request = requestArgument;
        const adapter = adapterArgument;
        const deadline = deadlineArgument;
        return await new Promise(resolve => {
            let worker;
            let hostTimer;
            let settled = false;
            let url;
            const finish = value => {
                if (settled) return;
                settled = true;
                if (hostTimer) clearTimeout(hostTimer);
                if (worker) worker.terminate();
                if (url) URL.revokeObjectURL(url);
                resolve(value);
            };
            const source = `
                self.onmessage = async function(event) {
                    const timer = setTimeout(function() {
                        self.postMessage({error: "__WBLOCK_TIMEOUT__"});
                    }, event.data.deadline * 1000);
                    try {
                        // The runtime is fixed and bundled, but deny browser capabilities
                        // it does not need so compiler input cannot reach network/storage APIs.
                        for (const name of ["fetch", "XMLHttpRequest", "WebSocket", "EventSource", "importScripts", "Worker", "SharedWorker", "indexedDB", "caches", "navigator", "crypto", "BroadcastChannel", "webkit"]) {
                            try { Object.defineProperty(self, name, {value: undefined, writable: false, configurable: false}); }
                            catch (_) { try { self[name] = undefined; } catch (_) {} }
                        }
                        // Less's browser UMD entry only needs an inert bootstrap shape.
                        self.window = self;
                        self.less = {onReady: false, async: true};
                        self.document = {currentScript: null, getElementsByTagName: function() { return []; }};
                        (0, eval)(event.data.runtime);
                        const compile = (0, eval)("(" + event.data.adapter + ")");
                        const result = await compile(event.data.request);
                        clearTimeout(timer);
                        const response = typeof result === "string" ? JSON.parse(result) : result;
                        self.postMessage(response);
                    } catch (error) {
                        clearTimeout(timer);
                        self.postMessage({error: error && error.message ? error.message : String(error)});
                    }
                };
            `;
            url = URL.createObjectURL(new Blob([source], {type: "text/javascript"}));
            worker = new Worker(url);
            worker.onmessage = event => finish(event.data);
            worker.onerror = event => finish({error: event.message || "Worker failed"});
            // This timer runs in the page, not the compiler Worker, so synchronous
            // compiler loops cannot prevent it from terminating that Worker.
            hostTimer = setTimeout(function() {
                finish({error: "__WBLOCK_TIMEOUT__"});
            }, deadline * 1000);
            worker.postMessage({runtime: runtime, request: request, adapter: adapter, deadline: deadline});
        });
        """
        let value = try await webView.callAsyncJavaScript(
            function,
            arguments: ["runtimeArgument": runtime, "requestArgument": request, "adapterArgument": adapter, "deadlineArgument": deadline],
            in: nil,
            contentWorld: .page
        )
        guard let response = value as? [String: Any] else {
            throw UserStyleCompiler.CompilationError(message: String(localized: "Userstyle compiler returned an invalid response.", comment: "Userstyle compiler response error"))
        }
        if response["error"] as? String == "__WBLOCK_TIMEOUT__" {
            throw UserStyleCompiler.CompilationError(message: String(localized: "Userstyle compiler timed out.", comment: "Userstyle compiler timeout error"))
        }
        return response
    }
}

extension UserStyleCompilerExecutionHost {
    private nonisolated static let executionLock = NSLock()

    nonisolated static func run(runtime: String, request: [String: Any], adapter: String) throws -> [String: Any] {
        guard !Thread.isMainThread else {
            throw UserStyleCompiler.CompilationError(message: String(localized: "Userstyle compiler must not run on the main thread.", comment: "Userstyle compiler main thread error"))
        }
        executionLock.lock()
        defer { executionLock.unlock() }

        let semaphore = DispatchSemaphore(value: 0)
        let result = UserStyleCompilerResultBox()
        DispatchQueue.main.async {
            Task { @MainActor in
                let host = UserStyleCompilerExecutionHost()
                do { result.store(.success(try await host.execute(runtime: runtime, request: request, adapter: adapter))) }
                catch { result.store(.failure(error)) }
                semaphore.signal()
            }
        }
        semaphore.wait()
        guard let value = result.take() else {
            throw UserStyleCompiler.CompilationError(message: String(localized: "Userstyle compiler returned an invalid response.", comment: "Userstyle compiler response error"))
        }
        return try value.get()
    }
}
