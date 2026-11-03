// Request corpus for judging a rule list against uBO: for each network filter,
// synthesized URLs that the filter should match and near misses, each with
// first- and third-party documents, plus hand-written real-world pairs.
// Deterministic for a given seed.

import { getDomain } from 'tldts';
import type { UboType } from '../oracle/index.ts';
import type { SimRequest, WkResourceType } from '../sim/webkit.ts';
import { type NetworkFilter, parseNetworkFilter } from './filters.ts';
import { REAL_WORLD } from './realworld.ts';

export interface CorpusRequest {
    // Stable identifier, e.g. "s:12:0:m" (synthetic) or "r:7" (real world).
    id: string;
    origin: 'synthetic' | 'real';
    url: string;
    uboType: UboType;
    // Document the request is made from: uBO's originURL and WebKit's frameURL.
    docUrl: string;
    // Main frame document: WebKit's mainDocumentURL.
    topUrl: string;
    // The request belongs to a frame other than the main frame.
    inChildFrame: boolean;
    // The filter line a synthetic request was derived from.
    ruleLine?: string;
}

// uBO request type to WebKit resource type. uBO's `ping` is navigator.sendBeacon,
// which WebKit reports as `other` (sim/calibrate.ts, case k51).
export const UBO_TO_WEBKIT: Record<UboType, WkResourceType> = {
    main_frame: 'top-document',
    sub_frame: 'child-document',
    stylesheet: 'style-sheet',
    script: 'script',
    image: 'image',
    font: 'font',
    media: 'media',
    xmlhttprequest: 'fetch',
    websocket: 'websocket',
    ping: 'other',
    other: 'other',
    popup: 'popup',
};

// Turns a corpus request into the input simulate() takes.
export function toSimRequest(r: CorpusRequest): SimRequest {
    return {
        url: r.url,
        resourceType: UBO_TO_WEBKIT[r.uboType],
        loadContext: r.inChildFrame ? 'child-frame' : 'top-frame',
        frameUrl: r.docUrl,
        topUrl: r.topUrl,
    };
}

