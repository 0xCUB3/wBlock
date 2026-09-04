#!/usr/bin/env swift
import Foundation

func require(_ c: Bool, _ m: String) { guard c else { fputs("FAIL: \(m)\n", stderr); exit(1) } }
let editor = try String(contentsOfFile: "wBlock/CodeMirrorTextEditor.swift", encoding: .utf8)

// #672: no white flash before CodeMirror paints its themed background.
require(editor.contains("webView.isOpaque = false") && editor.contains("webView.backgroundColor = .clear"), "iOS web view must be transparent")
require(editor.contains("webView.underPageBackgroundColor = .clear"), "iOS under-page layer must be clear so nothing white shows through")
require(editor.contains("webView.setValue(false, forKey: \"drawsBackground\")"), "macOS web view must not draw its background")
require(editor.contains("webView.alphaValue = 0") && editor.contains("webView.alpha = 0"), "web view starts hidden on both platforms")
require(editor.contains("case \"ready\":\n                hasBootedEditor = true\n                revealWebView()"), "web view is revealed when the editor reports ready")
require(editor.contains("didFailProvisionalNavigation") && editor.contains("didFail navigation"), "navigation failures must still reveal the view")
print("PASS test_issue_672_editor_flash")
