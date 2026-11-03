// Crude stand-in for uBO's `!#if` preprocessing: every `!#if` block is removed,
// both branches, because the conditions (env_*, cap_*, ext_*) are not evaluated.
// Good enough for demos; a real preprocessor belongs in the list downloader.
export function stripConditionals(text: string): string {
    const out: string[] = [];
    let depth = 0;
    for (const line of text.split('\n')) {
        const trimmed = line.trim();
        if (trimmed.startsWith('!#if ')) { depth++; continue; }
        if (trimmed === '!#endif') { depth = Math.max(0, depth - 1); continue; }
        if (trimmed === '!#else' || trimmed.startsWith('!#else ')) { continue; }
        if (depth === 0) { out.push(line); }
    }
    return out.join('\n');
}
