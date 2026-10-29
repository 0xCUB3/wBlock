// Preserve bytes outside a literal match, including non-text response bodies.
// Empty replacements and decoder-specific patterns still need the full-text path.
function literalReplacement(pattern, replacement) {
    if (!pattern || pattern === '*' || pattern.startsWith('/') || !replacement || replacement.includes('$') ||
        /[\uFEFF\uFFFD]/.test(pattern) || replacement.includes('\uFEFF') ||
        typeof TextEncoder !== 'function' || typeof TextDecoder !== 'function') return;
    const encoder = new TextEncoder();
    const needle = encoder.encode(pattern);
    if (new TextDecoder().decode(needle) !== pattern) return;
    const prefixes = new Uint32Array(needle.length);
    for (let i = 1, matched = 0; i < needle.length; i++) {
        while (matched > 0 && needle[i] !== needle[matched]) matched = prefixes[matched - 1];
        if (needle[i] === needle[matched]) matched++;
        prefixes[i] = matched;
    }
    return { needle, substitute: encoder.encode(replacement), prefixes };
}

function streamLiteralResponse(before, { needle, substitute, prefixes }) {
    if (!before.body || before.bodyUsed || typeof TransformStream !== 'function') return;
    let matched = 0;
    let replaced = false;
    const body = before.body.pipeThrough(new TransformStream({
        transform(chunk, controller) {
            if (replaced || (matched === 0 && !chunk.includes(needle[0]))) {
                controller.enqueue(chunk);
                return;
            }
            let output, used = 0;
            const write = bytes => {
                if (!bytes.length) return;
                if (!output || used + bytes.length > output.length) {
                    const grown = new Uint8Array(Math.max(chunk.length, used + bytes.length, (output?.length || 0) * 2));
                    if (output) grown.set(output.subarray(0, used));
                    output = grown;
                }
                output.set(bytes, used);
                used += bytes.length;
            };
            let start = 0;
            for (let i = 0; i < chunk.length; i++) {
                while (matched > 0 && chunk[i] !== needle[matched]) {
                    const next = prefixes[matched - 1];
                    write(needle.subarray(0, matched - next));
                    matched = next;
                }
                if (chunk[i] !== needle[matched]) continue;
                if (matched === 0) write(chunk.subarray(start, i));
                matched++;
                start = i + 1;
                if (matched !== needle.length) continue;
                write(substitute);
                write(chunk.subarray(i + 1));
                matched = 0;
                replaced = true;
                break;
            }
            if (!replaced && matched === 0) write(chunk.subarray(start));
            if (used) controller.enqueue(output.subarray(0, used));
        },
        flush(controller) {
            if (matched) controller.enqueue(needle.slice(0, matched));
        },
    }));
    const after = new Response(body, {status: before.status, statusText: before.statusText, headers: before.headers});
    Object.defineProperties(after, {
        ok: {value: before.ok}, redirected: {value: before.redirected},
        type: {value: before.type}, url: {value: before.url},
    });
    return after;
}

function replaceFetchResponseFn(trusted = false, pattern = '', replacement = '', propsToMatch = '', ...varargs) {
    if (trusted !== true) return;
    const safe = safeSelf();
    const logPrefix = safe.makeLogPrefix('replace-fetch-response', pattern, replacement, propsToMatch);
    const literal = literalReplacement(pattern, replacement);
    if (pattern === '*') pattern = '.*';
    const rePattern = safe.patternToRegex(pattern);
    const propNeedles = parsePropertiesToMatchFn(propsToMatch, 'url');
    const extraArgs = safe.parseVarargs(varargs);
    const reIncludes = extraArgs.includes ? safe.patternToRegex(extraArgs.includes) : null;
    self.fetch = new Proxy(self.fetch, {
        apply(target, thisArg, args) {
            const fetchPromise = Reflect.apply(target, thisArg, args);
            if (pattern === '') return fetchPromise;
            if (propNeedles.size !== 0) {
                const props = collateFetchArgumentsFn(...args);
                const matched = matchObjectPropertiesFn(propNeedles, props);
                if (matched === undefined) return fetchPromise;
                if (safe.logLevel > 1) safe.uboLog(logPrefix, `Matched "propsToMatch":\n\t${matched.join('\n\t')}`);
            }
            return fetchPromise.then(before => {
                if (literal && !reIncludes) {
                    const streamed = streamLiteralResponse(before, literal);
                    if (streamed) return streamed;
                }
                return before.clone().text().then(text => {
                    if (reIncludes && !reIncludes.test(text)) return before;
                    const after = text.replace(rePattern, replacement);
                    if (after === text) return before;
                    safe.uboLog(logPrefix, 'Replaced');
                    const response = new Response(after, {status: before.status, statusText: before.statusText, headers: before.headers});
                    Object.defineProperties(response, {
                        ok: {value: before.ok}, redirected: {value: before.redirected},
                        type: {value: before.type}, url: {value: before.url},
                    });
                    return response;
                }).catch(reason => { safe.uboErr(logPrefix, reason); return before; });
            }).catch(reason => { safe.uboErr(logPrefix, reason); return fetchPromise; });
        },
    });
}
