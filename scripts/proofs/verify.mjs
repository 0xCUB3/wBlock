import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtempSync, readFileSync, writeFileSync, rmSync, readdirSync, existsSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { decisions, uploadRule, revisionRule, railRule, gateRule, infoRule, headlessGateRule, headlessOps, pauseRule, popupRule, swipeRule, verifyProofs } from "./policies.mjs";

const here = dirname(fileURLToPath(import.meta.url)),
  root = resolve(here, "../..");
const requests = [],
  expected = [];
let seed = 0x57424c4b;
// High bits: the low bits of a power-of-two LCG cycle with short periods.
const rand = (n) => Math.floor(((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 2 ** 32) * n);
const flags = (names) =>
  Array.from({ length: 2 ** names.length }, (_, i) =>
    Object.fromEntries(names.map((k, j) => [k, Boolean(i & (1 << j))])),
  );
function add(suite, values, result) {
  requests.push({ suite, values });
  expected.push(result);
}
function decision(suite, values, project = (x) => x) {
  add(
    suite,
    values,
    values.map((e) => project(decisions[suite].run(e), e)),
  );
}
function traces(alphabet, depth) {
  let result = [[]];
  for (let i = 0; i < depth; i++) result = result.flatMap((t) => alphabet.map((e) => [...t, e]));
  return [
    ...result,
    ...Array.from({ length: 32 }, () => Array.from({ length: 64 }, () => alphabet[rand(alphabet.length)])),
  ];
}
function machine(suite, r, inputs, project) {
  const m = r.compiled(),
    p = r.encodeParams({});
  for (const values of inputs) {
    let state = m.init(p);
    const output = values.map((e) => {
      const before = state;
      state = m.step(p, state, r.encodeInput(e));
      return project(state, before, e);
    });
    add(suite, values, output);
  }
}
for (const e of flags(["remote", "inline", "custom", "downloaded", "builtIn", "local"]).filter(
  (e) => !(e.remote && e.inline),
)) {
  decision("menus", [e], (o) => ({
    filter: [
      "info",
      ...(o.filterDownload ? ["download"] : []),
      ...(o.filterSettings ? ["settings", o.filterEdit ? "editRules" : "viewRules"] : []),
      ...(o.filterMetadata ? ["editInfo", "deleteList"] : []),
    ],
    script: [
      "info",
      ...(o.scriptDownload ? ["download"] : []),
      ...(o.scriptSettings ? ["settings", o.scriptEdit ? "editContent" : "viewContent"] : []),
      ...(o.scriptMetadata ? ["editInfo", "deleteScript"] : []),
    ],
  }));
}
for (const e of flags(["local", "base", "baseLegacy", "remote", "remoteLegacy", "knownNil", "knownCur", "knownLegacy", "custom", "reconciled"]))
  decision("selection", [e]);
for (const e of flags(["builtInCurrent", "builtInLegacy", "purged", "variant"])) decision("customImport", [e]);
for (const e of flags(["prevNamed", "prevSel", "localStart", "named1", "sel1", "custom1", "toggled", "named2", "sel2"])) decision("twoSyncs", [e]);
for (const e of flags(["paused", "disabledOnSite", "enabled", "webURL", "noframes", "top", "matched", "excluded", "otherHost", "hostless"])) decision("frame", [e]);
// The model's booleans become the strings FilterListRemoteMetadataPolicy.applying yields: an unchanged name or description, or the header's text.
for (const e of flags(["custom", "userName", "titlePresent", "titleBlank", "userDescription", "descriptionPresent", "descriptionBlank", "versionPresent"]))
  decision("remoteMetadata", [e], (o) => ({
    name: o.takeTitle ? "Remote Title" : "Original",
    description: o.takeDescription ? "Remote Description" : "Original description",
    version: o.versionUnknown ? "Unknown" : "2025.1",
  }));
for (const e of flags(["present", "same", "blank"])) decision("importReview", [e]);
{
  const values = [];
  for (const persisted of [false, true])
    for (const runningSince of [0, 50, 90, 110])
      for (const lastCheck of [0, 50, 90, 110])
        for (const stale of [0, 10, 50])
          values.push({ persisted, runningSince, lastCheck, now: 100, stale });
  decision("persistedRunActive", values);
}
{
  const values = [];
  for (const e of flags(["force", "pending", "hasExpiry"]))
    for (const lastChecked of [0, 50, 90, 100])
      for (const expiry of [5, 20, 60])
        for (const interval of [0, 10, 40])
          values.push({ ...e, lastChecked, expiry, interval, now: 100 });
  decision("filterDueCheck", values);
}
for (const e of flags(["globalOn", "onlySelected", "inExcluded", "inSelected", "targetOn", "hasCompiled", "compiledAllows"])) {
  decision("cosmeticSite", [e]);
}
for (const e of flags(["tomb", "local", "remote", "existed"]))
  for (const deletedAt of [0, 99, 100, 101])
    for (const remoteAt of [0, 99, 100, 101]) decision("custom", [{ ...e, deletedAt, remoteAt }]);
for (const e of flags(["tomb", "local", "remote", "added", "synced"]))
  for (const generation of [0, 1, 2, Number.MAX_SAFE_INTEGER - 1])
    for (const snapshot of [0, 1, 2, Number.MAX_SAFE_INTEGER - 1]) decision("remote", [{ ...e, generation, snapshot }]);
for (const e of flags(["remote", "exists", "automatic", "hasGlobal", "hasDownload", "hasCheck"])) {
  for (const interval of [0, 1, 100])
    for (const global of [0, 900, 901, 1001])
      for (const download of [0, 900, 901, 1001])
        for (const check of [0, 900, 901, 1001]) {
          const v = { ...e, interval, global, download, check, now: 1000 };
          const values = [
            v,
            { ...v, remote: !v.remote, exists: !v.exists },
            { ...v, automatic: !v.automatic, hasCheck: !v.hasCheck },
          ];
          const order = values
            .map((v, i) => ({ i, fetch: decisions.refresh.run(v).fetch, missing: !v.exists }))
            .filter((x) => x.fetch)
            .sort((a, b) => Number(b.missing) - Number(a.missing))
            .map((x) => x.i);
          add("refresh", values, order);
        }
}
for (const e of flags([
  "identity",
  "remotePresent",
  "remoteIdentity",
  "sameIdentity",
  "sameName",
  "validName",
  "tombName",
  "syncedName",
  "tombIdentity",
  "syncedIdentity",
]))
  decision("local", [e]);
for (const e of flags(["tomb", "local", "remote", "remoteTomb"])) decision("localSets", [e], (o) => [o, o]);
for (const e of flags([
  "persisted",
  "oldName",
  "newName",
  "oldDescription",
  "newDescription",
  "selected",
  "automatic",
  "onlySelected",
])) {
  const values = [
    e,
    { ...e, persisted: !e.persisted },
    { ...e, newName: !e.newName, newDescription: !e.newDescription },
  ];
  add(
    "rebase",
    values,
    values.map((e, i) => {
      const o = decisions.rebase.run(e);
      return {
        name: o.useName ? "persisted" : `snapshot-${i}`,
        description: o.useDescription ? "persisted" : `snapshot-${i}`,
        selected: o.selected,
        automatic: o.automatic,
        nameFlag: o.nameFlag,
        descriptionFlag: o.descriptionFlag,
        onlySelected: o.onlySelected,
        category: e.persisted,
        excluded: e.persisted ? ["excluded.test"] : [],
        sites: e.persisted ? ["selected.test"] : [],
        version: "downloaded",
        url: `https://example.com/${i}`,
      };
    }),
  );
}
machine(
  "upload",
  uploadRule,
  traces(
    [
      { take: true, syncing: false, trigger: 0 },
      ...Array.from({ length: 6 }, (_, i) => ({ take: false, syncing: i >= 3, trigger: i % 3 })),
    ],
    4,
  ),
  (s) => {
    const d = uploadRule.decode(s);
    return [d.kind, d.value];
  },
);
machine(
  "revisions",
  revisionRule,
  traces(
    [
      ...Array.from({ length: 6 }, (_, i) => ({ op: 0, key: i % 3, token: Math.floor(i / 3) })),
      ...Array.from({ length: 3 }, (_, key) => ({ op: 1, key, token: 0 })),
      { op: 2, key: 0, token: 0 },
    ],
    2,
  ),
  (s) => ["Current", "Snapshot"].map((name) => [0, 1, 2].map((k) => s.maps[name].get(k) ?? 0)),
);
machine(
  "rail",
  railRule,
  traces(
    [
      ...Array.from({ length: 10 }, (_, i) => ({ op: 0, phase: i % 5, complete: i >= 5 })),
      ...Array.from({ length: 3 }, (_, i) => ({ op: i + 1, phase: 0, complete: false })),
    ],
    3,
  ),
  (s, b, e) => {
    const d = railRule.decode(s),
      old = railRule.decode(b),
      phases = Array.from({ length: 5 }, (_, i) => d[`p${i}`]),
      previous = Array.from({ length: 5 }, (_, i) => old[`p${i}`]);
    const failed = phases.indexOf(3),
      active = phases.indexOf(1),
      last = phases.lastIndexOf(2);
    return {
      phases,
      failed: d.failed || failed >= 0,
      focus: failed >= 0 ? failed : active >= 0 ? active : last >= 0 ? last : 0,
      cleared: e.op === 3 || (e.op === 0 && previous.indexOf(1) !== active),
    };
  },
);
// Every letter names all inputs. The mask letters cover all eight component sets; op 11 is an install that
// wrote only the legacy key. Depth 3 is exhaustive; the seeded long traces follow.
const pauseAlphabet = [
  ...Array.from({ length: 8 }, (_, m) => ({ op: 0, fMask: Boolean(m & 1), sMask: Boolean(m & 2), zMask: Boolean(m & 4), paused: false })),
  ...[true, false].flatMap((paused) => [1, 11].map((op) => ({ op, fMask: false, sMask: false, zMask: false, paused }))),
  ...[2, 3, 4, 5, 6, 7, 8, 9, 10].map((op) => ({ op, fMask: false, sMask: false, zMask: false, paused: false })),
];
machine("pauseStore", pauseRule, traces(pauseAlphabet, 3), (s) => {
  const d = pauseRule.decode(s);
  // The effective mask the global and content-blocking queries read: the stored one, or the legacy bool for all components.
  const eff = d.hasMask ? [d.filters, d.scripts, d.zapper] : [d.legacy, d.legacy, d.legacy];
  return [
    d.legacy ? 1 : 0,
    d.hasMask ? 1 : 0,
    d.hasMask ? (d.filters ? 1 : 0) + (d.scripts ? 2 : 0) + (d.zapper ? 4 : 0) : 0,
    d.requested ? 1 : 0,
    d.status,
    d.err ? 1 : 0,
    d.out,
    eff.some(Boolean) ? 1 : 0,
    eff[0] && eff[2] ? 1 : 0,
  ];
});

machine(
  "gate",
  gateRule,
  traces(
    [0, 1, 2, 3].map((op) => ({ op })),
    6,
  ),
  (s) => {
    const d = gateRule.decode(s);
    return { granted: d.granted, work: d.work, running: d.running, resumed: d.resumed };
  },
);
const infoInput = (op, o = {}) => ({ op, tok: 1, id: 1, ev: 1, mouse: false, fromKb: false, v1: true, v2: true, v3: true, ...o });
// Depth 3 uses every anchor on screen; depth 2 adds each visibility pattern of the three tokens' anchors.
const infoOther = [
  ...[1, 2, 3].map((tok) => infoInput("clicked", { tok })),
  ...["request", "dismiss"].flatMap((op) =>
    [1, 2, 3].flatMap((tok) => [infoInput(op, { tok }), ...[1, 2].map((ev) => infoInput(op, { tok, ev, mouse: true }))]),
  ),
  infoInput("clear"),
];
const infoAnchors = [1, 2, 3].flatMap((id) =>
  [false, true].flatMap((fromKb) => flags(["v1", "v2", "v3"]).map((v) => infoInput("anchor", { id, fromKb, ...v }))),
);
machine(
  "infoPopover",
  infoRule,
  [
    ...traces([...infoOther, ...infoAnchors.filter((e) => e.v1 && e.v2 && e.v3)], 3),
    ...traces([...infoOther, ...infoAnchors], 2),
  ],
  (s, b, e) => {
    const d = infoRule.decode(s), o = infoRule.decode(b);
    const result = e.op === "anchor" ? d.pick : e.op === "request" ? Number(d.pres === e.tok) : e.op === "dismiss" ? Number(o.pres === e.tok) : 0;
    return [d.pres, result];
  },
);

for (const f of [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 99])
  for (const g of [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 99]) decision("headlessBackoff", [{ f, g }]);
// Gate traces, with the clock free to move backwards as the shipped gate allows. Depth 2 covers every pair over the
// boundary times (900/901 and 1800-1802 bracket the first cooldowns, 2700/2701 the second); depth 3 covers the short set;
// then a directed trace and seeded long ones whose clock steps through every cooldown and backoff edge, forwards and back.
const headlessNow = [1, 900, 901, 1800, 1801, 1802, 2700, 2701, 22000];
const headlessAlphabet = headlessOps.flatMap((op) => headlessNow.map((now) => ({ op, now })));
const headlessShort = headlessOps.flatMap((op) => [1, 900, 1800, 1801].map((now) => ({ op, now })));
const headlessTraces = [...traces(headlessAlphabet, 2), ...traces(headlessShort, 3)];
// Three failures, then the edge: after the third failure the cooldown is 3600 s, so last+3599 is refused and last+3600 granted.
headlessTraces.push([
  { op: "consume", now: 1000 }, { op: "launchFailed", now: 1000 }, { op: "consume", now: 1900 }, { op: "launchFailed", now: 1900 },
  { op: "consume", now: 3700 }, { op: "launchFailed", now: 3700 },
  { op: "consume", now: 7299 }, { op: "consume", now: 7300 }, { op: "consume", now: 7301 },
]);
const clockSteps = [-30000, -3601, -1801, -900, -1, 0, 1, 899, 900, 901, 1799, 1800, 1801, 3599, 3600, 3601, 7199, 7200, 7201, 14399, 14400, 14401, 21599, 21600, 21601, 30000];
for (let t = 0; t < 32; t++) {
  let clock = 1000;
  headlessTraces.push(
    Array.from({ length: 64 }, () => {
      clock = Math.max(1, clock + clockSteps[rand(clockSteps.length)]);
      const op = headlessOps[rand(headlessOps.length)];
      return { op, now: op === "consume" && rand(4) === 0 ? Math.max(1, clock - 1) : clock };
    }),
  );
}
machine("headlessGate", headlessGateRule, headlessTraces, (s) => {
  const d = headlessGateRule.decode(s);
  return { granted: d.granted, last: d.last, failures: d.failures, outcome: d.outcome };
});
add("headlessGateBlocked", [{ op: "consume", now: 1000 }, { op: "consume", now: 5000 }], [{ granted: false }, { granted: false }]);

// A claim at 1 s goes stale once now exceeds 301 s, so probes at 301 and 302 cover elapsed 300 and 301.
const popupTimes = [1, 301, 302];
const popupOutcomes = Array.from({ length: 9 }, (_, i) => i);
const popupAlphabet = [
  ...[0, 1, 2, 4, 5].flatMap((op) => [1, 2].flatMap((claim) => popupTimes.map((now) => ({ op, claim, now, outcome: 0 })))),
  ...[1, 2].flatMap((claim) => popupTimes.flatMap((now) => popupOutcomes.map((outcome) => ({ op: 3, claim, now, outcome })))),
];
// Directed traces longer than the exhaustive depth. A stale takeover (302 s after a 1 s claim) must not hand the
// earlier request to the new claim. A stale acknowledgment clears the store; the following snapshot reads the cleared state,
// since consumeSnapshot reports the state it clears.
const popupDirected = [
  [
    { op: 1, claim: 1, now: 1, outcome: 0 }, { op: 0, claim: 2, now: 302, outcome: 0 },
    { op: 2, claim: 2, now: 302, outcome: 0 }, { op: 4, claim: 2, now: 302, outcome: 0 },
  ],
  [
    { op: 1, claim: 1, now: 1, outcome: 0 }, { op: 5, claim: 1, now: 302, outcome: 0 }, { op: 4, claim: 1, now: 302, outcome: 0 },
    { op: 1, claim: 2, now: 302, outcome: 0 }, { op: 2, claim: 2, now: 302, outcome: 0 }, { op: 4, claim: 2, now: 302, outcome: 0 },
  ],
];
machine(
  "popup",
  popupRule,
  [...traces(popupAlphabet, 2), ...popupDirected],
  (s, b, e) => {
    const view = (x, now) => [x.st === 1 && now - x.startedAt > 300 ? 4 : x.st, x.startedAt, x.finishedAt];
    const d = popupRule.decode(s), old = popupRule.decode(b);
    return [d.ok ? 1 : 0, ...(e.op === 5 ? view(old, e.now) : view(d, e.now))];
  },
);

const swipeInput = (op, o = {}) => ({
  op,
  phase: "none",
  hasMomentum: false,
  swipeEnabled: true,
  reduceMotionIn: false,
  axis: "short",
  amount: 0,
  isComplete: false,
  ...o,
});
const swipeScrolls = [
  swipeInput("scroll", { phase: "mayBegin" }),
  swipeInput("scroll", { phase: "began", axis: "short" }),
  swipeInput("scroll", { phase: "began", axis: "back" }),
  swipeInput("scroll", { phase: "began", axis: "back", reduceMotionIn: true }),
  swipeInput("scroll", { phase: "began", axis: "back", hasMomentum: true }),
  swipeInput("scroll", { phase: "began", axis: "back", swipeEnabled: false }),
  swipeInput("scroll", { phase: "began", axis: "other" }),
  swipeInput("scroll", { phase: "changed", axis: "back" }),
  swipeInput("scroll", { phase: "changed", axis: "other" }),
  swipeInput("scroll", { phase: "ended", axis: "back" }),
];
const swipeTracks = [
  swipeInput("track", { phase: "changed", amount: 400 }),
  swipeInput("track", { phase: "changed", amount: 996 }),
  swipeInput("track", { phase: "ended", amount: 250 }),
  swipeInput("track", { phase: "ended", amount: 350 }),
  swipeInput("track", { phase: "ended", amount: 996 }),
  swipeInput("track", { phase: "cancelled", amount: 400 }),
  swipeInput("track", { phase: "none", amount: 996 }),
  swipeInput("track", { phase: "none", amount: 0, isComplete: true }),
  swipeInput("track", { phase: "none", amount: 1000, isComplete: true }),
];
const swipeAlphabet = [...swipeScrolls, ...swipeTracks, swipeInput("finishCommit"), swipeInput("abort")];
const swipeDirected = [
  // Normal live hold, release, and tail snap.
  [
    swipeInput("scroll", { phase: "mayBegin" }),
    swipeInput("scroll", { phase: "changed", axis: "back" }),
    swipeInput("track", { phase: "changed", amount: 400 }),
    swipeInput("track", { phase: "changed", amount: 1000 }),
    swipeInput("track", { phase: "ended", amount: 600 }),
    swipeInput("track", { phase: "none", amount: 995 }),
    swipeInput("track", { phase: "none", amount: 1000, isComplete: true }),
    swipeInput("finishCommit"),
  ],
  // Reduce motion release commit and cancel.
  [
    swipeInput("scroll", { phase: "began", axis: "back", reduceMotionIn: true }),
    swipeInput("track", { phase: "changed", amount: 400 }),
    swipeInput("track", { phase: "ended", amount: 300 }),
    swipeInput("finishCommit"),
    swipeInput("scroll", { phase: "began", axis: "back", reduceMotionIn: true }),
    swipeInput("track", { phase: "ended", amount: 299 }),
  ],
];
machine(
  "swipeBack",
  swipeRule,
  [...traces(swipeAlphabet, 2), ...swipeDirected],
  (s) => {
    const d = swipeRule.decode(s);
    return [d.mode, d.action, d.progress, d.stopped ? 1 : 0];
  },
);

const temp = mkdtempSync(join(tmpdir(), "wblock-policy-proofs-"));
try {
  let products = process.env.WBLOCK_CORE_PRODUCTS;
  if (!products) {
    const derived = join(homedir(), "Library/Developer/Xcode/DerivedData");
    const directory = readdirSync(derived).find(
      (p) =>
        p.startsWith("wBlock-") &&
        existsSync(join(derived, p, "Build/Products/Debug/wBlock.app")) &&
        existsSync(join(derived, p, "Build/Products/Debug/wBlockCoreService.framework")),
    );
    assert.ok(directory, "Set WBLOCK_CORE_PRODUCTS to the signed Xcode build products");
    products = join(derived, directory, "Build/Products/Debug");
  }
  const binary = join(temp, "policy-probe");
  const sources = [
    "wBlock/ContextMenuActionAvailability.swift",
    "wBlock/CloudSyncCustomFilterSync.swift",
    "wBlock/CloudSyncRemoteUserScriptSync.swift",
    "wBlock/CloudSyncUserScriptSync.swift",
    "wBlock/ApplyChangesViewModel.swift",
    "wBlock/Haptics.swift",
    "wBlock/InfoPresentation.swift",
    "wBlock/SwipeBackNavigation.swift",
    "scripts/proofs/PolicyProbe.swift",
  ];
  // The Swift probe compiles and runs in child processes while this process proves the laws.
  const run = (file, args, timeout) =>
    promisify(execFile)(file, args, { cwd: root, timeout, maxBuffer: 1 << 26, env: { ...process.env, PROBE: binary } }).then(({ stdout, stderr }) =>
      process.stderr.write(stdout + stderr),
    );
  writeFileSync(binary + ".in.json", JSON.stringify(requests));
  // One shell child compiles and then runs the probe, so neither waits on this process's event loop.
  const swift = run(
    "/bin/sh",
    [
      "-c",
      'swiftc "$@" && exec "$PROBE" "$PROBE.in.json" "$PROBE.out.json"',
      "sh",
      "-parse-as-library",
      "-F",
      products,
      "-I",
      products,
      "-L",
      products,
      "-framework",
      "wBlockCoreService",
      "-Xlinker",
      "-rpath",
      "-Xlinker",
      products,
      ...sources,
      "-o",
      binary,
    ],
    240000,
  );
  const proof = verifyProofs();
  await swift;
  const actual = JSON.parse(readFileSync(binary + ".out.json", "utf8"));
  assert.equal(actual.length, expected.length, "Swift must answer every request");
  for (let i = 0; i < actual.length; i++) assert.deepEqual(actual[i], expected[i], JSON.stringify(requests[i]));
  const suites = Object.fromEntries(
    [...new Set(requests.map((r) => r.suite))].map((s) => [
      s,
      requests.filter((r) => r.suite === s).reduce((n, r) => n + r.values.length, 0),
    ]),
  );
  console.log(JSON.stringify({ proof, swiftChecks: suites, seed: "0x57424c4b" }));
} finally {
  rmSync(temp, { recursive: true, force: true });
}
