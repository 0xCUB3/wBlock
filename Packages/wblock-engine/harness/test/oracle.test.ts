import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createOracle } from '../oracle/index.ts';
import { stripConditionals } from '../oracle/preprocess.ts';

const LIST = [
    '||ads.example.com^',
    '@@||ads.example.com/ok^',
    '||tracker.net^$third-party',
    '||pixel.test^$image',
    '/banner.gif',
].join('\n');

describe('uBO oracle', () => {
    it('reports block, allow (exception) and none', async () => {
        const oracle = await createOracle([LIST]);
        const page = 'https://site.org/';
        assert.equal(oracle.match({ url: 'https://ads.example.com/x.js', type: 'script', docUrl: page }), 'block');
        assert.equal(oracle.match({ url: 'https://ads.example.com/ok', type: 'script', docUrl: page }), 'allow');
        assert.equal(oracle.match({ url: 'https://news.org/a.js', type: 'script', docUrl: page }), 'none');
    });

    it('applies $third-party against the document origin', async () => {
        const oracle = await createOracle([LIST]);
        assert.equal(oracle.match({ url: 'https://tracker.net/t', type: 'image', docUrl: 'https://site.org/' }), 'block');
        assert.equal(oracle.match({ url: 'https://tracker.net/t', type: 'image', docUrl: 'https://www.tracker.net/' }), 'none');
    });

    it('applies type options', async () => {
        const oracle = await createOracle([LIST]);
        assert.equal(oracle.match({ url: 'https://pixel.test/p', type: 'image', docUrl: 'https://site.org/' }), 'block');
        assert.equal(oracle.match({ url: 'https://pixel.test/p', type: 'script', docUrl: 'https://site.org/' }), 'none');
    });

    it('explains a verdict with the deciding filter line', async () => {
        const oracle = await createOracle([LIST]);
        assert.deepEqual(oracle.explain({ url: 'https://ads.example.com/x.js', type: 'script', docUrl: 'https://site.org/' }), {
            verdict: 'block',
            filter: '||ads.example.com^',
        });
        assert.deepEqual(oracle.explain({ url: 'https://news.org/', type: 'script', docUrl: 'https://site.org/' }), { verdict: 'none', filter: undefined });
    });

    it('can be created more than once in one process', async () => {
        await createOracle([LIST]);
        const second = await createOracle(['||other.test^']);
        assert.equal(second.match({ url: 'https://other.test/', type: 'script', docUrl: 'https://site.org/' }), 'block');
        assert.equal(second.match({ url: 'https://ads.example.com/x.js', type: 'script', docUrl: 'https://site.org/' }), 'none');
    });
});

describe('stripConditionals', () => {
    it('drops every !#if block, both branches included', () => {
        const text = ['keep1', '!#if env_firefox', 'drop1', '!#else', 'drop2', '!#endif', 'keep2'].join('\n');
        assert.equal(stripConditionals(text), 'keep1\nkeep2');
    });
});
