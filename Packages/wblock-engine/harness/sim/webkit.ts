// Simulator of WebKit's content-blocker semantics for a Safari JSON rule list.
//
// Mirrors WebKit's Source/WebCore/contentextensions: ContentExtensionParser.cpp
// (validation), ContentExtensionCompiler.cpp and URLFilterParser.cpp (url-filter
// dialect; conditions become separate top-URL and frame-URL matchers),
// DFABytecodeInterpreter.cpp (flag tests), ContentExtensionsBackend.cpp
// (condition filtering, rule order, ignore-*-rules), and
// loader/ResourceLoadInfo.cpp (party and resource flags). sim/calibrate.swift
// checks it against WKWebView.

import { getDomain } from 'tldts';

export type WkResourceType =
    | 'top-document' | 'child-document' | 'image' | 'style-sheet' | 'script'
    | 'font' | 'svg-document' | 'media' | 'popup' | 'ping' | 'fetch'
    | 'websocket' | 'csp-report' | 'other';

export interface SimRequest {
    url: string;
    resourceType: WkResourceType;
    // top-frame for the main document and its subresources; child-frame for
    // subresources of a child frame. Ignored for child documents, which are
    // always child-frame.
    loadContext: 'top-frame' | 'child-frame';
    // Document of the initiating frame, for if-frame-url. For a top-document
    // load, the URL being loaded. Ignored for child documents, which WebKit
    // evaluates against about:blank, the new frame's initial document.
    frameUrl: string;
    // Main frame URL (WebKit's mainDocumentURL): for if-domain, if-top-url and
    // load-type. For a top-document load, the URL being loaded.
    topUrl: string;
}

export interface SimResult {
    blocked: boolean;
    // Index in the rule list of the block rule that decided `blocked`.
    blockedBy?: number;
    hiddenSelectors: string[];
}

export class WebKitRuleError extends Error {}

type Party = 'first-party' | 'third-party';
type Context = 'top-frame' | 'child-frame';
type ConditionKind = 'if-domain' | 'unless-domain' | 'if-top-url' | 'unless-top-url' | 'if-frame-url' | 'unless-frame-url';
type ActionKind = 'block' | 'css' | 'ignore-previous' | 'ignore-following' | 'other';

// WebKit's trigger "resource-type" names. Group names expand to several types.
const RESOURCE_TYPE_NAMES: Record<string, WkResourceType[]> = {
    'document': ['top-document', 'child-document'],
    'top-document': ['top-document'],
    'child-document': ['child-document'],
    'image': ['image'],
    'style-sheet': ['style-sheet'],
    'script': ['script'],
    'font': ['font'],
    'raw': ['fetch', 'websocket', 'other', 'ping'],
    'websocket': ['websocket'],
    'fetch': ['fetch'],
    'other': ['other', 'ping', 'csp-report'],
    'svg-document': ['svg-document'],
    'media': ['media'],
    'popup': ['popup'],
    'ping': ['ping'],
    'csp-report': ['csp-report'],
};
const RESOURCE_TYPES = new Set<string>(Object.values(RESOURCE_TYPE_NAMES).flat());
const CONDITION_KEYS: ConditionKind[] = ['if-domain', 'unless-domain', 'if-top-url', 'unless-top-url', 'if-frame-url', 'unless-frame-url'];
const ACTION_TYPES = new Set(['block', 'ignore-previous-rules', 'ignore-following-rules', 'block-cookies', 'css-display-none', 'make-https', 'notify', 'redirect', 'modify-headers']);
const MAX_RULES = 150000;

// A compiled pattern. `literal` is a mandatory substring (lowercase) of every
// subject it matches, used to prefilter rules; empty when there is none.
interface Pattern {
    re: RegExp;
    literal: string;
    matchesAll: boolean;
}

// Prefilter key length. Rules are indexed by the rarest GRAM-gram of their literal.
const GRAM = 5;

type GateKind = 'url' | 'top' | 'frame';

interface CompiledRule {
    action: ActionKind;
    selector?: string;
    types?: Set<WkResourceType>;
    parties?: Set<Party>;
    contexts?: Set<Context>;
    url: Pattern;
    condition?: { kind: ConditionKind, patterns: Pattern[] };
}