// Deterministic PRNG (mulberry32).
export function prng(seed: number): () => number {
    let a = seed >>> 0;
    return () => {
        a = (a + 0x6d2b79f5) | 0;
        let t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

const SITE_HOSTS = [
    'news-desk.test', 'shop-corner.test', 'video-hub.test', 'blog-yard.test', 'travel-map.test',
    'sports-wire.test', 'recipe-box.test', 'game-arena.test', 'mail-cloud.test', 'docs-forge.test',
];
const THIRD_PARTY_HOSTS = [
    'cdn-fast.test', 'static-pool.test', 'metrics-hub.test', 'pixel-bank.test', 'tag-relay.test',
    'api-edge.test', 'img-cache.test', 'ads-serve.test',
];
const PATH_WORDS = ['banner', 'track', 'pixel', 'ad', 'asset', 'lib', 'img', 'api', 'v2', 'stats', 'css', 'frame', 'promo'];

function registrable(url: string): string {
    const host = new URL(url).hostname;
    return getDomain(host) ?? host;
}

// A document on the same registrable domain as the URL; the host itself for IP addresses.
function firstPartySite(url: string): string {
    const host = new URL(url).hostname;
    const domain = getDomain(host);
    return domain === null ? `https://${host}/` : `https://www.${domain}/`;
}

// A child frame's document, served from a subdomain of the site.
function childFrameSite(site: string): string {
    const host = new URL(site).hostname;
    return getDomain(host) === null ? `${site}f.html` : `https://frame.${host}/f.html`;
}

// First- or third-party relative to a document.
function isThirdParty(docUrl: string, url: string): boolean {
    return registrable(docUrl) !== registrable(url);
}

// A synthetic URL from a filter pattern. Returns undefined when the pattern
// cannot be turned into a valid URL.
export function synthesizeUrl(pattern: string, rnd: () => number): string | undefined {
    let rest = pattern;
    let scheme = 'https://';
    let host: string | undefined;
    if (rest.startsWith('||')) {
        rest = rest.slice(2);
        const end = rest.search(/[\/^*:|?]/);
        host = end === -1 ? rest : rest.slice(0, end);
        rest = end === -1 ? '' : rest.slice(end);
        host = host.replace(/\*/g, 'sub');
    } else if (rest.startsWith('|')) {
        rest = rest.slice(1);
        const m = /^(https?):\/\//.exec(rest);
        if (m !== null) {
            scheme = `${m[1]}://`;
            rest = rest.slice(m[0].length);
        }
    }
    if (host === undefined) {
        host = THIRD_PARTY_HOSTS[Math.floor(rnd() * THIRD_PARTY_HOSTS.length)];
        if (!rest.startsWith('/') && !rest.startsWith('^') && !rest.startsWith('*')) { rest = `/${rest}`; }
    }
    const word = PATH_WORDS[Math.floor(rnd() * PATH_WORDS.length)];
    const body = rest
        .replace(/\*/g, `${word}1`)
        .replace(/\^/g, '/')
        .replace(/\|$/, '');
    const url = `${scheme}${host}${body.startsWith('/') || body === '' ? body : `/${body}`}`;
    try {
        return new URL(url).href;
    } catch {
        return undefined;
    }
}

// Near misses for a matching URL: one small edit that should usually break the match.
export function nearMiss(url: string, rnd: () => number): string | undefined {
    const u = new URL(url);
    const choice = Math.floor(rnd() * 4);
    if (choice === 0) {
        u.hostname = `x${u.hostname}`;
    } else if (choice === 1) {
        u.pathname = u.pathname.toUpperCase();
    } else if (choice === 2) {
        u.protocol = u.protocol === 'https:' ? 'http:' : 'https:';
    } else {
        u.pathname = `${u.pathname}z`;
    }
    return u.href === url ? undefined : u.href;
}

// Candidate requests for one filter, before sampling.
function candidatesFor(filter: NetworkFilter, index: number, quota: number, rnd: () => number): CorpusRequest[] {
    const base = synthesizeUrl(filter.pattern, rnd);
    if (base === undefined) { return []; }
    const uboTypes = filter.types.length > 0 ? filter.types : ['script', 'image', 'stylesheet', 'xmlhttprequest', 'font', 'media', 'ping'];
    // Top-document filters need the document itself as the request. Popups are
    // not resource loads that a content blocker sees, so neither is synthesized.
    const allowedTypes = [...new Set(uboTypes)].filter((t) => !['main_frame', 'popup'].includes(t) && !filter.notTypes.includes(t)) as UboType[];

    const hostOptions = [...filter.domains, ...filter.excludedDomains].filter((h) => /^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(h));
    const sites = [...hostOptions, ...SITE_HOSTS.slice(0, 3)].map((h) => `https://${h}/`);
    const docs: { docUrl: string, inChildFrame: boolean, topUrl: string }[] = [];
    for (const site of [firstPartySite(base), `https://${THIRD_PARTY_HOSTS[0]}/`, ...sites]) {
        docs.push({ docUrl: site, inChildFrame: false, topUrl: site });
        docs.push({ docUrl: childFrameSite(site), inChildFrame: true, topUrl: site });
    }
    // Party is decided by the uBO document, which is what the oracle sees.
    const usable = docs.filter((d) => {
        if (filter.party === undefined) { return true; }
        const third = isThirdParty(d.docUrl, base);
        return filter.party === '3p' ? third : !third;
    });

    // Sample (type, document, variant) tuples before building requests.
    const tuples: [UboType, (typeof usable)[number], 'match' | 'near'][] = [];
    for (const uboType of allowedTypes) {
        for (const doc of usable) {
            tuples.push([uboType, doc, 'match'], [uboType, doc, 'near']);
        }
    }
    shuffle(tuples, rnd);
    const out: CorpusRequest[] = [];
    tuples.slice(0, quota).forEach(([uboType, doc, variant], i) => {
        const url = variant === 'match' ? base : nearMiss(base, rnd);
        if (url === undefined || url === doc.docUrl) { return; }
        out.push({
            id: `s:${index}:${i}${variant === 'match' ? 'm' : 'n'}`,
            origin: 'synthetic',
            url,
            uboType,
            docUrl: doc.docUrl,
            topUrl: doc.topUrl,
            inChildFrame: doc.inChildFrame,
            ruleLine: filter.line,
        });
    });
    return out;
}

function shuffle<T>(xs: T[], rnd: () => number): void {
    for (let k = xs.length - 1; k > 0; k--) {
        const j = Math.floor(rnd() * (k + 1));
        [xs[k], xs[j]] = [xs[j], xs[k]];
    }
}

export interface CorpusOptions {
    seed?: number;
    // Upper bound on synthetic requests; each filter contributes an equal share.
    maxSynthetic?: number;
}

// Corpus for the given uBO filter lists (already preprocessed), plus real-world pairs.
export function buildCorpus(listTexts: string[], options: CorpusOptions = {}): CorpusRequest[] {
    const rnd = prng(options.seed ?? 1);
    const filters: NetworkFilter[] = [];
    for (const text of listTexts) {
        for (const line of text.split('\n')) {
            const filter = parseNetworkFilter(line);
            if (filter !== undefined) { filters.push(filter); }
        }
    }
    const quota = Math.max(1, Math.floor((options.maxSynthetic ?? 400000) / Math.max(1, filters.length)));
    const synthetic: CorpusRequest[] = [];
    filters.forEach((filter, index) => {
        synthetic.push(...candidatesFor(filter, index, quota, rnd));
    });

    const real: CorpusRequest[] = REAL_WORLD.map(([page, url, uboType, frame], i) => {
        const inChildFrame = frame !== undefined;
        return {
            id: `r:${i}`,
            origin: 'real',
            url,
            uboType,
            docUrl: inChildFrame ? frame : page,
            topUrl: page,
            inChildFrame,
        };
    });
    return [...synthetic, ...real];
}
