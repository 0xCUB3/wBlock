// Markdown and self-contained HTML rendering for harness/bench/run.ts reports.

import type { EngineRun } from './run.ts';

export interface Machine {
  chip: string;
  cores: number;
  memoryGB: number;
  macOS: string;
  node: string;
  wblockCommit: string;
  sclCommit: string;
  adguardBinary: string;
  wkBinary: string;
}

export interface Report {
  timestamp: string;
  machine: Machine;
  config: {
    engines: string[];
    sets: string[];
    safari: string[];
    runs: number;
    wkRuns: number;
    lookupIterations: number;
    quick: boolean;
    snapshot: string;
    ruleLimit: number;
  };
  lists: Record<string, {
    store: string;
    combinedSha256: string;
    combinedLines: number;
    combinedBytes: number;
    lists: { url: string; lines: number; bytes: number; includeDirectives: number; rawSha256: string }[];
  }>;
  results: EngineRun[];
  warnings: string[];
}

const ENGINE_COLOR: Record<string, string> = { adguard: '#4C78A8', wbe: '#F58518' };
const ENGINE_LABEL: Record<string, string> = { adguard: 'AdGuard SafariConverterLib', wbe: 'wbe' };

const num = (v: number | null | undefined, digits = 1) =>
  typeof v === 'number' && Number.isFinite(v) ? v.toFixed(digits) : '—';

const int = (v: number | null | undefined) =>
  typeof v === 'number' && Number.isFinite(v) ? Math.round(v).toLocaleString('en-US') : '—';

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

const short = (s: string | undefined, n = 90) => (s ?? '').replace(/\s+/g, ' ').slice(0, n);

// Metrics derived from one run. null means the run has no value for that metric.
export function metricsOf(run: EngineRun) {
  const compile = run.compile;
  const sc = run.safariCompile;
  const safariMs = sc && Number.isFinite(sc.totalMs) ? sc.totalMs : null;
  const lookup = run.lookup;
  return {
    converterMs: compile ? compile.wallMs.median : null,
    converterMin: compile ? compile.wallMs.min : null,
    converterMax: compile ? compile.wallMs.max : null,
    rssMB: compile && Number.isFinite(compile.maxRssMB.median) ? compile.maxRssMB.median : null,
    nativeRules: compile ? compile.nativeRules : null,
    jsonMB: compile ? compile.jsonBytes / (1024 * 1024) : null,
    safariMs,
    totalMs: run.totalMs ?? null,
    accepted: sc ? sc.accepted : null,
    p50Us: lookup?.p50Us ?? null,
    p99Us: lookup?.p99Us ?? null,
    buildMs: lookup?.engineBuildMs ?? null,
  };
}

function statusCell(run: EngineRun): string {
  if (run.status === 'ok') return 'ok';
  return `${run.status}: ${short(run.error)}`;
}

