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

Tube Cleaner scenarios (fixture.html / fixture-noplaysinline.html): desktop
(macOS Safari-like), iPhone (mobile Safari, touch), and iPad requesting the
desktop site (no `playsinline`, the iPadOS default).

Player Cleaner scenarios:
- `fixture-player-cleaner.html` — opaque (blob) source, so the script enhances
  the existing `<video>` in place and must keep native controls on while the
  custom player keeps stripping them.
- `fixture-player-cleaner-replace.html` — a clean http(s) source, exercising the
  full replacement path: a brand-new native `<video>` is swapped in, the poster
  and caption `<track>` are copied, the custom chrome is dropped, and controls
  survive an adversarial player.
- `fixture-player-cleaner-discovery.html` — five players exposing the media URL
  through different mechanisms (video.src, `<source>` child, descendant
  `data-src`, a mocked video.js `currentSource()`, a mocked JW Player playlist
  item); each must resolve to the right clean source.

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
asserts active listener/interval counts stay flat. Fails on the pre-fix code
(leaked ~2 intervals per swap) and passes now. Exit code 1 on failure.

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

## What these tests do and don't prove

- Prove: the userscripts' DOM transformation logic. Tube Cleaner: native
  controls, chrome hiding, toolbar, background-playback override, auto-PiP
  hooks, iOS code paths, `playsinline`, controls surviving YouTube's attempts to
  remove them. Player Cleaner: custom-player detection, source discovery across
  video.js/JW/Plyr/data-attributes, the clean-source replacement path (poster
  and track copying, chrome removal), the opaque-source enhance-in-place path,
  the background-playback override, and controls surviving a fighting player.
- Don't prove: in-video ad removal. Ads are stripped by wBlock's separate
  AdGuard scriptlets (`trusted-replace-*-response`, `set-constant` on
  `adPlacements`/`adSlots`/`playerAds`), not by Tube Cleaner. Verify those via
  `scripts/test_youtube_compatibility_rules.swift` and, for SABR-stitched ads,
  manual/`live-smoke` inspection.
