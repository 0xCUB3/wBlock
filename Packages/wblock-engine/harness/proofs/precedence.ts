// Rule precedence, proven with gdp-wired and held to the shipped compiler.
//
// WebKit applies rules in order and `ignore-previous-rules` cancels every
// earlier match, so precedence is the tier order in crates/wbe/src/compile/mod.rs.
// The model folds that order; the laws are uBO's precedence (static-net-filtering.js
// `matchString`, traffic.js `shouldStrictBlock`, cosmetic-filtering.js). The
// cross-check compiles every combination with `wbe` and runs it through the
// calibrated WebKit simulator, so the model cannot drift from the code.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { bool, fun, proveDecision, crossCheckDecision } from 'gdp-wired';
import { simulate } from '../sim/webkit.ts';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const WBE = process.env.WBE_BIN ?? path.join(ROOT, 'target/release/wbe');

// Each input is "a rule of this tier matched this load". `add` tiers set an
// output; the rest are ignore-previous-rules, which cancel the outputs
// accumulated so far (`cancel` narrows that to the named outputs). Hides are
// judged on the page load, blocks on a subresource load. Native hides are all
// generic; hides scoped to sites and `$specifichide` are the runtime engine's.
const TIERS = [
  ['genericHide', { add: 'generic' }],
  ['hideException', {}],
  // `$denyallow`: the block, then its exclusions, both ahead of every other
  // block. An exclusion matches subresource loads only, so it cancels blocks
  // and no hides.
  ['denyallowBlock', { add: 'blocked' }],
  ['denyallowException', { cancel: ['blocked'] }],
  ['block', { add: 'blocked' }],
  ['exception', {}],
  // `$important,$denyallow`: the same, ahead of the other important blocks.
  ['importantDenyallowBlock', { add: 'blocked' }],
  ['importantDenyallowException', { cancel: ['blocked'] }],
  ['importantBlock', { add: 'blocked' }],
  ['importantException', {}],
  ['documentException', {}],
] as const;
type Input = (typeof TIERS)[number][0];
type Tier = (typeof TIERS)[number];
const INPUTS = Object.fromEntries(TIERS.map(([name]) => [name, bool])) as Record<Input, typeof bool>;

function model(name: string, order: readonly Tier[]) {
  return fun(name).inputs(INPUTS).returns((e: any) => {
    const no = e.block.and(e.block.not());
    const out: Record<string, any> = { blocked: no, generic: no };
    for (const [tier, { add, cancel }] of order as any) {
      if (add) out[add] = out[add].or(e[tier]);
      for (const k of cancel ?? (add ? [] : Object.keys(out))) out[k] = out[k].and(e[tier].not());
    }
    return out;
  });
}

// Moves the tier `name` to just before `before`.
function moved(order: readonly Tier[], name: Input, before: Input): Tier[] {
  const tier = order.find(([n]) => n === name)!;
  const rest = order.filter(([n]) => n !== name);
  rest.splice(rest.findIndex(([n]) => n === before), 0, tier);
  return rest;
}

const laws = (m: any) => [
  m.law('an important block beats exceptions', (e: any) => e.importantBlock.and(e.documentException.not(), e.importantException.not()), (o: any) => o.blocked),
  m.law('an important exception lifts every block', (e: any) => e.importantException, (o: any) => o.blocked.not()),
  m.law('an exception lifts an ordinary block', (e: any) => e.exception.and(e.importantBlock.not(), e.importantDenyallowBlock.not()), (o: any) => o.blocked.not()),
  m.law('nothing is blocked without a blocking filter', (e: any) => e.block.not().and(e.denyallowBlock.not(), e.importantBlock.not(), e.importantDenyallowBlock.not()), (o: any) => o.blocked.not()),
  m.law('$document lifts everything on the page', (e: any) => e.documentException, (o: any) => o.blocked.not().and(o.generic.not())),
  // WebKit limit, not uBO: an exception matching the page load itself also lifts
  // its hides. network.rs gives exceptions a page-load trigger only where one
  // must lift a strict host block.
  m.law('a page-load exception lifts the page hides', (e: any) => e.exception, (o: any) => o.generic.not()),
  m.law('$generichide and $elemhide lift the native hides', (e: any) => e.hideException, (o: any) => o.generic.not()),
  // A `$denyallow` exclusion lifts its own block (and the blocks above it),
  // but no block placed after it.
  m.law('a denyallow exclusion lifts its own block', (e: any) => e.denyallowBlock.and(e.denyallowException, e.block.not(), e.importantBlock.not(), e.importantDenyallowBlock.not()), (o: any) => o.blocked.not()),
  m.law('a denyallow exclusion does not lift an unrelated block', (e: any) => e.denyallowException.and(e.block, e.exception.not(), e.importantDenyallowException.not(), e.importantException.not(), e.documentException.not()), (o: any) => o.blocked),
  m.law('a denyallow exclusion lifts its own important block', (e: any) => e.importantDenyallowBlock.and(e.importantDenyallowException, e.importantBlock.not(), e.importantException.not(), e.documentException.not()), (o: any) => o.blocked.not()),
  m.law('a denyallow exclusion does not lift an unrelated important block', (e: any) => e.importantDenyallowException.and(e.importantBlock, e.importantException.not(), e.documentException.not()), (o: any) => o.blocked),
];

