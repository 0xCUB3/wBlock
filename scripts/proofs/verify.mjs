import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync, rmSync, readdirSync, existsSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { decisions, uploadRule, revisionRule, railRule, gateRule, infoRule, headlessGateRule, headlessOps, pauseRule, verifyProofs } from "./policies.mjs";

const here = dirname(fileURLToPath(import.meta.url)),
  root = resolve(here, "../..");
const proof = verifyProofs();
const requests = [],
  expected = [];
let seed = 0x57424c4b;
const rand = (n) => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) % n;
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
for (const e of flags(["builtInCurrent", "builtInLegacy", "variant"])) decision("customImport", [e]);
for (const e of flags(["prevNamed", "prevSel", "localStart", "named1", "sel1", "custom1", "toggled", "named2", "sel2"])) decision("twoSyncs", [e]);
for (const e of flags(["paused", "disabledOnSite", "enabled", "webURL", "noframes", "top", "matched", "excluded"])) decision("frame", [e]);
for (const e of flags(["custom", "userName", "titlePresent", "titleBlank", "userDescription", "descriptionPresent", "descriptionBlank", "versionPresent"])) decision("remoteMetadata", [e]);
for (const e of flags(["present", "same", "blank"])) decision("importReview", [e]);
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
  return [
    d.legacy ? 1 : 0,
    d.hasMask ? 1 : 0,
    d.hasMask ? (d.filters ? 1 : 0) + (d.scripts ? 2 : 0) + (d.zapper ? 4 : 0) : 0,
    d.requested ? 1 : 0,
    d.status,
    d.err ? 1 : 0,
    d.out,
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
const infoInput = (op, o = {}) => ({ op, tok: 1, id: 1, ev: 1, mouse: false, fromKb: false, ...o });
machine(
  "infoPopover",
  infoRule,
  traces(
    [
      ...[1, 2, 3].map((tok) => infoInput("clicked", { tok })),
      ...[1, 2, 3].flatMap((id) => [false, true].map((fromKb) => infoInput("anchor", { id, fromKb }))),
      ...["request", "dismiss"].flatMap((op) =>
        [1, 2, 3].flatMap((tok) => [infoInput(op, { tok }), ...[1, 2].map((ev) => infoInput(op, { tok, ev, mouse: true }))]),
      ),
      infoInput("clear"),
    ],
    3,
  ),
  (s, b, e) => {
    const d = infoRule.decode(s), o = infoRule.decode(b);
    const result = e.op === "anchor" ? d.pick : e.op === "request" ? Number(d.pres === e.tok) : e.op === "dismiss" ? Number(o.pres === e.tok) : 0;
    return [d.pres, result];
  },
);

for (const f of [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 99])
  for (const g of [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 99]) decision("headlessBackoff", [{ f, g }]);
// Gate traces: exhaustive short ones over boundary times (900/901 and 1801/1802 bracket the first two cooldowns),
// then seeded long ones whose clock steps through every cooldown and backoff edge. Recorded outcomes never move the clock back.
let headlessTraces = [[]];
const headlessAlphabet = headlessOps.flatMap((op) => [1, 900, 901, 902, 1801, 22000].map((now) => ({ op, now })));
for (let i = 0; i < 3; i++) headlessTraces = headlessTraces.flatMap((t) => headlessAlphabet.map((e) => [...t, e]));
headlessTraces = headlessTraces.filter((t) =>
  t.every((e, i) => e.op === "consume" || e.now >= Math.max(0, ...t.slice(0, i).map((x) => x.now))),
);
const clockSteps = [0, 1, 899, 900, 901, 1799, 1800, 1801, 3599, 3600, 3601, 7199, 7200, 7201, 14399, 14400, 14401, 21599, 21600, 21601, 30000];
for (let t = 0; t < 32; t++) {
  let clock = 1000;
  headlessTraces.push(
    Array.from({ length: 64 }, () => {
      clock += clockSteps[rand(clockSteps.length)];
      const op = headlessOps[rand(headlessOps.length)];
      return { op, now: op === "consume" && rand(4) === 0 ? clock - 1 : clock };
    }),
  );
}
machine("headlessGate", headlessGateRule, headlessTraces, (s) => {
  const d = headlessGateRule.decode(s);
  return { granted: d.granted, last: d.last, failures: d.failures, outcome: d.outcome };
});
add("headlessGateBlocked", [{ op: "consume", now: 1000 }, { op: "consume", now: 5000 }], [{ granted: false }, { granted: false }]);

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
    "wBlock/InfoPresentation.swift",
    "scripts/proofs/PolicyProbe.swift",
  ];
  execFileSync(
    "swiftc",
    [
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
    { cwd: root, stdio: "inherit", timeout: 120000 },
  );
  writeFileSync(join(temp, "input.json"), JSON.stringify(requests));
  execFileSync(binary, [join(temp, "input.json"), join(temp, "output.json")], {
    cwd: root,
    stdio: "inherit",
    timeout: 120000,
  });
  const actual = JSON.parse(readFileSync(join(temp, "output.json"), "utf8"));
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
