# Tube Cleaner & Player Cleaner test harness

Autonomous tests for the bundled Tube Cleaner and Player Cleaner userscripts
(`wBlockCoreService/BundledUserscripts/tube-cleaner.user.js` and
`player-cleaner.user.js`). They run in Playwright **WebKit** — the same engine
Safari uses — so results approximate real macOS/iOS Safari behavior without
needing a device or a human to report.

## Setup (once)

```sh
cd tests/tube-cleaner
npm install
npx playwright install webkit
```

## Deterministic gate — `run-tests.mjs`

Loads a synthetic page that mimics the real player DOM, injects the real
userscript at `document-start` in the page world (matching `@run-at` +
`@inject-into page`), and asserts the transformation actually happens.

Tube Cleaner scenarios: `fixture.html` / `fixture-noplaysinline.html` cover
macOS Safari, iPhone, legacy iPad mobile UAs, and modern iPadOS requesting the
desktop site as `MacIntel`. Mobile checks enforce Safari-native playback with a
non-persistent quality-only overlay, migration out of old black-screen
audio-only and fixed-quality loading states, visible video in portrait and
landscape, suppression of the separate mobile YouTube controls tree,
restoration of inline playback, preservation of the iOS ManagedMediaSource
restriction required for SABR playback, native chapter and WebVTT subtitle
mirroring (including token-gated caption metadata fallback), and k-anonymous
SponsorBlock skipping with a bounded session cache, precise boundary timers,
persistent category modes, manual skip, and Undo behavior.
`fixture-tube-cleaner-multiple.html` models retained
Shorts players and verifies native enhancements follow the visible playing
video. `fixture-tube-cleaner-early.html` creates the YouTube player from a
`<head>` script and enforces anti-flash CSS plus nativeization before
DOMContentLoaded and within one frame of insertion.

Player Cleaner scenarios:
- `fixture-player-cleaner.html` — opaque (blob) source, so the script enhances
  the existing `<video>` in place and must keep native controls on while the
  custom player keeps stripping them. Its MediaElement case verifies direct
  sources are also nativeized in place because that framework continues using
  its generated shell after startup; the shell remains intact and its chrome is
  hidden without lifecycle errors.
- `fixture-player-cleaner-replace.html` — a clean http(s) source, exercising the
  full cleanup path: the original `<video>` is retained (avoiding a second media
  load and preserving buffered state, poster, and caption tracks), the custom
  chrome is dropped, and controls survive an adversarial player.
- `fixture-player-cleaner-discovery.html` — five players exposing the media URL
  through different mechanisms (video.src, `<source>` child, descendant
  `data-src`, a mocked video.js `currentSource()`, a mocked JW Player playlist
  item); each must resolve to the right clean source. Negative cases ensure a
  poster `data-src` and a DASH `.mpd` never replace a working blob/MSE stream.
- `fixture-player-cleaner-shadow.html` — reproduces Archive.org's `<play-av>`:
  JW Player and its `<video>` live inside a shadow root. Verifies document-start
  `attachShadow` capture, one-frame nativeization, in-place pipeline retention,
  custom-chrome hiding, controls defense, and flat resources after removing and
  reattaching the shadow host.
- `fixture-player-cleaner-bare.html` — modern/custom players whose wrapper is
  not a recognized library class (Mux-style or bespoke). Verifies the bare-video
  fallback: a controls-less `<video>` in an unknown wrapper is enhanced in place
  (native controls forced on, source kept), while an ambient `autoplay muted
  loop` video and an already-native video are left untouched.
- `fixture-player-cleaner-relative.html` — players whose media URL is
  root-relative (a `<base>` makes it resolve to http(s)), as media APIs commonly
  expose (`/download/<item>/movie.mp4`). Verifies discovery resolves
  relative URLs from a JW playlist and from `data-src` to absolute before
  swapping in a clean `<video>`.
- `fixture-player-cleaner-upgrade.html` — a Plyr-style player that exposes only
  an opaque `blob:` src at first scan (the plyr.io "slow to switch to native"
  case). Native controls must appear immediately; a clean source then becomes
  available through a mock player API without a DOM mutation. `loadedmetadata`
  must trigger event-driven cleanup while retaining the original media element.
- `fixture-player-cleaner-early.html` — creates a known custom player from a
  `<head>` script and records insertion, nativeization, and DOMContentLoaded
  timestamps. Enforces pre-paint transformation within one frame, without a
  debounce or DOMContentLoaded gate.