const precedence = model('precedence', TIERS);
let seed = 0x77626521;
const rand = (n: number) => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) % n);
for (const law of laws(precedence)) {
  const v = proveDecision(law);
  assert.ok(v.proven && v.checked, JSON.stringify(v));
  const c = crossCheckDecision(law, { rand });
  assert.equal(c.failure, undefined, JSON.stringify(c));
}

// The bug the order rules out: exceptions placed after important blocks.
const swapped = [...TIERS];
const [i, j] = [swapped.findIndex(([n]) => n === 'exception'), swapped.findIndex(([n]) => n === 'importantBlock')];
[swapped[i], swapped[j]] = [swapped[j], swapped[i]];
const refusal = proveDecision(laws(model('swapped', swapped))[0]);
assert.equal(refusal.proven, false, 'swapped tiers must be refused');
assert.equal(refusal.stuck, 'sat', JSON.stringify(refusal));

// The bug the denyallow tiers rule out: exclusions placed ahead of their block,
// as when they sat in the ordinary exception tier. The exclusion then cancels
// nothing it should.
const early = moved(TIERS, 'importantDenyallowException', 'importantDenyallowBlock');
const earlyRefusal = proveDecision(laws(model('early exclusions', early)).at(-2)!);
assert.equal(earlyRefusal.proven, false, 'exclusions ahead of their block must be refused');
assert.equal(earlyRefusal.stuck, 'sat', JSON.stringify(earlyRefusal));

// The same for an ordinary `$denyallow` rule whose block and exclusions sit in
// the block and exception tiers: the exclusion lifts other rules' blocks.
const late = moved(moved(TIERS, 'denyallowBlock', 'exception'), 'denyallowException', 'importantDenyallowBlock');
const lateRefusal = proveDecision(laws(model('late exclusions', late)).at(-3)!);
assert.equal(lateRefusal.proven, false, 'exclusions after other blocks must be refused');
assert.equal(lateRefusal.stuck, 'sat', JSON.stringify(lateRefusal));

// Every combination through wbe and the WebKit simulator. An exclusion comes
// only with its block (both are one `$denyallow` rule), so an exclusion without
// a block is not a combination the compiler can produce.
const FILTERS: Partial<Record<Input, string>> = {
  genericHide: '##.g',
  hideException: '@@||page.example^$generichide',
  block: '||t.example/x',
  exception: '@@||t.example/x',
  importantBlock: '||t.example/x$important',
  importantException: '@@||t.example/x$important',
  documentException: '@@||page.example^$document',
};
// The denyallow rule: the exclusion covers the tested host only when `excluded`.
const DENYALLOW = {
  block: '*$script,domain=page.example,denyallow=other.example',
  excluded: '*$script,domain=page.example,denyallow=t.example',
};
const names = TIERS.map(([n]) => n);
const dir = mkdtempSync(path.join(tmpdir(), 'wbe-precedence-'));
const list = path.join(dir, 'list.txt');
const page = 'https://page.example/';
let checked = 0;
for (let mask = 0; mask < 1 << names.length; mask++) {
  const env = Object.fromEntries(names.map((n, k) => [n, Boolean(mask & (1 << k))])) as Record<Input, boolean>;
  if (env.importantDenyallowException && !env.importantDenyallowBlock) continue;
  if (env.denyallowException && !env.denyallowBlock) continue;
  const lines = names.filter((n) => env[n]).flatMap((n) => {
    if (n === 'denyallowBlock') return [env.denyallowException ? DENYALLOW.excluded : DENYALLOW.block];
    if (n === 'importantDenyallowBlock') return [`${env.importantDenyallowException ? DENYALLOW.excluded : DENYALLOW.block},important`];
    const filter = FILTERS[n];
    return filter === undefined ? [] : [filter];
  });
  writeFileSync(list, lines.join('\n'));
  const rules = JSON.parse(execFileSync(WBE, ['compile', '--safari', '18.0', list], { stdio: ['ignore', 'pipe', 'ignore'] }).toString());
  const sub = rules.length ? simulate(rules, { url: 'https://t.example/x', resourceType: 'script', loadContext: 'top-frame', frameUrl: page, topUrl: page }) : null;
  const doc = rules.length ? simulate(rules, { url: page, resourceType: 'top-document', loadContext: 'top-frame', frameUrl: page, topUrl: page }) : null;
  // The exception filter targets the subresource, so it does not match the page load.
  const onPage = precedence.run({ ...env, exception: false, importantException: false });
  const expected = { blocked: precedence.run(env).blocked, generic: onPage.generic };
  const actual = {
    blocked: sub?.blocked ?? false,
    generic: doc?.hiddenSelectors.some((s) => s.split(',').includes('.g')) ?? false,
  };
  assert.deepEqual(actual, expected, `combination ${JSON.stringify(env)}`);
  checked++;
}
console.log(`precedence: ${laws(precedence).length} laws proven, swapped, early-exclusion and late-exclusion orders refused, ${checked} combinations match wbe`);
