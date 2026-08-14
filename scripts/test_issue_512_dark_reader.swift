#!/usr/bin/env swift
import Foundation

func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func read(_ path: String) -> String { guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { fail("read \(path)") }; return s }
func run(_ path: String, _ args: [String]) -> (Int32, String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
    do { try p.run() } catch { fail("launch \(path): \(error)") }
    p.waitUntilExit(); return (p.terminationStatus, String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
}

let root = FileManager.default.currentDirectoryPath
let manager = read("wBlockCoreService/UserScriptManager.swift")
let handler = read("wBlockCoreService/WebExtensionRequestHandler.swift")
let source = read("wBlockCoreService/BundledUserscripts/dark-reader.user.js")
let vendor = read("wBlockCoreService/Vendored/DarkReader/darkreader-api.min.js")
let provenance = read("wBlockCoreService/Vendored/DarkReader/PROVENANCE.md")
let localizedDescription = "Dark Reader's MIT-licensed API engine, bundled for wBlock (beta; without the full site-fix database)."
let locales = try! FileManager.default.contentsOfDirectory(atPath: "wBlock").filter { $0.hasSuffix(".lproj") && $0 != "en.lproj" }
for locale in locales { guard !read("wBlock/\(locale)/Localizable.strings").contains("\"\(localizedDescription)\" = \"\(localizedDescription)\";") else { fail("English Dark Reader description copied into \(locale)") } }

let url = "https://bundled.wblock.invalid/dark-reader.user.js"
guard manager.contains("name: \"Dark Reader\"") && manager.contains("darkReaderURL") else { fail("Dark Reader is not registered") }
guard manager.contains("url: darkReaderURL") && manager.contains("isEnabledByDefault: false") && manager.contains("bundledContent: BundledUserScriptSources.darkReader") else { fail("Dark Reader must be beta, bundled, and default-off") }
guard manager.components(separatedBy: "darkReaderURL").count >= 2 && !manager.contains("darkReaderURL = \"\"") else { fail("stable Dark Reader URL missing") }
guard source.components(separatedBy: "@name         Dark Reader").count == 2 else { fail("Dark Reader metadata missing") }
guard source.contains("@inject-into  content") && source.contains("@run-at       document-start") else { fail("content/document-start metadata missing") }
guard source.contains("@match        http://*/*") && source.contains("@match        https://*/*") else { fail("ordinary page matches missing") }
guard source.contains("@version      4.9.128-wblock.2") else { fail("Dark Reader adapter version missing") }
guard source.contains("api.auto();") && !source.contains("api.enable();") && source.contains("api.setFetchMethod(bridgeFetch)") && source.contains("GM_xmlhttpRequest") else { fail("system appearance adapter contract missing") }
guard !source.contains("api.Plugins.fetch") else { fail("adapter must use the supported setFetchMethod API") }
guard source.contains("data-wblock-userstyle") && vendor.contains("data-wblock-userstyle") else { fail("userstyle exclusion missing") }
guard !source.contains("fetch(\"http") && !source.contains("import(\"http") else { fail("runtime executable download present") }
guard provenance.contains("4.9.128") && provenance.contains("SHA-256") && provenance.contains("MIT") && provenance.contains("433921d71add2d8119025c3727fc8ff5357e54ac40dd068ad73ec45619f09206") else { fail("provenance is incomplete") }
guard FileManager.default.fileExists(atPath: "scripts/update_darkreader_vendor.py") && FileManager.default.fileExists(atPath: "scripts/build_darkreader_userscript.py") else { fail("reproducible vendor/build scripts are missing") }
guard manager.contains("getEnabledUserScriptsForURL") && manager.contains("enabledScripts = userScripts.filter { $0.isEnabled }") else { fail("disabled scripts are not excluded from descriptors") }
guard handler.contains("let userScripts = userScriptManager.getEnabledUserScriptsForURL(urlString)") else { fail("descriptor path does not use enabled native filtering") }
guard manager.contains("return hydrated.filter(BuiltInUserScripts.isCanonicalBundled)") else { fail("bundled descriptor filtering contract missing") }

let expectedVendorHash = "433921d71add2d8119025c3727fc8ff5357e54ac40dd068ad73ec45619f09206"
let hashResult = run("/bin/sh", ["-c", "shasum -a 256 wBlockCoreService/Vendored/DarkReader/darkreader-api.min.js | awk '{print $1}'"])
guard hashResult.0 == 0, hashResult.1.trimmingCharacters(in: .whitespacesAndNewlines) == expectedVendorHash else { fail("vendored payload hash mismatch") }
guard !vendor.contains("window.chrome") && !vendor.contains("chrome.runtime") && vendor.contains("__wblockDarkReaderChrome") else { fail("private Chrome shim contract missing") }
let updateScript = read("scripts/update_darkreader_vendor.py")
for marker in ["ce0b18e9a89caf7145292e7d7d2592b5bac664c49567fbf2d59c57a2bc7014e5", "terser@5.46.0", "629f0a0077c32cdad9b934a06100154c1a47aab00cfef0a88df6214cc4e58c47", expectedVendorHash] { guard updateScript.contains(marker) else { fail("update script marker missing: \(marker)") } }

let node = "/usr/bin/env"
let result = run(node, ["node", "--check", "wBlockCoreService/BundledUserscripts/dark-reader.user.js"])
guard result.0 == 0 else { fail("Dark Reader userscript syntax: \(result.1)") }
let vmScript = """
    const fs = require('fs'), vm = require('vm');
    const s = fs.readFileSync('wBlockCoreService/BundledUserscripts/dark-reader.user.js', 'utf8');
    const adapter = s.slice(s.indexOf('/* Dark Reader v4.9.128 is vendored above this adapter. */'));
    let autoCalls = 0, fetchMethod = null;
    const window = {DarkReader: {auto: () => {autoCalls += 1}, setFetchMethod: (f) => {fetchMethod = f}}};
    const context = {window, Response, GM_xmlhttpRequest: () => {}, console};
    vm.createContext(context); vm.runInContext(adapter, context);
    if ('chrome' in window || autoCalls !== 1 || typeof fetchMethod !== 'function') throw new Error('adapter mutated chrome or did not follow system appearance');
    """
let probe = run(node, ["node", "-e", vmScript])
guard probe.0 == 0 else { fail("direct JavaScript behavior: \(probe.1)") }
let bridgeProbe = """
const fs = require('fs'), vm = require('vm');
const s = fs.readFileSync('wBlockCoreService/BundledUserscripts/dark-reader.user.js', 'utf8');
const adapter = s.slice(s.indexOf('/* Dark Reader v4.9.128 is vendored above this adapter. */'));
let fetchMethod; const window = {DarkReader: {auto(){}, setFetchMethod(f){fetchMethod=f}}};
const context = {window, Response, GM_xmlhttpRequest(o){o.onload({response: new TextEncoder().encode('ok').buffer, status: 201, statusText: 'Created', responseHeaders: 'X-Test: yes\\r\\n'});}, console};
vm.createContext(context); vm.runInContext(adapter, context);
fetchMethod('https://example.invalid').then(async r => { if (new TextDecoder().decode(await r.arrayBuffer()) !== 'ok' || r.status !== 201 || r.statusText !== 'Created' || r.headers.get('X-Test') !== 'yes') throw new Error('bridge response mismatch'); }).catch(e => { console.error(e); process.exit(1); });
"""
let bridge = run(node, ["node", "-e", bridgeProbe])
guard bridge.0 == 0 else { fail("bridgeFetch behavior: \(bridge.1)") }

print("PASS: issue #512 Dark Reader integration")
