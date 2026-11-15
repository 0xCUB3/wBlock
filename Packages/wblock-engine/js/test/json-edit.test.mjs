import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { JSDOM } from 'jsdom';

const dir = mkdtempSync(join(tmpdir(), 'wbe-json-edit-'));
let source;
try {
    execFileSync(process.execPath, [new URL('../build-scriptlets.mjs', import.meta.url).pathname, dir]);
    source = readFileSync(join(dir, 'json-edit.js'), 'utf8');
} finally { rmSync(dir, { recursive: true, force: true }); }

function setup(pattern = 'ad') {
    const dom = new JSDOM('', { url: 'https://example.com/', runScripts: 'outside-only' });
    Object.assign(dom.window, { Request, __wbeScriptletCalls: { 'json-edit': [['$.ad', 'matches', pattern]] } });
    dom.window.eval(source);
    return dom;
}

test('JSON editing preserves coercible inputs and native parse errors', () => {
    const dom = setup();
    const w = dom.window;
    try {
        const input = { toString: () => '{"ad":1,"keep":2}' };
        assert.equal(w.JSON.stringify(w.JSON.parse(input)), '{"keep":2}');
        for (const value of [null, true, false, 42]) assert.equal(w.JSON.parse(value), value);
        assert.throws(() => w.JSON.parse(undefined), { name: 'SyntaxError' });
        assert.throws(() => w.JSON.parse('{'), { name: 'SyntaxError' });
    } finally { w.close(); }
});

test('JSON editing honors matching and nonmatching strings', () => {
    for (const [pattern, expected] of [['ad', '{"keep":2}'], ['never-match', '{"ad":1,"keep":2}']]) {
        const dom = setup(pattern);
        const w = dom.window;
        try {
            assert.equal(w.JSON.stringify(w.JSON.parse('{"ad":1,"keep":2}')), expected);
            assert.equal(w.__wbeScriptletCalls['json-edit'], undefined);
        } finally { w.close(); }
    }
});

test('JSON matching survives later changes to String.prototype.includes', () => {
    const dom = setup();
    const w = dom.window;
    try {
        w.String.prototype.includes = () => { throw new Error('page replacement'); };
        assert.equal(w.JSON.stringify(w.JSON.parse('{"ad":1,"keep":2}')), '{"keep":2}');
    } finally { w.close(); }
});
