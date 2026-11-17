// Snopes swaps the article for an "allow ads" notice from an inline script
// that is the first thing in the page, before any filter-list scriptlet can
// arrive. Queue the abort for scriptlets/abort-current-script.js, which runs
// right after this file at document_start in the page world.
(globalThis.__wbeScriptletCalls ||= {})['abort-current-script'] = [['matchMedia', 'adblock_notice']];