export function renderMarkdown(report: Report): string {
  const m = report.machine;
  const lines: string[] = [];
  lines.push(`# wbe vs AdGuard SafariConverterLib: ${report.timestamp}`);
  lines.push('');
  lines.push(`- Machine: ${m.chip}, ${m.cores} cores, ${m.memoryGB} GB, macOS ${m.macOS}, Node ${m.node}`);
  lines.push(`- Commits: wBlock ${m.wblockCommit}, SafariConverterLib ${m.sclCommit}`);
  lines.push(`- Binaries: ${m.adguardBinary}, ${m.wkBinary}`);
  const c = report.config;
  lines.push(`- Config: ${c.quick ? 'quick, ' : ''}${c.runs} runs per compile (median), ${c.wkRuns} per WebKit compile, lookup iterations ${c.lookupIterations}, snapshot \`${c.snapshot}\`, Safari rule limit ${int(c.ruleLimit)}`);
  lines.push('');
  lines.push('Total time to apply filters = converter wall time (median) + WebKit compile time (median; sum over 150k-rule chunks when sharded).');
  lines.push('Converter wall time includes process start, reading the input, and writing JSON.');
  lines.push('');

  for (const version of c.safari) {
    lines.push(`## Safari ${version}`);
    lines.push('');
    lines.push('| List set | Engine | Converter ms (median, min-max) | Peak RSS MB | Native rules | JSON MB | Runtime rules | Dropped | Safari compile ms | Accepted | Total ms | Lookup p50 / p99 us | Engine build ms | Status |');
    lines.push('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|');
    for (const run of report.results.filter((r) => r.safari === version)) {
      const k = metricsOf(run);
      const dropped = run.compile ? Object.entries(run.compile.dropped).map(([name, v]) => `${name} ${int(v as number)}`).join(', ') : '—';
      const converter = run.compile ? `${num(k.converterMs)} (${num(k.converterMin)}-${num(k.converterMax)})` : '—';
      const lookup = run.lookup ? `${num(k.p50Us, 1)} / ${num(k.p99Us, 1)}` : (run.lookupError ? `n/a: ${short(run.lookupError, 60)}` : '—');
      lines.push([
        run.set,
        run.engine,
        converter,
        num(k.rssMB, 0),
        int(k.nativeRules),
        num(k.jsonMB),
        run.compile?.runtimeRules == null ? '—' : int(run.compile.runtimeRules),
        dropped,
        num(k.safariMs, 0),
        k.accepted == null ? '—' : k.accepted ? 'yes' : 'no',
        num(k.totalMs, 0),
        lookup,
        num(k.buildMs, 1),
        statusCell(run).replace(/\|/g, '/'),
      ].join(' | ').replace(/^/, '| ').replace(/$/, ' |'));
    }
    lines.push('');
  }

  lines.push('## List sets');
  lines.push('');
  lines.push('| Set | Store | Lists | Combined lines | Combined MB | Combined sha256 |');
  lines.push('|---|---|---|---|---|---|');
  for (const [name, l] of Object.entries(report.lists)) {
    lines.push(`| ${name} | ${l.store} | ${l.lists.length} | ${int(l.combinedLines)} | ${num(l.combinedBytes / 1048576)} | \`${l.combinedSha256.slice(0, 16)}\` |`);
  }
  lines.push('');
  for (const [name, l] of Object.entries(report.lists)) {
    lines.push(`${name}:`);
    for (const list of l.lists) lines.push(`- ${list.url} (${int(list.lines)} lines, ${list.includeDirectives} include directives)`);
    lines.push('');
  }

  const failures = report.results.filter((r) => r.status !== 'ok' || (r.lookupStatus && r.lookupStatus !== 'ok'));
  if (failures.length) {
    lines.push('## Engine failures');
    lines.push('');
    for (const r of failures) {
      if (r.status !== 'ok') lines.push(`- ${r.engine} ${r.set} Safari ${r.safari}: ${r.status}: ${r.error ?? ''}`);
      if (r.lookupStatus && r.lookupStatus !== 'ok') lines.push(`- ${r.engine} ${r.set} Safari ${r.safari} lookup: ${r.lookupStatus}: ${r.lookupError ?? ''}`);
    }
    lines.push('');
  }
  if (report.warnings.length) {
    lines.push('## Warnings');
    lines.push('');
    for (const w of report.warnings) lines.push(`- ${w}`);
    lines.push('');
  }
  return lines.join('\n');
}

interface Row {
  label: string;
  value: number | null;
  color: string;
  note?: string;
}

// Horizontal grouped bars: one row per (set, engine). Null values render as a labelled gap.
function barChart(title: string, unit: string, rows: Row[], digits = 0): string {
  const width = 820;
  const labelW = 300;
  const barW = width - labelW - 110;
  const rowH = 24;
  const height = rows.length * rowH + 52;
  const max = Math.max(1e-9, ...rows.map((r) => r.value ?? 0));
  const body = rows.map((r, i) => {
    const y = 36 + i * rowH;
    const label = `<text x="${labelW - 8}" y="${y + 15}" text-anchor="end" class="lbl">${esc(r.label)}</text>`;
    if (r.value === null) {
      return `${label}<text x="${labelW + 6}" y="${y + 15}" class="na">${esc(r.note ?? 'no value')}</text>`;
    }
    const w = Math.max(1, (r.value / max) * barW);
    const bar = `<rect x="${labelW}" y="${y + 4}" width="${w.toFixed(1)}" height="${rowH - 8}" fill="${r.color}"><title>${esc(r.label)}: ${r.value.toFixed(digits)} ${esc(unit)}</title></rect>`;
    const value = `<text x="${(labelW + w + 6).toFixed(1)}" y="${y + 15}" class="val">${r.value.toFixed(digits)} ${esc(unit)}</text>`;
    return `${label}${bar}${value}`;
  }).join('\n');
  return `<figure>
<figcaption><strong>${esc(title)}</strong> (${esc(unit)})</figcaption>
<svg viewBox="0 0 ${width} ${height}" width="100%" role="img" aria-label="${esc(title)}">
${body}
</svg>
</figure>`;
}

function chartRows(results: EngineRun[], version: string, pick: (m: ReturnType<typeof metricsOf>) => number | null): Row[] {
  return results.filter((r) => r.safari === version).map((r) => {
    const value = pick(metricsOf(r));
    return {
      label: `${r.set} · ${r.engine}`,
      value,
      color: ENGINE_COLOR[r.engine] ?? '#888',
      note: r.status === 'ok' ? 'not measured' : `${r.status}: ${short(r.error, 70)}`,
    };
  });
}

