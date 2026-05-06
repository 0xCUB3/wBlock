# WBlockFilterCompiler

Standalone Swift package for compiling ABP/uBO/AdGuard/hosts-style filter text into Safari content blocker JSON plus diagnostics.

This package is intentionally modular:

- no dependency on wBlock app models
- no app-group storage
- no SafariServices reload logic
- no SwiftUI/AppKit/UIKit
- no network fetching

The host app owns file I/O, caching, target distribution, disabled-site rules, and content blocker reloads.

## Library usage

```swift
import WBlockFilterCompiler

let source = FilterSource(
    identifier: "easylist",
    displayName: "EasyList",
    text: filterText
)

var configuration = FilterCompilerConfiguration()
configuration.platform = .safariCompatible

let result = try NativeFilterCompiler().compile([source], configuration: configuration)
print(result.safariRulesJSON)
print(result.unsupportedRules.count)
```

## CLI usage

```bash
swift run wblock-filter-compiler --pretty list.txt
swift run wblock-filter-compiler --diagnostics-only --ubo-compat list.txt
swift run wblock-filter-compiler --output content-blocker.json list.txt
swift run wblock-filter-compiler --advanced-runtime --advanced-output advanced-runtime.json list.txt
swift run wblock-filter-compiler --ubo-compat --lookup https://example.com list.txt
```

## Current implementation status

Implemented:

- line normalization and uBO continuation folding
- conditional preprocessing for conservative Safari and uBO-compatible identities
- network rule parsing for common ABP/uBO syntax
- hosts-file rule parsing
- Safari URL filter translation for common ABP anchors/separators/wildcards and regex rules
- resource type/load type/domain/match-case/important/badfilter handling
- native cosmetic rules with grouping
- exact cosmetic exceptions and generic-rule `unless-domain` planning
- Safari JSON emission
- diagnostics and unsupported-rule accounting
- experimental WebExtension advanced-rule bundle for scriptlets and procedural cosmetics
- uBO `##+js(...)` scriptlet-name compatibility mapping to the bundled WebExtension scriptlet engine

Still incomplete:

- production hardening for advanced-rule runtime edge cases
- scriptlet/procedural-cosmetic exception planning
- redirect/removeparam/header/csp support
- mixed positive/negative domain splitting
- full uBO parity
