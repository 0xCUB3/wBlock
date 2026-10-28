import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { prng } from '../corpus/index.ts';
import { CALIBRATION_CASES } from '../sim/calibration-cases.ts';
import { compare, type Observation } from '../sim/calibrate.ts';
import { compileRuleList, simulate, type SimRequest, WebKitRuleError } from '../sim/webkit.ts';

const top = 'https://news.example.org/article';
const block = (urlFilter: string, trigger: Record<string, unknown> = {}) => ({ trigger: { 'url-filter': urlFilter, ...trigger }, action: { type: 'block' } });

function request(url: string, over: Partial<SimRequest> = {}): SimRequest {
    return { url, resourceType: 'script', loadContext: 'top-frame', frameUrl: top, topUrl: top, ...over };
}

const blocked = (rules: unknown[], url: string, over: Partial<SimRequest> = {}) => simulate(rules, request(url, over)).blocked;

describe('url-filter dialect', () => {
    it('matches unanchored substrings, case-insensitively by default', () => {
        assert.equal(blocked([block('banner')], 'https://cdn.test/IMG/BANNER.png'), true);
        assert.equal(blocked([block('banner')], 'https://cdn.test/logo.png'), false);
    });

    it('honours url-filter-is-case-sensitive', () => {
        const rules = [block('BANNER', { 'url-filter-is-case-sensitive': true })];
        assert.equal(blocked(rules, 'https://cdn.test/banner.png'), false);
        assert.equal(blocked(rules, 'https://cdn.test/BANNER.png'), true);
    });

    it('anchors ^ at the start and $ at the end of the URL, and $ sees the id query', () => {
        assert.equal(blocked([block('^https://ads\\.test')], 'https://ads.test/x'), true);
        assert.equal(blocked([block('^https://ads\\.test')], 'https://x.test/ads.test/x'), false);
        assert.equal(blocked([block('\\.js$')], 'https://a.test/lib.js'), true);
        assert.equal(blocked([block('\\.js$')], 'https://a.test/lib.js?v=1'), false);
    });

    it('supports . * ? [] + and {n,} quantifiers and groups', () => {
        assert.equal(blocked([block('ads.*banner')], 'https://a.test/ads/x/banner'), true);
        assert.equal(blocked([block('colou?r')], 'https://a.test/color'), true);
        assert.equal(blocked([block('colou?r')], 'https://a.test/colr'), false);
        assert.equal(blocked([block('/[0-9]+\\.gif')], 'https://a.test/p/12.gif'), true);
        assert.equal(blocked([block('(ab)+c')], 'https://a.test/ababc'), true);
    });

    it('rejects what URLFilterParser rejects', () => {
        for (const bad of ['a|b', '\\d+', '\\w', 'a\\b', '(?=x)', 'x{2,}y', 'a{3}', '^a^', 'a$b', '', '[]', 'a**', '(a']) {
            assert.throws(() => compileRuleList([block(bad)]), WebKitRuleError, bad);
        }
    });
});

describe('party, context and frames', () => {
    it('computes third-party by registrable domain of the top URL', () => {
        const rules = [block('lib', { 'load-type': ['third-party'] })];
        assert.equal(blocked(rules, 'https://static.news.example.org/lib.js'), false);
        assert.equal(blocked(rules, 'https://cdn.other.test/lib.js'), true);
    });

    it('evaluates load-context, with child documents always child-frame', () => {
        const rules = [block('lib', { 'load-context': ['top-frame'] })];
        assert.equal(blocked(rules, 'https://a.test/lib/x.js'), true);
        assert.equal(blocked(rules, 'https://a.test/lib/x.js', { loadContext: 'child-frame' }), false);
        assert.equal(blocked(rules, 'https://a.test/lib/f.html', { resourceType: 'child-document' }), false);
    });

    it('tests if-frame-url against the frame document, and child documents against about:blank', () => {
        const rules = [block('lib', { 'if-frame-url': ['frame/f1'] })];
        const frame = 'https://a.test/frame/f1.html';
        assert.equal(blocked(rules, 'https://a.test/lib/x.js', { loadContext: 'child-frame', frameUrl: frame }), true);
        assert.equal(blocked(rules, 'https://a.test/lib/x.js', { frameUrl: top }), false);
        const about = [block('frame', { 'resource-type': ['child-document'], 'if-frame-url': ['about:blank'] })];
        assert.equal(blocked(about, 'https://a.test/frame/x.html', { resourceType: 'child-document', frameUrl: top }), true);
    });

    it('tests if-domain against the top URL, with * for subdomains', () => {
        assert.equal(blocked([block('lib', { 'if-domain': ['news.example.org'] })], 'https://a.test/lib.js'), true);
        assert.equal(blocked([block('lib', { 'if-domain': ['example.org'] })], 'https://a.test/lib.js'), false);
        assert.equal(blocked([block('lib', { 'if-domain': ['*example.org'] })], 'https://a.test/lib.js'), true);
        assert.equal(blocked([block('lib', { 'unless-domain': ['*example.org'] })], 'https://a.test/lib.js'), false);
    });

    it('rejects two conditions in one trigger and non-lowercase domains', () => {
        assert.throws(() => compileRuleList([block('x', { 'if-domain': ['a.test'], 'unless-top-url': ['y'] })]), WebKitRuleError);
        assert.throws(() => compileRuleList([block('x', { 'if-domain': ['A.test'] })]), WebKitRuleError);
    });
});

