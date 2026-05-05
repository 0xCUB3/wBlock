# Native Filter Compiler Replacement Plan

Branch: `native-filter-compiler-replacement`

Goal: replace SafariConverterLib/AdGuard conversion with a wBlock-owned, fully modular filter compiler and advanced-rule runtime that can live either inside wBlock or as a standalone Swift package.

This is a strict implementation plan, not a commitment that Safari can match uBlock Origin feature-for-feature. Safari’s platform model imposes hard limits. The replacement must expose those limits explicitly through metrics and tests instead of silently dropping rules.

## 1. Research baseline

### 1.1 Safari Content Blocker API

Primary source: Apple, “Creating a content blocker”  
URL: https://developer.apple.com/documentation/SafariServices/creating-a-content-blocker

Safari content blocker rules are precompiled JSON arrays. Each rule has:

- `trigger`
  - required: `url-filter`
  - optional: `url-filter-is-case-sensitive`
  - optional: `if-domain` / `unless-domain`
  - optional: `resource-type`
  - optional: `load-type`
  - optional: `if-top-url` / `unless-top-url`
  - optional: `if-frame-url` / `unless-frame-url`
  - optional: `load-context`
- `action`
  - `block`
  - `block-cookies`
  - `css-display-none`
  - `ignore-previous-rules`
  - `make-https`

Key limits:

- Safari JSON is declarative. It cannot run arbitrary matching code.
- Safari regex support is a subset, not full PCRE/JS regex.
- `if-domain` and `unless-domain` are mutually exclusive.
- Exceptions must be emulated through `ignore-previous-rules` and rule ordering.
- Native Safari content blockers cannot implement HTML response filtering, response body rewriting, CNAME/IP resolution, or scriptlet injection.

### 1.2 Safari WebExtension Declarative Net Request

Primary source: Apple, “Blocking content with your Safari web extension”  
URL: https://developer.apple.com/documentation/safariservices/blocking-content-with-your-safari-web-extension

Safari WebExtensions support a subset of the WebExtensions Declarative Net Request API:

- action types include `block`, `allow`, `upgradeScheme`, `allowAllRequests`; `redirect` requires Safari 15.4+ and host permissions; `modifyHeaders` requires Safari 16.4+ and additional user permissions.
- resource types include `main_frame`, `sub_frame`, `stylesheet`, `script`, `image`, `font`, `xmlhttprequest`, `ping`, `media`, `websocket`, `other`.
- conditions include `domainType`, `excludedResourceTypes`, `isUrlFilterCaseSensitive`, `regexFilter`, and `resourceTypes`.

Implication for wBlock:

- The content blocker targets should remain the primary network-blocking path for privacy/performance and current app architecture.
- DNR can be considered later for selected advanced features, but it increases permission prompts and differs from the existing content-blocker extension model.

### 1.3 uBlock Origin syntax

Primary source: uBO Static filter syntax wiki  
URL: https://github.com/gorhill/ublock/wiki/static-filter-syntax

uBO supports most EasyList/ABP syntax and extends it with:

- pre-parsing directives: `!#include`, `!#if`, `!#else`, `!#endif`
- hosts-file interpretation
- network modifiers: `$1p`, `$3p`, `$all`, `$badfilter`, `$css`, `$domain`/`$from`, `$denyallow`, `$document`, `$elemhide`, `$generichide`, `$important`, `$match-case`, `$method`, `$ping`, `$popup`, `$strict1p`, `$strict3p`, `$to`, `$xhr`, `$websocket`
- modifier filters: `$csp`, `$redirect`, `$redirect-rule`, `$removeparam`, `$replace`, `$uritransform`, `$urlskip`, `$header`, `$permissions`
- static extended filters: cosmetic rules, procedural cosmetic filters, action operators, HTML filters, response-header filters, scriptlet injection

Hard Safari gaps:

- `$header`, response header matching/removal: not available in Safari content blockers.
- `$replace` and HTML filtering: not available in Safari content blockers; content-script approximations are late and incomplete.
- `$redirect`/`$redirect-rule`: not available in Safari content blockers; possibly partial via WebExtension DNR with extra permissions.
- `$removeparam`: not available in Safari content blockers; possibly partial via DNR redirect/query transform if supported and permissioned, or via page navigation script for top-level URLs only.
- scriptlets and procedural cosmetics: require WebExtension content scripts and a maintained runtime.
- CNAME/IP filters: unavailable without privileged DNS/network APIs.