export interface CompiledRuleList {
    rules: CompiledRule[];
    // Rules indexed by a gram of their url-filter literal (byUrl), of their
    // top-URL condition literal (byTop) or of their frame-URL condition literal
    // (byFrame). Rules without a usable literal are in `universal`.
    byUrl: Map<string, number[]>;
    byTop: Map<string, number[]>;
    byFrame: Map<string, number[]>;
    universal: number[];
}

// Translates a url-filter pattern, as URLFilterParser.cpp accepts it: no `|`,
// no `\d \w \s \b` or back-references, `^` only at the start, `$` only at the
// end, `.` any character, and quantifiers `? * +` or `{0,1} {0,} {1,}`. The
// pattern is unanchored unless it starts with `^`. Case-insensitive unless asked.
function translatePattern(pattern: string, caseSensitive: boolean): Pattern {
    type Unit = { t: 'char' | 'any' | 'class' | 'close' | 'open' | 'bol' | 'eol', src: string, q: string };
    const units: Unit[] = [];
    const fail = (why: string): never => {
        throw new WebKitRuleError(`invalid url-filter ${JSON.stringify(pattern)}: ${why}`);
    };
    const quantify = (q: string) => {
        const last = units[units.length - 1];
        if (last === undefined || ['open', 'bol', 'eol'].includes(last.t) || last.q !== '') { fail('nothing to repeat'); }
        last.q = q;
    };
    const push = (t: Unit['t'], src: string) => units.push({ t, src, q: '' });
    let depth = 0;
    let i = 0;
    while (i < pattern.length) {
        const c = pattern[i];
        if (c.charCodeAt(0) > 127) { fail('non-ASCII'); }
        if (c === '^') {
            if (i !== 0) { fail('misplaced ^'); }
            push('bol', '');
            i++;
        } else if (c === '$') {
            if (i !== pattern.length - 1) { fail('misplaced $'); }
            push('eol', '');
            i++;
        } else if (c === '|') {
            fail('disjunction');
        } else if (c === '(') {
            depth++;
            push('open', '');
            i++;
        } else if (c === ')') {
            if (depth === 0) { fail('unbalanced )'); }
            depth--;
            push('close', '');
            i++;
        } else if (c === '.') {
            push('any', '.');
            i++;
        } else if (c === '[') {
            let j = i + 1;
            const negated = pattern[j] === '^';
            if (negated) { j++; }
            let body = '';
            while (j < pattern.length && pattern[j] !== ']') {
                const d = pattern[j];
                if (d.charCodeAt(0) > 127) { fail('non-ASCII'); }
                if (d === '\\') {
                    const e = pattern[j + 1];
                    if (e === undefined || /[a-zA-Z0-9]/.test(e)) { fail('unsupported class escape'); }
                    body += `\\${e}`;
                    j += 2;
                } else {
                    body += d === '[' ? '\\[' : d;
                    j++;
                }
            }
            if (j >= pattern.length || body === '') { fail('unterminated character class'); }
            push('class', `[${negated ? '^' : ''}${body}]`);
            i = j + 1;
        } else if (c === '\\') {
            const e = pattern[i + 1];
            if (e === undefined || /[a-zA-Z0-9]/.test(e)) { fail('unsupported escape'); }
            push('char', e);
            i += 2;
        } else if (c === '*' || c === '+' || c === '?') {
            quantify(c);
            i++;
        } else {
            const m = c === '{' ? /^\{(\d+)(?:(,)(\d*))?\}/.exec(pattern.slice(i)) : null;
            if (m === null) {
                push('char', c);
                i++;
            } else {
                const min = Number(m[1]);
                const max = m[2] === undefined ? min : (m[3] === '' ? Infinity : Number(m[3]));
                if (min === 0 && max === 1) { quantify('?'); } else if (min === 0 && max === Infinity) { quantify('*'); } else if (min === 1 && max === Infinity) { quantify('+'); } else { fail('invalid quantifier'); }
                i += m[0].length;
            }
        }
    }
    if (depth !== 0) { fail('unbalanced ('); }

    const escapeJS = (ch: string) => (/[\\^$.*+?()[\]{}|/]/.test(ch) ? `\\${ch}` : ch);
    const source = units.map((u) => {
        switch (u.t) {
            case 'char': return escapeJS(u.src) + u.q;
            case 'any':
            case 'class': return u.src + u.q;
            case 'close': return `)${u.q}`;
            case 'open': return '(?:';
            case 'bol': return '^';
            case 'eol': return '$';
        }
    }).join('');
    return {
        re: new RegExp(source, caseSensitive ? 's' : 'si'),
        literal: longestLiteral(units),
        matchesAll: units.every((u) => (u.t === 'any' && u.q === '*') || u.t === 'bol'),
    };
}