describe('rule order and actions', () => {
    it('ignore-previous-rules cancels earlier matches, including css selectors', () => {
        const rules = [
            block('img'),
            { trigger: { 'url-filter': 'k.*' }, action: { type: 'css-display-none', selector: '.a' } },
            { trigger: { 'url-filter': 'keep' }, action: { type: 'ignore-previous-rules' } },
        ];
        assert.deepEqual(simulate(rules, request('https://a.test/img/keep.png')), { blocked: false, blockedBy: undefined, hiddenSelectors: [] });
        assert.equal(blocked(rules, 'https://a.test/img/other.png'), true);
    });

    it('ignore-following-rules ends the list only when it matches', () => {
        const stop = [{ trigger: { 'url-filter': 'lib' }, action: { type: 'ignore-following-rules' } }, block('lib')];
        assert.equal(blocked(stop, 'https://a.test/lib.js'), false);
        const other = [{ trigger: { 'url-filter': 'keep' }, action: { type: 'ignore-following-rules' } }, block('lib')];
        assert.equal(blocked(other, 'https://a.test/lib.js'), true);
    });

    it('collects css-display-none selectors and reports the deciding block rule', () => {
        const rules = [
            { trigger: { 'url-filter': '.*', 'if-domain': ['news.example.org'] }, action: { type: 'css-display-none', selector: '.ad' } },
            { trigger: { 'url-filter': '.*', 'if-domain': ['other.test'] }, action: { type: 'css-display-none', selector: '.no' } },
            block('lib'),
        ];
        const result = simulate(rules, request('https://a.test/lib.js'));
        assert.deepEqual(result.hiddenSelectors, ['.ad']);
        assert.equal(result.blockedBy, 2);
    });

    it('treats resource-type groups as WebKit does', () => {
        assert.equal(blocked([block('x', { 'resource-type': ['document'] })], 'https://a.test/x', { resourceType: 'child-document' }), true);
        assert.equal(blocked([block('x', { 'resource-type': ['raw'] })], 'https://a.test/x', { resourceType: 'fetch' }), true);
        assert.equal(blocked([block('x', { 'resource-type': ['other'] })], 'https://a.test/x', { resourceType: 'ping' }), true);
        assert.equal(blocked([block('x', { 'resource-type': ['ping'] })], 'https://a.test/x', { resourceType: 'other' }), false);
    });

    it('does not block data: URLs', () => {
        assert.equal(blocked([block('data')], 'data:text/plain,data'), false);
    });

    it('rejects rule lists over WebKit limits or with no rules', () => {
        assert.throws(() => compileRuleList([]), WebKitRuleError);
        assert.throws(() => compileRuleList(Array.from({ length: 150001 }, () => block('x'))), WebKitRuleError);
    });
});

describe('prefilter', () => {
    it('gives the same answers as evaluating every rule', () => {
        const rnd = prng(7);
        const words = ['ads', 'banner', 'track', 'lib', 'img', 'cdn', 'news', 'shop', 'x'];
        const pick = <T>(xs: T[]) => xs[Math.floor(rnd() * xs.length)];
        const rules: unknown[] = [];
        for (let i = 0; i < 300; i++) {
            const pattern = rnd() < 0.2 ? '.*' : `${pick(words)}${rnd() < 0.5 ? '/' : '.'}${pick(words)}`;
            const trigger: Record<string, unknown> = { 'url-filter': pattern };
            const r = rnd();
            if (r < 0.2) { trigger['if-domain'] = [`${pick(words)}.test`]; } else if (r < 0.3) { trigger['unless-top-url'] = [pick(words)]; } else if (r < 0.4) { trigger['if-top-url'] = [pick(words)]; } else if (r < 0.5) { trigger['if-frame-url'] = [pick(words)]; }
            if (rnd() < 0.3) { trigger['load-type'] = [rnd() < 0.5 ? 'first-party' : 'third-party']; }
            const action = rnd() < 0.2
                ? { type: 'css-display-none', selector: `.${pick(words)}` }
                : rnd() < 0.05 ? { type: 'ignore-previous-rules' } : { type: 'block' };
            rules.push({ trigger, action });
        }
        const list = compileRuleList(rules);
        const bruteForce = { ...list, byUrl: new Map(), byTop: new Map(), byFrame: new Map(), universal: rules.map((_, i) => i) };
        for (let i = 0; i < 500; i++) {
            const url = `https://${pick(words)}.${pick(['test', 'org'])}/${pick(words)}/${pick(words)}.js?x=${pick(words)}`;
            const req = request(url, {
                topUrl: `https://${pick(words)}.test/${pick(words)}`,
                frameUrl: `https://${pick(words)}.test/${pick(words)}`,
                loadContext: rnd() < 0.5 ? 'top-frame' : 'child-frame',
            });
            assert.deepEqual(simulate(list, req), simulate(bruteForce, req), `${url} ${JSON.stringify(req)}`);
        }
    });
});

describe('calibration against WKWebView', () => {
    const expected = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', 'sim', 'calibrate-expected.json'), 'utf8')) as { cases: Observation[] };
    const observed = new Map(expected.cases.map((o) => [o.id, o]));

    it('has a recording for every calibration case', () => {
        assert.deepEqual([...observed.keys()].sort(), CALIBRATION_CASES.map((c) => c.id).sort());
    });

    for (const c of CALIBRATION_CASES) {
        it(`${c.id}: ${c.what}`, () => {
            assert.deepEqual(compare(c, observed.get(c.id)!), []);
        });
    }
});