### 1.4 SafariConverterLib current behavior and limitations

Primary source: AdGuard SafariConverterLib README  
URL: https://github.com/AdguardTeam/SafariConverterLib

SafariConverterLib already documents many Safari-imposed compromises:

- Not every filter rule can be supported natively; advanced rules require a separate extension.
- Regex rules are limited to Safari-supported regex.
- `$domain` has limitations, including no mixed positive/negative domain list in a single Safari trigger.
- Exceptions rely on `ignore-previous-rules` and ordering.
- HTML filtering rules are not supported and “will not be supported in the future” because Safari lacks the required capabilities.
- Several modifiers are unsupported or partial: `$header`, `$csp`, `$redirect`, `$removeparam`, `$replace`, `$to`, `$strict-first-party`, `$strict-third-party`, etc.

Implication:

- A full replacement can be faster and more controllable, but cannot magically unlock Safari capabilities.
- We should target “wBlock-native Safari compiler with uBO/ABP/AdGuard compatibility accounting,” not “full uBO clone.”

### 1.5 Existing open-source reference: adblock-rust

Primary source: Brave adblock-rust README  
URL: https://github.com/brave/adblock-rust/

adblock-rust is MPL-2.0 and supports network blocking, cosmetic filtering, resource replacements, hosts syntax, uBO syntax extensions, and iOS content-blocking syntax conversion.

Decision:

- Use as a behavioral reference and test oracle where useful.
- Do not vendor or bind it in phase 1. Rust FFI/WASM would complicate Apple builds, package boundaries, app review, binary size, and debugging.
- Revisit later only if native Swift implementation fails cost/performance targets.

## 2. Strategic decision

We will build a standalone, modular Swift package first, then integrate it into wBlock through a narrow adapter. The app’s existing behavior remains the default until the native compiler passes parity gates.

Package name proposal: `WBlockFilterCompiler`

Repository layout proposal inside this repo:

```text
Packages/
  WBlockFilterCompiler/
    Package.swift
    Sources/
      WBlockFilterCompiler/
        PublicAPI/
        Parsing/
        Preprocessing/
        IR/
        Planning/
        SafariJSON/
        AdvancedRules/
        Diagnostics/
        Utilities/
    Tests/
      WBlockFilterCompilerTests/
        Fixtures/
```

The package must have no dependency on:

- `wBlockCoreService`
- app-group storage
- `SafariServices`
- SwiftUI/AppKit/UIKit
- generated protobuf models
- wBlock app models such as `FilterList`

The package may depend on:

- `Foundation`
- `CryptoKit` only if required for cache keys; prefer caller-owned hashing

The app integration layer will translate wBlock concepts into package input/output.

## 3. Public package API

Initial public API:

```swift
public struct FilterCompilerConfiguration: Sendable {
    public var dialects: Set<FilterDialect>
    public var target: CompilationTarget
    public var platform: FilterPlatform
    public var safariVersion: SafariCompatibilityVersion
    public var enabledCapabilities: Set<CompilerCapability>
    public var strictMode: Bool
}

public enum FilterDialect: Sendable {
    case abp
    case ublockOrigin
    case adGuard
    case hosts
    case auto
}

public enum CompilationTarget: Sendable {
    case safariContentBlocker
    case safariWebExtensionAdvanced
    case diagnosticsOnly
}

public struct FilterSource: Sendable {
    public var identifier: String
    public var displayName: String
    public var url: URL?
    public var text: String
}

public struct FilterCompilationResult: Sendable {
    public var safariRulesJSON: String
    public var safariRuleCount: Int
    public var advancedRules: AdvancedRuleBundle
    public var diagnostics: CompilationDiagnostics
    public var unsupportedRules: [UnsupportedRule]
    public var fingerprints: CompilationFingerprints
}

public protocol FilterCompiling: Sendable {
    func compile(_ sources: [FilterSource], configuration: FilterCompilerConfiguration) throws -> FilterCompilationResult
}
```

Non-goals for the package API:

- no file I/O requirement
- no app group knowledge
- no content blocker reload knowledge
- no assumptions about wBlock’s five-target distribution

## 4. Internal architecture

Pipeline:

```text
FilterSource text
  -> LineReader / ContinuationNormalizer
  -> Preprocessor
  -> DialectDetector
  -> RuleParser
  -> RuleNormalizer
  -> BadfilterResolver
  -> RulePlanner
  -> SafariJSONWriter
  -> AdvancedRuleEmitter
  -> Diagnostics
```