// Longest run of mandatory top-level literal characters, lowercased. Every
// matching subject contains it as a substring.
function longestLiteral(units: { t: string, src: string, q: string }[]): string {
    let best = '';
    let current = '';
    for (const u of units) {
        if (u.t === 'char' && u.q === '') {
            current += u.src.toLowerCase();
        } else {
            if (current.length > best.length) { best = current; }
            current = '';
        }
    }
    return current.length > best.length ? current : best;
}

function grams(s: string): string[] {
    const out: string[] = [];
    for (let i = 0; i + GRAM <= s.length; i++) { out.push(s.slice(i, i + GRAM)); }
    return out;
}

// WebKit's getDomainList: `<scheme>://` (plus any subdomains for `*`) then the
// domain then `:` or `/`. Matched against the top URL string.
function domainPattern(domain: string, subdomains: boolean, caseSensitive: boolean): Pattern {
    if (!/^[\x00-\x7f]*$/.test(domain) || domain !== domain.toLowerCase()) {
        throw new WebKitRuleError(`domain must be lowercase ASCII: ${domain}`);
    }
    const escaped = domain.replace(/[\\{}[.?*$]/g, (ch) => `\\${ch}`);
    return translatePattern(`[a-z][a-z+.-]*:\\/\\/${subdomains ? '([^/]*\\.)*' : ''}${escaped}[:/]`, caseSensitive);
}

function booleanFlag(value: unknown, key: string): boolean {
    if (value === undefined) { return false; }
    if (typeof value !== 'boolean') { throw new WebKitRuleError(`${key} must be a boolean`); }
    return value;
}

function stringList(value: unknown, key: string): string[] {
    if (!Array.isArray(value) || value.length === 0 || value.some((v) => typeof v !== 'string' || v === '')) {
        throw new WebKitRuleError(`${key} must be a non-empty list of strings`);
    }
    return value as string[];
}

// An empty name list is accepted and means no restriction, as in WebKit.
function nameList(value: unknown, key: string, known: (name: string) => boolean): Set<string> | undefined {
    if (value === undefined) { return undefined; }
    if (!Array.isArray(value)) { throw new WebKitRuleError(`${key} must be an array`); }
    const names = new Set<string>();
    for (const name of value) {
        if (typeof name !== 'string' || !known(name)) { throw new WebKitRuleError(`unknown ${key} ${String(name)}`); }
        names.add(name);
    }
    return names.size === 0 ? undefined : names;
}

// Literals that every matching subject must contain, one per alternative, from the
// first necessary part of the rule: the url-filter, else the top-URL or frame-URL
// condition. Undefined when no part is necessary.
function gateLiterals(url: Pattern, condition?: { kind: ConditionKind, patterns: Pattern[] }): { kind: GateKind, literals: string[] } | undefined {
    if (url.literal.length >= GRAM) { return { kind: 'url', literals: [url.literal] }; }
    if (condition?.kind.startsWith('if-') && condition.patterns.every((p) => p.literal.length >= GRAM)) {
        return { kind: condition.kind.endsWith('frame-url') ? 'frame' : 'top', literals: condition.patterns.map((p) => p.literal) };
    }
    return undefined;
}

function compileRule(rule: any): { compiled: CompiledRule, gate: ReturnType<typeof gateLiterals> } {
    if (typeof rule !== 'object' || rule === null) { throw new WebKitRuleError('rule must be an object'); }
    const trigger = rule.trigger;
    if (typeof trigger !== 'object' || trigger === null) { throw new WebKitRuleError('missing trigger'); }
    if (typeof trigger['url-filter'] !== 'string' || trigger['url-filter'] === '') { throw new WebKitRuleError('missing url-filter'); }
    if (trigger['request-method'] !== undefined) { throw new WebKitRuleError('request-method is not simulated'); }

    const caseSensitive = booleanFlag(trigger['url-filter-is-case-sensitive'], 'url-filter-is-case-sensitive');
    const topCaseSensitive = booleanFlag(trigger['top-url-filter-is-case-sensitive'], 'top-url-filter-is-case-sensitive');
    const frameCaseSensitive = booleanFlag(trigger['frame-url-filter-is-case-sensitive'], 'frame-url-filter-is-case-sensitive');

    const compiled: CompiledRule = {
        action: 'other',
        url: translatePattern(trigger['url-filter'], caseSensitive),
        types: undefined,
        parties: undefined,
        contexts: undefined,
    };

    const types = nameList(trigger['resource-type'], 'resource-type', (n) => n in RESOURCE_TYPE_NAMES);
    if (types !== undefined) { compiled.types = new Set([...types].flatMap((n) => RESOURCE_TYPE_NAMES[n])); }
    const parties = nameList(trigger['load-type'], 'load-type', (n) => n === 'first-party' || n === 'third-party');
    if (parties !== undefined) { compiled.parties = parties as Set<Party>; }
    const contexts = nameList(trigger['load-context'], 'load-context', (n) => n === 'top-frame' || n === 'child-frame');
    if (contexts !== undefined) { compiled.contexts = contexts as Set<Context>; }

    const present = CONDITION_KEYS.filter((k) => trigger[k] !== undefined);
    if (present.length > 1) { throw new WebKitRuleError('at most one condition per trigger'); }
    if (present.length === 1) {
        const kind = present[0];
        const values = stringList(trigger[kind], kind);
        if (kind.endsWith('domain')) {
            compiled.condition = {
                kind,
                patterns: values.map((v) => domainPattern(v.startsWith('*') ? v.slice(1) : v, v.startsWith('*'), topCaseSensitive)),
            };
        } else {
            const cs = kind.endsWith('top-url') ? topCaseSensitive : frameCaseSensitive;
            compiled.condition = { kind, patterns: values.map((v) => translatePattern(v, cs)) };
        }
    }

    const action = rule.action;
    if (typeof action !== 'object' || action === null || typeof action.type !== 'string') { throw new WebKitRuleError('missing action'); }
    if (!ACTION_TYPES.has(action.type)) { throw new WebKitRuleError(`unknown action ${action.type}`); }
    if (action.type === 'css-display-none') {
        if (typeof action.selector !== 'string') { throw new WebKitRuleError('css-display-none needs a selector'); }
        compiled.action = 'css';
        compiled.selector = action.selector;
    } else if (action.type === 'block') {
        compiled.action = 'block';
    } else if (action.type === 'ignore-previous-rules') {
        compiled.action = 'ignore-previous';
    } else if (action.type === 'ignore-following-rules') {
        compiled.action = 'ignore-following';
    }
    // block-cookies, make-https, notify, redirect and modify-headers do not
    // change whether a load is blocked in an app-extension content blocker.

    return { compiled, gate: gateLiterals(compiled.url, compiled.condition) };
}


// Rarest-gram index: each entry is keyed by one gram of each of its literals,
// the gram least common among all entries, so the buckets stay small.
function buildIndex(entries: { rule: number, literals: string[] }[]): Map<string, number[]> {
    const frequency = new Map<string, number>();
    for (const { literals } of entries) {
        for (const literal of literals) {
            for (const g of grams(literal)) { frequency.set(g, (frequency.get(g) ?? 0) + 1); }
        }
    }
    const buckets = new Map<string, number[]>();
    for (const { rule, literals } of entries) {
        const keys = new Set<string>();
        for (const literal of literals) {
            keys.add(grams(literal).reduce((best, g) => ((frequency.get(g) ?? 0) < (frequency.get(best) ?? 0) ? g : best)));
        }
        for (const key of keys) {
            const bucket = buckets.get(key);
            if (bucket === undefined) { buckets.set(key, [rule]); } else { bucket.push(rule); }
        }
    }
    return buckets;
}

export function compileRuleList(rules: unknown): CompiledRuleList {
    if (!Array.isArray(rules)) { throw new WebKitRuleError('top level must be an array'); }
    if (rules.length > MAX_RULES) { throw new WebKitRuleError(`more than ${MAX_RULES} rules`); }
    if (rules.length === 0) { throw new WebKitRuleError('rule list contains no rules'); }
    const list: CompiledRule[] = [];
    const entries: Record<GateKind, { rule: number, literals: string[] }[]> = { url: [], top: [], frame: [] };
    const universal: number[] = [];
    rules.forEach((raw, index) => {
        const { compiled, gate } = compileRule(raw);
        list.push(compiled);
        if (gate === undefined) {
            universal.push(index);
        } else {
            entries[gate.kind].push({ rule: index, literals: gate.literals });
        }
    });
    return {
        rules: list,
        byUrl: buildIndex(entries.url),
        byTop: buildIndex(entries.top),
        byFrame: buildIndex(entries.frame),
        universal,
    };
}

const cache = new WeakMap<object, CompiledRuleList>();

function compiledFor(rules: unknown[] | CompiledRuleList): CompiledRuleList {
    if (!Array.isArray(rules)) { return rules; }
    let compiled = cache.get(rules);
    if (compiled === undefined) {
        compiled = compileRuleList(rules);
        cache.set(rules, compiled);
    }
    return compiled;
}

// Registrable domain via the public suffix list. IP addresses and other hosts
// without one compare by hostname.
function isThirdParty(topUrl: URL, url: URL): boolean {
    const domain = (host: string) => getDomain(host) ?? host;
    return domain(topUrl.hostname) !== domain(url.hostname);
}

function addCandidates(buckets: Map<string, number[]>, subject: string, into: Set<number>): void {
    const lower = subject.toLowerCase();
    for (let i = 0; i + GRAM <= lower.length; i++) {
        const bucket = buckets.get(lower.slice(i, i + GRAM));
        if (bucket !== undefined) { bucket.forEach((r) => into.add(r)); }
    }
}

function conditionHolds(condition: { kind: ConditionKind, patterns: Pattern[] }, top: string, frame: string): boolean {
    const subject = condition.kind.endsWith('frame-url') ? frame : top;
    const matched = condition.patterns.some((p) => p.re.test(subject));
    return condition.kind.startsWith('if-') ? matched : !matched;
}

// Blocks and css-display-none selectors that apply to one request. Rules are
// evaluated in list order. A matching ignore-following-rules ends the list, and a
// matching ignore-previous-rules discards everything matched before it.
export function simulate(rules: unknown[] | CompiledRuleList, req: SimRequest): SimResult {
    if (!RESOURCE_TYPES.has(req.resourceType)) { throw new WebKitRuleError(`unknown resource type ${req.resourceType}`); }
    const url = new URL(req.url);
    if (url.protocol === 'data:') { return { blocked: false, hiddenSelectors: [] }; }
    const href = url.href;
    const top = new URL(req.topUrl).href;
    const isChildDocument = req.resourceType === 'child-document';
    const frame = isChildDocument ? 'about:blank' : new URL(req.frameUrl).href;
    const context = isChildDocument ? 'child-frame' : req.loadContext;
    const list = compiledFor(rules);

    const candidates = new Set<number>(list.universal);
    addCandidates(list.byUrl, href, candidates);
    addCandidates(list.byTop, top, candidates);
    addCandidates(list.byFrame, frame, candidates);

    const party: Party = isThirdParty(new URL(top), url) ? 'third-party' : 'first-party';
    let blocked = false;
    let blockedBy: number | undefined;
    const hiddenSelectors: string[] = [];
    for (const index of [...candidates].sort((a, b) => a - b)) {
        const rule = list.rules[index];
        if (rule.types !== undefined && !rule.types.has(req.resourceType)) { continue; }
        if (rule.parties !== undefined && !rule.parties.has(party)) { continue; }
        if (rule.contexts !== undefined && !rule.contexts.has(context)) { continue; }
        if (!rule.url.matchesAll && !rule.url.re.test(href)) { continue; }
        if (rule.condition !== undefined && !conditionHolds(rule.condition, top, frame)) { continue; }
        if (rule.action === 'ignore-following') { break; }
        if (rule.action === 'ignore-previous') {
            blocked = false;
            blockedBy = undefined;
            hiddenSelectors.length = 0;
        } else if (rule.action === 'block') {
            blocked = true;
            blockedBy = index;
        } else if (rule.action === 'css') {
            hiddenSelectors.push(rule.selector!);
        }
    }
    return { blocked, blockedBy, hiddenSelectors };
}
