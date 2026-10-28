// Parser for the subset of uBO network-filter syntax the corpus synthesizes
// from. Regex filters, cosmetic filters and filters with options that change
// the request in other ways (csp, removeparam, ...) are not parsed.

export interface NetworkFilter {
    line: string;
    exception: boolean;
    pattern: string;
    // Positive uBO type names from `$type` options; empty means any type.
    types: string[];
    // Types excluded with `~type`.
    notTypes: string[];
    party?: '1p' | '3p';
    domains: string[];
    excludedDomains: string[];
}

const TYPE_OPTIONS: Record<string, string> = {
    'script': 'script',
    'image': 'image',
    'stylesheet': 'stylesheet',
    'css': 'stylesheet',
    'xmlhttprequest': 'xmlhttprequest',
    'xhr': 'xmlhttprequest',
    'subdocument': 'sub_frame',
    'frame': 'sub_frame',
    'document': 'main_frame',
    'font': 'font',
    'media': 'media',
    'websocket': 'websocket',
    'ping': 'ping',
    'beacon': 'ping',
    'other': 'other',
    'object': 'other',
    'popup': 'popup',
};

export function parseNetworkFilter(rawLine: string): NetworkFilter | undefined {
    let line = rawLine.trim();
    if (line === '' || line.startsWith('!') || line.startsWith('[')) { return undefined; }
    if (/#[@?$%]?#|#@[$%?]#/.test(line)) { return undefined; }
    const hosts = /^(?:0\.0\.0\.0|127\.0\.0\.1)\s+([a-z0-9.-]+)$/i.exec(line);
    if (hosts !== null) { line = `||${hosts[1]}^`; }
    const exception = line.startsWith('@@');
    if (exception) { line = line.slice(2); }

    let pattern = line;
    let options: string[] = [];
    const dollar = line.lastIndexOf('$');
    if (dollar !== -1 && /^[\w~,=|.-]+$/.test(line.slice(dollar + 1))) {
        pattern = line.slice(0, dollar);
        options = line.slice(dollar + 1).split(',');
    }
    if (pattern.length > 2 && pattern.startsWith('/') && pattern.endsWith('/')) { return undefined; }

    const filter: NetworkFilter = { line: rawLine.trim(), exception, pattern, types: [], notTypes: [], domains: [], excludedDomains: [] };
    for (const opt of options) {
        const negated = opt.startsWith('~');
        const name = negated ? opt.slice(1) : opt;
        if (name.startsWith('domain=') || name.startsWith('from=')) {
            for (const d of name.slice(name.indexOf('=') + 1).split('|')) {
                (d.startsWith('~') ? filter.excludedDomains : filter.domains).push(d.replace(/^~/, ''));
            }
        } else if (name === 'third-party' || name === '3p') {
            filter.party = negated ? '1p' : '3p';
        } else if (name === 'first-party' || name === '1p') {
            filter.party = negated ? '3p' : '1p';
        } else if (name in TYPE_OPTIONS) {
            (negated ? filter.notTypes : filter.types).push(TYPE_OPTIONS[name]);
        } else if (name === 'all' || name === 'important' || name === 'match-case' || name.startsWith('strict')) {
            // Accepted; these do not change which URLs the filter is synthesized for.
        } else if (name.startsWith('redirect=')) {
            // uBO blocks the request and substitutes a stub. Safari can only block it.
        } else {
            // Options that change the request outcome (csp, removeparam, ...) are skipped.
            return undefined;
        }
    }
    return filter;
}