### 4.1 LineReader / ContinuationNormalizer

Responsibilities:

- normalize LF/CRLF safely
- preserve source line numbers for diagnostics
- support uBO long-line continuations where a line ends with ` \` and the next line is indented
- avoid Swift `Character` hot loops where possible

### 4.2 Preprocessor

Responsibilities:

- evaluate `!#if`, `!#else`, `!#endif`
- track line inclusion/exclusion
- process `!#include` only through a caller-provided resolver in later phases
- default package behavior: no network I/O

Important platform constants:

For uBO-oriented lists, `ext_ublock` should be true only if wBlock intentionally opts into uBO-specific sections. This is risky because some included rules require capabilities wBlock may not have. We need two modes:

- `safariCompatible`: `env_safari = true`, `ext_ublock = false`, `adguard = false`
- `uboCompat`: `env_safari = true`, `ext_ublock = true`, `adguard = false`, unsupported uBO-only rules counted

The default migration mode should be `safariCompatible`. `uboCompat` is enabled per known-good list.

### 4.3 Parser

Parse to an intermediate representation, not directly to JSON.

Core IR categories:

```swift
public enum ParsedRule {
    case network(NetworkRule)
    case cosmetic(CosmeticRule)
    case cosmeticException(CosmeticExceptionRule)
    case scriptlet(ScriptletRule)
    case scriptletException(ScriptletExceptionRule)
    case proceduralCosmetic(ProceduralCosmeticRule)
    case htmlFiltering(HTMLFilteringRule)
    case modifier(ModifierRule)
    case badfilter(BadfilterRule)
    case comment
    case unsupported(UnsupportedRule)
}
```

### 4.4 RuleNormalizer

Responsibilities:

- alias mapping:
  - `$css` -> `$stylesheet`
  - `$xhr` -> `$xmlhttprequest`
  - `$1p` -> `$first-party`
  - `$3p` -> `$third-party`
  - `$frame` -> `$subdocument` / Safari child-document mapping
  - `$from` -> `$domain`
- normalize hostnames to lowercase ASCII/punycode
- normalize domains for Safari `if-domain`/`unless-domain`
- normalize hosts-file entries to `||host^`
- canonicalize cosmetic selector strings where safe

### 4.5 BadfilterResolver

`$badfilter` must be processed before output. It disables matching rules and should not become a Safari rule.

Strict acceptance criterion:

- The resolver must use canonical rule identity, not raw string equality only.
- If a badfilter rule cannot be matched confidently, emit a diagnostic.

### 4.6 RulePlanner

The planner is the most important correctness layer.

Responsibilities:

- order Safari actions so `ignore-previous-rules` behaves as expected
- split mixed positive/negative domain rules into multiple Safari-compatible rules where possible
- decide when to emit `if-domain`, `unless-domain`, `if-top-url`, or `unless-top-url`
- decide when to generate advanced rules instead of Safari JSON
- group selectors to reduce Safari rule count
- deduplicate identical trigger/action pairs
- enforce per-target budget and rule count limits

Rule ordering principles:

1. blocking network rules
2. cookie stripping rules
3. make-https rules, if supported/used
4. native cosmetic hiding rules
5. scoped exceptions using `ignore-previous-rules`
6. wBlock disabled-site rules appended last, preserving current behavior

This ordering must be validated against Safari, because `ignore-previous-rules` semantics are easy to get subtly wrong.

### 4.7 SafariJSONWriter

Responsibilities:

- streaming compact JSON output
- no large `[[String: Any]]` construction for production paths
- stable output order for deterministic cache keys
- JSON string escaping
- optional debug pretty-printer for tests only

### 4.8 AdvancedRuleEmitter

Responsibilities:

- emit a package-owned advanced-rule bundle format, not AdGuard’s `advancedRulesText`
- include source mappings and rule type counts
- initially serialize as JSON for debuggability
- later optional binary index for runtime speed

Proposed shape:

```json
{
  "format": "wblock-advanced-rules-v1",
  "scriptlets": [],
  "scriptletExceptions": [],
  "proceduralCosmetics": [],
  "removeparam": [],
  "redirect": [],
  "unsupportedButKnown": []
}
```

## 5. Feature support matrix

Legend:

