# Tube Cleaner test harness

Autonomous tests for the bundled Tube Cleaner userscript
(`wBlockCoreService/BundledUserscripts/tube-cleaner.user.js`). They run in
Playwright **WebKit** — the same engine Safari uses — so results approximate
real macOS/iOS Safari behavior without needing a device or a human to report.

## Setup (once)

```sh
cd tests/tube-cleaner
npm install
npx playwright install webkit
```

## Deterministic gate — `run-tests.mjs`

Loads a synthetic YouTube watch page (`fixture.html`) that mimics the real
player DOM and the `#movie_player` API surface, injects the real userscript at
`document-start` in the page world (matching `@run-at document-start` +
`@inject-into page`), and asserts the transformation actually happens.

Three scenarios run: desktop (macOS Safari-like), iPhone (mobile Safari, touch),
and iPad requesting the desktop site (no `playsinline`, the iPadOS default).

```sh
node run-tests.mjs            # exit code 1 if any check fails (CI-gateable)
node run-tests.mjs --filter=iPad
```

The fixture's mock player actively fights the userscript (strips `controls`
repeatedly, the way YouTube's html5 player does) so the tests verify the script
survives adversarial behavior, not just a static page.

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

- Prove: the userscript's DOM transformation logic (native controls, chrome
  hiding, toolbar, background-playback override, auto-PiP hooks, iOS code paths,
  `playsinline`, controls surviving YouTube's attempts to remove them).
- Don't prove: in-video ad removal. Ads are stripped by wBlock's separate
  AdGuard scriptlets (`trusted-replace-*-response`, `set-constant` on
  `adPlacements`/`adSlots`/`playerAds`), not by Tube Cleaner. Verify those via
  `scripts/test_youtube_compatibility_rules.swift` and, for SABR-stitched ads,
  manual/`live-smoke` inspection.