export function renderHtml(report: Report): string {
  const m = report.machine;
  const version = report.config.safari[0];
  const charts: [string, string, (k: ReturnType<typeof metricsOf>) => number | null, number][] = [
    ['Total time to apply filters', 'ms', (k) => k.totalMs, 0],
    ['Converter wall time (median of runs)', 'ms', (k) => k.converterMs, 0],
    ['Safari compile time (WebKit, median)', 'ms', (k) => k.safariMs, 0],
    ['Peak resident memory of the converter', 'MB', (k) => k.rssMB, 0],
    ['Native Safari rules emitted', 'rules', (k) => k.nativeRules, 0],
    ['Safari JSON size', 'MB', (k) => k.jsonMB, 1],
    ['Per-page lookup, p50', 'µs', (k) => k.p50Us, 1],
    ['Per-page lookup, p99', 'µs', (k) => k.p99Us, 1],
  ];
  const chartHtml = charts.map(([title, unit, pick, digits]) =>
    barChart(`${title}, Safari ${version}`, unit, chartRows(report.results, version, pick), digits)).join('\n');
  const tableRows = report.results.map((r) => {
    const k = metricsOf(r);
    return `<tr><td>${esc(r.safari)}</td><td>${esc(r.set)}</td><td>${esc(ENGINE_LABEL[r.engine] ?? r.engine)}</td><td>${num(k.converterMs)}</td><td>${num(k.rssMB, 0)}</td><td>${int(k.nativeRules)}</td><td>${num(k.jsonMB)}</td><td>${num(k.safariMs, 0)}</td><td>${k.accepted == null ? '—' : k.accepted ? 'yes' : 'no'}</td><td>${num(k.totalMs, 0)}</td><td>${num(k.p50Us)}</td><td>${num(k.p99Us)}</td><td>${esc(r.status === 'ok' ? 'ok' : `${r.status}: ${short(r.error, 120)}`)}</td></tr>`;
  }).join('\n');
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>wbe vs AdGuard SafariConverterLib: ${esc(report.timestamp)}</title>
<style>
  :root { color-scheme: light dark; --fg: #1d1d1f; --muted: #6e6e73; --bg: #ffffff; --line: #d2d2d7; }
  @media (prefers-color-scheme: dark) { :root { --fg: #f5f5f7; --muted: #a1a1a6; --bg: #1c1c1e; --line: #3a3a3c; } }
  body { font: 14px -apple-system, system-ui, sans-serif; color: var(--fg); background: var(--bg); margin: 24px auto; max-width: 900px; padding: 0 16px; }
  h1 { font-size: 22px; } h2 { font-size: 17px; margin-top: 32px; }
  figure { margin: 16px 0; } figcaption { margin-bottom: 4px; }
  svg text { fill: var(--fg); font: 12px -apple-system, system-ui, sans-serif; }
  svg .lbl { font-size: 12px; } svg .val { font-size: 12px; fill: var(--fg); }
  svg .na { fill: var(--muted); font-style: italic; }
  table { border-collapse: collapse; width: 100%; font-size: 12px; }
  th, td { border-bottom: 1px solid var(--line); padding: 4px 6px; text-align: right; }
  th:nth-child(-n+3), td:nth-child(-n+3) { text-align: left; }
  .meta { color: var(--muted); line-height: 1.5; }
  .legend span { display: inline-block; margin-right: 16px; }
  .swatch { display: inline-block; width: 10px; height: 10px; margin-right: 4px; border-radius: 2px; }
</style>
</head>
<body>
<h1>wbe vs AdGuard SafariConverterLib</h1>
<p class="meta">Run ${esc(report.timestamp)}. ${esc(m.chip)}, ${m.cores} cores, ${m.memoryGB} GB, macOS ${esc(m.macOS)}, Node ${esc(m.node)}.<br>
wBlock ${esc(m.wblockCommit)}, SafariConverterLib ${esc(m.sclCommit)}. ${report.config.quick ? 'Quick run: one measurement each, no lookups. ' : ''}${report.config.runs} runs per compile (median), ${report.config.wkRuns} per WebKit compile. Snapshot <code>${esc(report.config.snapshot)}</code>.</p>
<p class="legend"><span><i class="swatch" style="background:${ENGINE_COLOR.adguard}"></i>AdGuard SafariConverterLib</span><span><i class="swatch" style="background:${ENGINE_COLOR.wbe}"></i>wbe</span></p>
<p class="meta">Total time to apply filters = converter wall time + Safari compile time, medians per list set. Charts use Safari ${esc(version)}.</p>
${chartHtml}
<h2>All measurements</h2>
<table>
<thead><tr><th>Safari</th><th>Set</th><th>Engine</th><th>Converter ms</th><th>RSS MB</th><th>Native rules</th><th>JSON MB</th><th>Safari compile ms</th><th>Accepted</th><th>Total ms</th><th>Lookup p50 µs</th><th>Lookup p99 µs</th><th>Status</th></tr></thead>
<tbody>
${tableRows}
</tbody>
</table>
</body>
</html>
`;
}