- P0: required before native compiler can be hidden behind feature flag
- P1: required before defaulting for normal lists
- P2: required before switching to uBO-first defaults
- P3: nice-to-have / may stay unsupported
- Impossible: Safari limitation or unacceptable permission cost

| Feature | Target | Priority | Notes |
|---|---|---:|---|
| comments / metadata | parser | P0 | preserve diagnostics only |
| CRLF / LF splitting | parser | P0 | current converter bug class prevention |
| uBO line continuations | parser | P1 | needed for correctness on newer lists |
| `!#if` / `!#else` / `!#endif` | preprocessor | P0 | already exists in wBlock; move/package it |
| `!#include` | preprocessor | P1 | package uses resolver protocol, app performs fetch/cache |
| hosts entries | Safari JSON | P1 | important for security/privacy lists |
| `||host^` | Safari JSON | P0 | core network blocking |
| `|` anchors | Safari JSON | P0 | core ABP syntax |
| `^` separator | Safari JSON | P0 | core ABP syntax |
| `*` wildcard | Safari JSON | P0 | core ABP syntax |
| regex network rules | Safari JSON | P1 | only Safari-compatible regex; otherwise unsupported |
| `@@` network exceptions | Safari JSON | P0 | planner/order-sensitive |
| `$script`, `$image`, `$stylesheet`, `$font`, `$media`, `$xhr`, `$websocket`, `$ping` | Safari JSON | P0/P1 | Safari resource-type mapping |
| `$document`, `$popup` | Safari JSON | P1 | map carefully to top-document/popup behavior |
| `$third-party`, `$first-party` | Safari JSON | P0 | Safari `load-type` |
| `$domain` / `$from` | Safari JSON | P0 | split unsupported mixed forms where possible |
| `$badfilter` | parser/planner | P1 | needed for list correctness |
| `$important` | planner | P1 | affects exception handling |
| `$match-case` | Safari JSON | P1 | only for regex-compatible cases |
| `$denyallow` | planner | P2 | expands to block + exception rules; budget risk |
| `$to` | partial | P2 | not directly supported by content blocker; approximate with URL pattern or DNR later |
| `$strict1p` / `$strict3p` | unsupported initially | P3 | Safari load-type is eTLD-ish, not exact hostname semantics |
| basic `##` cosmetic | Safari JSON | P0 | css-display-none |
| domain-scoped cosmetics | Safari JSON | P0 | `if-domain` / top URL choices |
| `#@#` cosmetic exceptions | planner | P1 | hard with grouped selectors; requires tests |
| procedural cosmetics | advanced runtime | P2 | content script runtime |
| `##+js(...)` uBO scriptlets | advanced runtime | P2 | high value for uAssets |
| AdGuard `#%#//scriptlet(...)` | advanced runtime | P2 | compatibility with existing lists |
| scriptlet exceptions | advanced runtime | P2 | needed to avoid breakage |
| `$removeparam` | advanced/DNR maybe | P2/P3 | partial only; explicit diagnostics |
| `$redirect` / `$redirect-rule` | DNR maybe | P3 | requires permissions; not in content blockers |
| `$csp` / `$permissions` | DNR maybe | P3 | header modification permissions; default off |
| `$header` / `$removeheader` | unsupported/DNR maybe | P3 | extra permissions and partial API coverage |
| `$replace` | impossible/partial content script | P3 | response body replacement unavailable in Safari content blocker |
| HTML filtering `##^` | Impossible | n/a | Safari lacks required API |
| CNAME/IP filtering | Impossible | n/a | no DNS visibility |

## 6. Costs and drawbacks

### 6.1 Engineering cost

Estimated effort for robust replacement:

- Package skeleton + test harness: 1-2 days
- Parser/IR for static network rules: 1-2 weeks
- Safari JSON planner/writer: 1-2 weeks
- Exceptions and `badfilter`: 1 week
- Cosmetic rules and exceptions: 1-2 weeks
- Integration behind feature flag: 2-4 days
- Parity corpus and benchmarks: 1 week
- Advanced runtime MVP: 3-6 weeks depending on scriptlet scope
- Removing SafariConverterLib and old advanced engine: 1-2 weeks after confidence gates

Realistic total: 6-12 weeks for a serious replacement, longer if we chase uBO scriptlet parity.

### 6.2 Maintenance cost

