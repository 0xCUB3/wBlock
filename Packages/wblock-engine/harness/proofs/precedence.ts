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

// Each input is "a rule of this tier matched this load"; `add` tiers set an
// output, the rest are ignore-previous-rules. Hides are judged on the page load,
// blocks on a subresource load.
const TIERS = [
  ['genericHide', { add: 'generic' }],
  ['genericHideException', {}],
  ['specificHide', { add: 'specific' }],
  ['elemHideException', {}],
  ['block', { add: 'blocked' }],
  ['exception', {}],
  ['importantBlock', { add: 'blocked' }],
  ['documentException', {}],
] as const;
type Input = (typeof TIERS)[number][0];
const INPUTS = Object.fromEntries(TIERS.map(([name]) => [name, bool])) as Record<Input, typeof bool>;

function model(name: string, order: readonly (typeof TIERS)[number][]) {
  return fun(name).inputs(INPUTS).returns((e: any) => {
    const no = e.block.and(e.block.not());
    const out: Record<string, any> = { blocked: no, generic: no, specific: no };
    for (const [tier, { add }] of order as any) {
      if (add) out[add] = out[add].or(e[tier]);
      else for (const k of Object.keys(out)) out[k] = out[k].and(e[tier].not());
    }
    return out;
  });
}

const laws = (m: any) => [
  m.law('an important block beats exceptions', (e: any) => e.importantBlock.and(e.documentException.not()), (o: any) => o.blocked),
  m.law('an exception lifts an ordinary block', (e: any) => e.exception.and(e.importantBlock.not()), (o: any) => o.blocked.not()),
  m.law('nothing is blocked without a blocking filter', (e: any) => e.block.not().and(e.importantBlock.not()), (o: any) => o.blocked.not()),
  m.law('$document lifts everything on the page', (e: any) => e.documentException, (o: any) => o.blocked.not().and(o.generic.not(), o.specific.not())),
  m.law('$generichide keeps specific hides', (e: any) => e.specificHide.and(e.elemHideException.not(), e.exception.not(), e.documentException.not()), (o: any) => o.specific),
  // WebKit limit, not uBO: an exception matching the page load itself also lifts
  // its hides. network.rs gives exceptions a page-load trigger only where one
  // must lift a strict host block.
  m.law('a page-load exception lifts the page hides', (e: any) => e.exception, (o: any) => o.generic.not().and(o.specific.not())),
  m.law('$generichide lifts generic hides', (e: any) => e.genericHideException, (o: any) => o.generic.not()),
  m.law('$elemhide lifts every hide', (e: any) => e.elemHideException, (o: any) => o.generic.not().and(o.specific.not())),
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
[swapped[5], swapped[6]] = [swapped[6], swapped[5]];
const refusal = proveDecision(laws(model('swapped', swapped))[0]);
assert.equal(refusal.proven, false, 'swapped tiers must be refused');
assert.equal(refusal.stuck, 'sat', JSON.stringify(refusal));

// Every combination through wbe and the WebKit simulator.
const FILTERS: Record<Input, string> = {
  genericHide: '##.g',
  genericHideException: '@@||page.example^$generichide',
  specificHide: 'page.example##.s',
  elemHideException: '@@||page.example^$elemhide',
  block: '||t.example/x',
  exception: '@@||t.example/x',
  importantBlock: '||t.example/x$important',
  documentException: '@@||page.example^$document',
};
const names = TIERS.map(([n]) => n);
const dir = mkdtempSync(path.join(tmpdir(), 'wbe-precedence-'));
const list = path.join(dir, 'list.txt');
const page = 'https://page.example/';
for (let mask = 0; mask < 1 << names.length; mask++) {
  const env = Object.fromEntries(names.map((n, i) => [n, Boolean(mask & (1 << i))])) as Record<Input, boolean>;
  writeFileSync(list, names.filter((n) => env[n]).map((n) => FILTERS[n]).join('\n'));
  const rules = JSON.parse(execFileSync(WBE, ['compile', '--safari', '18.0', list], { stdio: ['ignore', 'pipe', 'ignore'] }).toString());
  const sub = rules.length ? simulate(rules, { url: 'https://t.example/x', resourceType: 'script', loadContext: 'top-frame', frameUrl: page, topUrl: page }) : null;
  const doc = rules.length ? simulate(rules, { url: page, resourceType: 'top-document', loadContext: 'top-frame', frameUrl: page, topUrl: page }) : null;
  // The exception filter targets the subresource, so it does not match the page load.
  const onPage = precedence.run({ ...env, exception: false });
  const expected = { blocked: precedence.run(env).blocked, generic: onPage.generic, specific: onPage.specific };
  const actual = {
    blocked: sub?.blocked ?? false,
    generic: doc?.hiddenSelectors.some((s) => s.split(',').includes('.g')) ?? false,
    specific: doc?.hiddenSelectors.some((s) => s.split(',').includes('.s')) ?? false,
  };
  assert.deepEqual(actual, expected, `combination ${JSON.stringify(env)}`);
}
console.log(`precedence: ${laws(precedence).length} laws proven, swapped order refused, ${1 << names.length} combinations match wbe`);