- The resource-lifecycle scenarios replace each cleaner's `<video>` six times
  and instrument document/window listeners, intervals, MutationObservers, and
  IntersectionObservers. Every active count must remain flat.
- Visibility scenarios shadow the page-facing document state while simulating a
  native hidden tab, proving both cleaners still enter PiP from the captured
  browser getter but not merely from window focus loss. The Tube Cleaner fixture
  also verifies its quality path keeps YouTube's settings shell hidden, selects
  the requested option once, and closes it without an extra toggle.

```sh
node run-tests.mjs            # exit code 1 if any check fails (CI-gateable)
node run-tests.mjs --filter=iPad
node run-tests.mjs --filter=player-cleaner
```

The fixtures' mock players actively fight the userscripts (strip `controls`
repeatedly, the way real custom players and YouTube's html5 player do) so the
tests verify the scripts survive adversarial behavior, not just a static page.

## Real-world smoke — `live-smoke.mjs` (best-effort)

Loads an actual YouTube watch page in WebKit with the userscript injected and
reports whether the player transforms in the wild. Network-dependent and subject
to YouTube's consent/anti-bot behavior, so it never fails the build — it prints a
verdict to read.

```sh
node live-smoke.mjs            # default video
node live-smoke.mjs <videoId>  # specific video
```

## Leak test — `leak-test.mjs`

Instruments `document.addEventListener`/`removeEventListener` and
`window.setInterval`/`clearInterval`, transforms the player, then swaps the
`<video>` element several times (as YouTube does during SPA navigation) and
asserts active listener/interval counts stay flat. The main deterministic gate
also covers both cleaners and tracks all document/window listeners, intervals,
MutationObservers, and IntersectionObservers across six swaps. Fails on the
pre-fix code and passes now. Exit code 1 on failure.

```sh
node leak-test.mjs
```

## Diagnostic — `probe-yt-events.mjs`

Best-effort probe that reports which document-level `yt-*` events live YouTube
actually dispatches. Used to confirm the removed `yt-player-state-change` hook
was dead code. Not a gate.

```sh
node probe-yt-events.mjs
```

## Diagnostic — `probe-live.mjs`

Loads real pages in WebKit with the actual Player Cleaner injected and
`__wblockPlayerCleanerDebug` enabled, captures the script's `[Player Cleaner]`
console output, and dumps each `<video>`'s state (source/protocol, controls,
autoplay/muted/loop, size, wrapper ancestry). Use it to see whether a live site
is replaced, enhanced in place, or skipped — and why. Note that Player Cleaner
logs nothing unless `window.__wblockPlayerCleanerDebug` is set, so silence in a
plain console does not mean the script is inactive. Not a gate.

```sh
node probe-live.mjs                       # a few default sites
node probe-live.mjs https://videojs.org/  # specific URL(s)
```

## What these tests do and don't prove

- Prove: the userscripts' DOM transformation logic. Tube Cleaner: pre-paint
  startup and anti-flash CSS, native controls, chrome hiding, toolbar,
  background-playback override, auto-PiP hooks, iOS code paths, `playsinline`,
  controls surviving YouTube's attempts to
  remove them. Player Cleaner: custom-player detection, source discovery across
  video.js/JW/Plyr/data-attributes (including root-relative URLs resolved
  against the document base and rejection of poster/DASH false positives), the
  clean-source cleanup path (original media
  element/state retention and chrome removal), the opaque-source enhance-in-place
  path, event-driven upgrade once a clean source appears, pre-paint timing for
  known wrappers, bounded per-video resources across SPA swaps, the bare-video
  fallback for unrecognized/custom players (and its ambient and
  already-native skip guards), sidecar subtitle/chapter recovery, persistent
  speed/volume/mute/subtitle/resume preferences, fallback system Now Playing
  metadata, the background-playback override, and controls surviving a fighting
  player. Tube Cleaner additionally distinguishes
  automatically entered PiP from user-entered PiP so returning to the page does
  not close a PiP session the user requested manually.
- Don't prove: in-video ad removal. Ads are stripped by wBlock's separate
  AdGuard scriptlets (`trusted-replace-*-response`, `set-constant` on
  `adPlacements`/`adSlots`/`playerAds`), not by Tube Cleaner. Verify those via
  `scripts/test_youtube_compatibility_rules.swift` and, for SABR-stitched ads,
  manual/`live-smoke` inspection.