- Filter syntax changes over time.
- uBO and AdGuard scriptlet libraries evolve quickly.
- Site breakage reports will become wBlock compiler bugs, not upstream converter bugs.
- A standalone package needs semver, API discipline, fixtures, and release notes.

### 6.3 Correctness risk

- `@@` exceptions can accidentally disable too much in Safari due to `ignore-previous-rules`.
- Grouping cosmetic selectors improves rule count but makes `#@#` exceptions harder.
- Domain matching semantics differ between ABP/uBO/AdGuard/Safari.
- Safari accepts a limited regex dialect. Invalid JSON rules may fail content blocker reload.

### 6.4 Performance risk

A native compiler can be faster, but only if we avoid:

- repeated whole-target recompilation
- `String` character-by-character hot paths
- huge Swift dictionary JSON trees
- excessive rule expansion for `$denyallow`, entity domains, any-TLD domains

### 6.5 Product risk

- Some users may see worse blocking if unsupported advanced uBO rules are silently ignored.
- More WebExtension permissions for DNR/header/redirect features may hurt trust and App Store review.
- iOS/macOS behavior may diverge.

Mitigation: no default behavior change until parity metrics pass.

## 7. Performance and caching strategy

Current app pipeline combines assigned filter files per target, then calls SafariConverterLib per target.

Replacement target architecture:

```text
Filter list A -> compiled artifact A
Filter list B -> compiled artifact B
Filter list C -> compiled artifact C
Target 1 = merge artifacts A+C
Target 2 = merge artifacts B
```

Compiled artifact contents:

- source fingerprint
- compiler version
- configuration fingerprint
- Safari rule fragments or binary-planned IR
- advanced-rule fragments
- diagnostics summary

Cache keys must include:

- filter source hash
- compiler semantic version
- platform constants mode
- Safari compatibility version
- enabled capabilities
- embedded compatibility rules version

Strict performance goals:

- compile unchanged list: 0 ms package work; app loads artifact
- target rebuild with unchanged lists but changed disabled sites: no filter parse, no compile
- target JSON merge: streaming only
- memory ceiling: no full combined target text in memory
- output stable enough for deterministic hashes

## 8. Testing strategy

### 8.1 Unit tests

Package tests:

- parser tests per syntax family
- normalizer tests
- badfilter tests
- Safari regex translation tests
- domain punycode/lowercase tests
- exception ordering tests
- cosmetic grouping and ungrouping tests
- JSON validity tests

### 8.2 Corpus tests

Fixtures:

- EasyList subset
- EasyPrivacy subset
- uAssets `filters.txt`, `privacy.txt`, `badware.txt`, `unbreak.txt`, `quick-fixes.txt`
- AdGuard optimized Safari lists currently used by wBlock
- representative regional lists
- custom user rules

Metrics per corpus:

- parsed count
- Safari-native count
- advanced count
- unsupported count by reason
- generated Safari JSON rule count
- generated JSON byte size
- compile duration
- peak memory if measurable

### 8.3 Differential tests

For static supported rules only:

- compare native output semantics against SafariConverterLib where possible before removal
- compare selected parser behavior against adblock-rust/uBO documentation fixtures where useful

### 8.4 Real Safari reload tests

On-device/simulator smoke:

- generated JSON reloads successfully for every target
- empty output uses safe no-op rule or accepted empty behavior consistent with current wBlock handling
- disabled-site injection still works
- large list combinations do not exceed Safari limits

## 9. Integration plan

### Phase A: branch and package skeleton

Status: branch created.

Tasks:

1. Add `Packages/WBlockFilterCompiler` Swift package.
2. Add basic public API types.
3. Add diagnostics-only compiler that classifies rules but emits `[]` or no-op JSON.
4. Add tests and fixtures.
5. Do not touch app behavior.

Acceptance:

- package tests pass via `swift test`
- wBlock still builds using SafariConverterLib
- no app behavior changes

### Phase B: app adapter behind explicit flag

Tasks:

1. Add `NativeFilterCompilerAdapter` in `wBlockCoreService`.
2. Add internal-only compiler selection:
   - default: SafariConverterLib
   - opt-in: native diagnostics/native compile
3. Keep existing cache filenames separate:
   - old: current `.base.json` cache
   - native: `.native.base.json` or versioned artifact directory
4. Log native diagnostics but continue using SafariConverterLib by default.

Acceptance:

- default path byte-for-byte behavior unchanged apart from logs if enabled
- internal flag can run native compiler for diagnostics without saving output

### Phase C: static network MVP

Tasks:

- implement parser/normalizer for P0 network rules
- implement streaming Safari JSON writer
- implement basic planner without advanced runtime
- support disabled-site rule injection via app layer or package hook

Acceptance:

- common network fixtures compile to valid Safari JSON
- no unsupported rule is silently ignored
- performance baseline collected

### Phase D: exceptions and cosmetics

Tasks:

- robust `@@` planning
- `$important`
- `$badfilter`
- basic `##` and `#@#`
- selector validation policy

Acceptance:

- exception/cosmetic fixtures pass
- generated JSON reloads in Safari smoke tests
- unsupported rate for default wBlock lists is documented

### Phase E: per-list artifacts

Tasks:

- compile each filter list independently
- cache package artifacts by source hash/config
- merge artifacts per target
- preserve affinity directives and target distribution

Acceptance:

- unchanged lists are not reparsed
- target rebuild time improves versus SafariConverterLib path
- memory profile improves or is neutral

### Phase F: advanced runtime MVP

Tasks:

- define wBlock advanced-rule JSON format
- update WebExtension content script/background to consume it
- implement domain matcher in JS
- implement procedural cosmetics MVP
- implement top scriptlets by observed uAssets usage
- implement scriptlet exception matching

Acceptance:

- advanced runtime handles selected high-impact rules
- no regression in existing userscripts/zapper flows
- no additional broad host permissions unless explicitly approved

### Phase G: switch default to native for internal builds

Tasks:

- default native in debug/internal builds only
- collect metrics from normal use
- keep one-click fallback to SafariConverterLib

Acceptance:

- rule count and unsupported metrics are stable
- no major site-breakage regressions in dogfood

### Phase H: remove SafariConverterLib

Prerequisites:

- native compiler is default for at least one release/beta cycle
- fallback has not been needed for known supported lists
- advanced runtime covers current wBlock compatibility rules
- generated JSON reload reliability is equal or better

Deletion targets:

- remove `internal import ContentBlockerConverter`
- remove `internal import FilterEngine`
- remove SafariConverterLib package reference from Xcode project
- remove Package.resolved SafariConverterLib pin
- delete `ContentBlockerService.convertRules` SafariConverterLib path
- delete `buildCombinedFilterEngine`, `clearFilterEngine`, and FilterEngine binary build code if replaced by package/runtime artifacts
- delete old `advancedRulesText` plumbing once native advanced-rule bundle is fully adopted
- delete compatibility shims and old cache migration after one or more releases

## 10. Unobtrusive branch rules

Until Phase G:

- no user-facing default changes
- no default filter URL changes
- no removal of SafariConverterLib
- no changes to app-store-visible text
- all native artifacts stored separately from current converter cache
- all native logs/diagnostics behind debug/internal flag
- fallback path remains one function call away

## 11. Package separation rules

The package must remain separable:

- all public APIs documented
- no reference to `GroupIdentifier`
- no reference to `ContentBlockerTargetInfo`
- no reference to `FilterList`
- no references to app localization resources
- deterministic tests runnable with `swift test`
- fixtures licensed/attributed if copied from external projects
- semantic version string exposed by package

The wBlock-specific adapter owns:

- reading filter files from the app group
- target distribution
- disabled sites
- zapper-generated rules
- affinity directives, unless later generalized
- cache directory placement
- content blocker reloads
- metrics logging into wBlock logs

## 12. Immediate next implementation checklist

1. Create package skeleton under `Packages/WBlockFilterCompiler`.
2. Add public API and diagnostics models.
3. Add parser classifier that distinguishes:
   - comment
   - preprocessor
   - network
   - cosmetic
   - scriptlet
   - procedural cosmetic
   - HTML filtering
   - modifier-only/unsupported
4. Add a tiny fixture suite.
5. Add a command-line/dev-only benchmark script that downloads or reads current lists and prints classification metrics.
6. Add no app integration until package tests exist.

## 13. Go/no-go gates

Do not remove SafariConverterLib unless all are true:

- default wBlock selected lists compile and reload successfully on macOS and iOS
- unsupported rules are explainable and visible in internal diagnostics
- native conversion is materially faster on clean conversion or materially faster on update due to per-list caching
- memory use is not worse
- advanced rule runtime covers current embedded compatibility rules and common uAssets scriptlets chosen for support
- App Store permission footprint does not increase unexpectedly
- rollback plan exists for one release
