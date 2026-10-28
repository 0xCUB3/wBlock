// Benchmarks AdGuard SafariConverterLib (ConverterTool) against wbe.
//
// Per list set, engine, and Safari version: converter wall time and peak RSS (/usr/bin/time -l),
// native rule counts, JSON size, real WebKit compile time (wk, sharded at 150k rules), and per-page
// lookup latency for the advanced (non-Safari) rules.
//
// Usage:
//   node harness/bench/run.ts [--engines adguard,wbe] [--sets ubo-default,wblock-current]
//     [--safari 18.0,16.4,15.4] [--runs 5] [--wk-runs 3] [--lookup-iterations 3]
//     [--snapshot NAME] [--refresh] [--quick] [--no-build] [--no-lookup]
// Writes harness/out/bench-<timestamp>.{json,md,html}. Raw outputs go to harness/.cache/runs/<timestamp>/.
// --quick: one run per measurement, no lookup benchmark. Engines that fail are recorded, not fatal.

import { spawn } from 'node:child_process';
import { closeSync, openSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CACHE_DIR, ListStore, LIST_SETS, prepareSet } from '../lib/lists.ts';
import type { PreparedSet } from '../lib/lists.ts';
import { renderHtml, renderMarkdown } from './report.ts';
import type { Report } from './report.ts';

const BENCH_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_DIR = path.resolve(BENCH_DIR, '../..');
const OUT_DIR = path.resolve(BENCH_DIR, '../out');
const URLS_FILE = path.join(BENCH_DIR, 'urls.txt');
const AG_LOOKUP_DIR = path.join(BENCH_DIR, 'ag-lookup');
const SCL_DIR = process.env.SCL_PATH ?? '/tmp/research/bench/scl';
const ADGUARD_BIN = process.env.ADGUARD_CONVERTER ?? path.join(SCL_DIR, '.build/release/ConverterTool');
const WK_BIN = process.env.WK_BIN ?? '/tmp/research/bench/wk';
const WBE_BIN = process.env.WBE_BIN ?? path.join(REPO_DIR, 'target/release/wbe');
const SAFARI_RULE_LIMIT = 150_000;

const ALL_ENGINES = ['adguard', 'wbe'];
type Engine = (typeof ALL_ENGINES)[number];

interface Options {
  engines: Engine[];
  sets: string[];
  safari: string[];
  runs: number;
  wkRuns: number;
  lookupIterations: number;
  snapshot: string;
  refresh: boolean;
  quick: boolean;
  build: boolean;
  lookup: boolean;
}

function parseOptions(argv: string[]): Options {
  const opts: Options = {
    engines: ALL_ENGINES,
    sets: ['ubo-default', 'wblock-current'],
    safari: ['18.0', '16.4', '15.4'],
    runs: 5,
    wkRuns: 3,
    lookupIterations: 3,
    snapshot: 'bench-default',
    refresh: false,
    quick: false,
    build: true,
    lookup: true,
  };
  const list = (v: string) => v.split(',').map((s) => s.trim()).filter(Boolean);
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new Error(`${flag} needs a value`);
      return v;
    };
    switch (flag) {
      case '--engines': opts.engines = list(next()) as Engine[]; break;
      case '--sets': opts.sets = list(next()); break;
      case '--safari': opts.safari = list(next()); break;
      case '--runs': opts.runs = Number(next()); break;
      case '--wk-runs': opts.wkRuns = Number(next()); break;
      case '--lookup-iterations': opts.lookupIterations = Number(next()); break;
      case '--snapshot': opts.snapshot = next(); break;
      case '--refresh': opts.refresh = true; break;
      case '--quick': opts.quick = true; break;
      case '--no-build': opts.build = false; break;
      case '--no-lookup': opts.lookup = false; break;
      default: throw new Error(`unknown argument: ${flag}`);
    }
  }
  for (const e of opts.engines) if (!ALL_ENGINES.includes(e)) throw new Error(`unknown engine: ${e}`);
  for (const s of opts.sets) if (!LIST_SETS[s]) throw new Error(`unknown list set: ${s}`);
  if (opts.quick) {
    opts.runs = 1;
    opts.wkRuns = 1;
    opts.lookup = false;
  }
  return opts;
}

interface Exec {
  code: number | null;
  signal: NodeJS.Signals | null;
  stdout: Buffer;
  stderr: string;
  wallMs: number;
  maxRssBytes: number | null;
}

// Runs a command, optionally under /usr/bin/time -l (peak RSS). stdin comes from a file descriptor
// so large inputs are not copied through Node.
function exec(cmd: string, args: string[], opts: { timed?: boolean; stdinFile?: string; cwd?: string } = {}): Promise<Exec> {
  const bin = opts.timed ? '/usr/bin/time' : cmd;
  const binArgs = opts.timed ? ['-l', cmd, ...args] : args;
  const stdinFd = opts.stdinFile ? openSync(opts.stdinFile, 'r') : 'ignore';
  return new Promise((resolve, reject) => {
    const start = performance.now();
    const child = spawn(bin, binArgs, { stdio: [stdinFd, 'pipe', 'pipe'], cwd: opts.cwd });
    const out: Buffer[] = [];
    const err: Buffer[] = [];
    child.stdout.on('data', (c: Buffer) => out.push(c));
    child.stderr.on('data', (c: Buffer) => err.push(c));
    child.on('error', (e) => {
      if (typeof stdinFd === 'number') closeSync(stdinFd);
      reject(e);
    });
    child.on('close', (code, signal) => {
      if (typeof stdinFd === 'number') closeSync(stdinFd);
      const stderr = Buffer.concat(err).toString('utf8');
      const rss = stderr.match(/(\d+)\s+maximum resident set size/);
      resolve({
        code,
        signal,
        stdout: Buffer.concat(out),
        stderr,
        wallMs: performance.now() - start,
        maxRssBytes: rss ? Number(rss[1]) : null,
      });
    });
  });
}

interface Stat {
  median: number;
  min: number;
  max: number;
  runs: number[];
}

function stat(values: number[]): Stat {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  const median = sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  return { median, min: sorted[0], max: sorted[sorted.length - 1], runs: values };
}

// Last non-empty stderr line that is not the /usr/bin/time report.
function errorLine(stderr: string, code: number | null, signal: string | null): string {
  const lines = stderr.split('\n').map((l) => l.trim()).filter((l) => l && !/maximum resident|real\s+\d|user\s+\d/.test(l));
  const marker = lines.find((l) => /panicked|error|fatal/i.test(l)) ?? lines[lines.length - 1];
  return marker ?? `exit ${code ?? signal}`;
}

interface Chunk {
  file: string;
  rules: number;
  bytes: number;
  compileMs: Stat;
  accepted: boolean;
  error?: string;
}

interface SafariCompile {
  accepted: boolean;
  sharded: boolean;
  totalMs: number;
  chunks: Chunk[];
}

interface EngineOutput {
  rulesJson: string;
  rules: unknown[];
  advancedText: string | null;
}

interface Compile {
  wallMs: Stat;
  maxRssMB: Stat;
  nativeRules: number;
  jsonBytes: number;
  advancedRules: number | null;
  runtimeRules: number | null;
  dropped: Record<string, number>;
  internalMs?: Stat;
}

interface Lookup {
  engineBuildMs?: number;
  loadMs?: number;
  p50Us?: number;
  p99Us?: number;
  meanUs?: number;
  pagesWithCosmeticRules?: number;
  wallMs?: number;
  raw?: string;
}

export interface EngineRun {
  engine: Engine;
  set: string;
  safari: string;
  status: 'ok' | 'failed' | 'unavailable' | 'skipped';
  error?: string;
  compile?: Compile;
  safariCompile?: SafariCompile;
  lookup?: Lookup;
  lookupStatus?: 'ok' | 'failed' | 'unavailable' | 'skipped';
  lookupError?: string;
  totalMs?: number;
}

const runsRoot = (stamp: string) => path.join(CACHE_DIR, 'runs', stamp);

// AdGuard ConverterTool: JSON on stdout; advanced rules are in advancedRulesText.
async function runAdguard(set: PreparedSet, version: string, timed: boolean) {
  const ex = await exec(ADGUARD_BIN, ['--safari-version', version, '--advanced-blocking', 'true'], {
    timed,
    stdinFile: set.combinedFile,
  });
  if (ex.code !== 0) throw new Error(errorLine(ex.stderr, ex.code, ex.signal));
  const json = JSON.parse(ex.stdout.toString('utf8')) as {
    safariRulesJSON: string;
    safariRulesCount: number;
    advancedRulesCount: number;
    discardedSafariRules: number;
    errorsCount: number;
    advancedRulesText?: string;
  };
  const rules = JSON.parse(json.safariRulesJSON) as unknown[];
  const output: EngineOutput = {
    rulesJson: json.safariRulesJSON,
    rules,
    advancedText: json.advancedRulesText ?? null,
  };
  return {
    output,
    sample: {
      wallMs: ex.wallMs,
      maxRssBytes: ex.maxRssBytes,
      nativeRules: json.safariRulesCount,
      jsonBytes: Buffer.byteLength(json.safariRulesJSON),
      advancedRules: json.advancedRulesCount,
      runtimeRules: null,
      dropped: {
        overLimit: json.discardedSafariRules,
        unconvertible: json.errorsCount,
      },
    },
  };
}

// wbe: Safari JSON on stdout, stats JSON as the last stderr line.
async function runWbe(set: PreparedSet, version: string, runtimeFile: string, timed: boolean) {
  const files = set.lists.map((l) => l.file);
  const ex = await exec(WBE_BIN, ['compile', '--safari', version, '--runtime-out', runtimeFile, ...files], { timed });
  if (ex.code !== 0) throw new Error(errorLine(ex.stderr, ex.code, ex.signal));
  const rulesJson = ex.stdout.toString('utf8');
  const rules = JSON.parse(rulesJson) as unknown[];
  const statsLine = ex.stderr.split('\n').filter((l) => l.startsWith('{')).pop();
  const stats = statsLine ? (JSON.parse(statsLine) as { compile_ms: number; stats: Record<string, number> }) : null;
  const runtimeText = await readFile(runtimeFile, 'utf8').catch(() => '');
  const runtimeRules = runtimeText.split('\n').filter((l) => l.trim()).length;
  return {
    output: { rulesJson, rules, advancedText: runtimeText } as EngineOutput,
    sample: {
      wallMs: ex.wallMs,
      maxRssBytes: ex.maxRssBytes,
      nativeRules: rules.length,
      jsonBytes: Buffer.byteLength(rulesJson),
      advancedRules: null,
      runtimeRules,
      dropped: stats?.stats ?? {},
      internalMs: stats?.compile_ms ?? null,
    },
  };
}

// Compiles one output with WebKit's real content-rule compiler. Lists above the Safari limit are
// cut into consecutive 150k-rule chunks, one JSON file each, and every chunk is compiled.
async function safariCompile(output: EngineOutput, dir: string, name: string, wkRuns: number): Promise<SafariCompile> {
  const sharded = output.rules.length > SAFARI_RULE_LIMIT;
  const pieces: { rules: number; text: string }[] = [];
  if (!sharded) {
    pieces.push({ rules: output.rules.length, text: output.rulesJson });
  } else {
    for (let start = 0; start < output.rules.length; start += SAFARI_RULE_LIMIT) {
      const slice = output.rules.slice(start, start + SAFARI_RULE_LIMIT);
      pieces.push({ rules: slice.length, text: JSON.stringify(slice) });
    }
  }
  const chunks: Chunk[] = [];
  for (const [i, piece] of pieces.entries()) {
    const file = path.join(dir, `${name}${sharded ? `-chunk${i}` : ''}.json`);
    await writeFile(file, piece.text);
    const times: number[] = [];
    let accepted = true;
    let error: string | undefined;
    for (let r = 0; r < wkRuns; r++) {
      const ex = await exec(WK_BIN, [file]);
      const m = ex.stdout.toString('utf8').match(/^compile:\s+([\d.e+-]+)\s+(.*)$/m);
      if (!m) {
        accepted = false;
        error = errorLine(ex.stderr || ex.stdout.toString('utf8'), ex.code, ex.signal);
        break;
      }
      times.push(Number(m[1]) * 1000);
      if (m[2].trim() !== 'ok') {
        accepted = false;
        error = m[2].trim();
        break;
      }
    }
    chunks.push({
      file,
      rules: piece.rules,
      bytes: Buffer.byteLength(piece.text),
      compileMs: stat(times.length ? times : [NaN]),
      accepted,
      error,
    });
  }
  const accepted = chunks.every((c) => c.accepted);
  return {
    accepted,
    sharded,
    totalMs: accepted ? chunks.reduce((sum, c) => sum + c.compileMs.median, 0) : NaN,
    chunks,
  };
}

async function runLookupAdguard(advancedFile: string, workDir: string, version: string, iterations: number): Promise<Lookup> {
  const bin = path.join(AG_LOOKUP_DIR, '.build/release/ag-lookup');
  const ex = await exec(bin, [advancedFile, URLS_FILE, String(iterations), workDir, version]);
  if (ex.code !== 0) throw new Error(errorLine(ex.stderr, ex.code, ex.signal));
  const j = JSON.parse(ex.stdout.toString('utf8')) as Record<string, number>;
  return {
    engineBuildMs: j.engineBuildMs,
    loadMs: j.loadMs,
    p50Us: j.p50Us,
    p99Us: j.p99Us,
    meanUs: j.meanUs,
    pagesWithCosmeticRules: j.pagesWithCosmeticRules,
  };
}

// wbe lookup benchmark. The subcommands are added by another agent; a missing subcommand is
// reported as unavailable rather than a failure.
async function runLookupWbe(set: PreparedSet, version: string, workDir: string, iterations: number): Promise<Lookup> {
  await mkdir(workDir, { recursive: true });
  const engineFile = path.join(workDir, 'engine.bin');
  const files = set.lists.map((l) => l.file);
  const build = await exec(WBE_BIN, ['engine-build', '--safari', version, '--out', engineFile, ...files], { timed: false });
  if (build.code !== 0) throw Object.assign(new Error(errorLine(build.stderr, build.code, build.signal)), { unavailable: build.code === 2 });
  const look = await exec(WBE_BIN, ['lookup', '--bench', String(iterations), engineFile, URLS_FILE]);
  if (look.code !== 0) throw Object.assign(new Error(errorLine(look.stderr, look.code, look.signal)), { unavailable: look.code === 2 });
  const text = look.stdout.toString('utf8').trim();
  try {
    const j = JSON.parse(text.split('\n').pop() ?? '') as Record<string, number>;
    return { engineBuildMs: build.wallMs, p50Us: j.p50Us, p99Us: j.p99Us, meanUs: j.meanUs, loadMs: j.loadMs, wallMs: look.wallMs, raw: text.slice(0, 500) };
  } catch {
    return { engineBuildMs: build.wallMs, wallMs: look.wallMs, raw: text.slice(0, 500) };
  }
}

function toMB(bytes: number): number {
  return bytes / (1024 * 1024);
}

async function machineInfo(): Promise<Report['machine']> {
  const sh = async (cmd: string, args: string[], cwd?: string) => {
    const ex = await exec(cmd, args, { cwd }).catch(() => null);
    return ex && ex.code === 0 ? ex.stdout.toString('utf8').trim() : 'unknown';
  };
  const dirty = (await sh('git', ['status', '--porcelain'], REPO_DIR)) !== '';
  return {
    chip: await sh('sysctl', ['-n', 'machdep.cpu.brand_string']),
    cores: os.cpus().length,
    memoryGB: Math.round(os.totalmem() / 2 ** 30),
    macOS: `${await sh('sw_vers', ['-productVersion'])} (${await sh('sw_vers', ['-buildVersion'])})`,
    node: process.version,
    wblockCommit: `${await sh('git', ['rev-parse', '--short', 'HEAD'], REPO_DIR)}${dirty ? ' (dirty worktree)' : ''}`,
    sclCommit: await sh('git', ['rev-parse', '--short', 'HEAD'], SCL_DIR),
    adguardBinary: ADGUARD_BIN,
    wkBinary: WK_BIN,
  };
}

// Returns an error message, or null when the build succeeded.
async function build(what: string, cmd: string, args: string[], cwd: string): Promise<string | null> {
  const ex = await exec(cmd, args, { cwd }).catch((e: Error) => ({ code: -1, stderr: e.message, signal: null, stdout: Buffer.alloc(0), wallMs: 0, maxRssBytes: null }));
  return ex.code === 0 ? null : `${what} build failed: ${errorLine(ex.stderr, ex.code, ex.signal)}`;
}

async function main() {
  const opts = parseOptions(process.argv.slice(2));
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const root = runsRoot(stamp);
  await mkdir(root, { recursive: true });
  await mkdir(OUT_DIR, { recursive: true });
  const warnings: string[] = [];

  const buildErrors: Partial<Record<Engine | 'ag-lookup', string>> = {};
  if (opts.build) {
    if (opts.engines.includes('wbe')) {
      const err = await build('wbe', 'cargo', ['build', '--release'], REPO_DIR);
      if (err) buildErrors.wbe = err;
    }
    if (opts.lookup && opts.engines.includes('adguard')) {
      const err = await build('ag-lookup', 'swift', ['build', '-c', 'release'], AG_LOOKUP_DIR);
      if (err) buildErrors['ag-lookup'] = err;
    }
  }

  const store = await ListStore.open(opts.snapshot, opts.refresh);
  const prepared: Record<string, PreparedSet> = {};
  for (const name of opts.sets) prepared[name] = await prepareSet(name, store);
  warnings.push(...store.warnings);

  const results: EngineRun[] = [];
  for (const set of opts.sets) {
    for (const version of opts.safari) {
      for (const engine of opts.engines) {
        const id = `${engine}-${set}-${version}`;
        const dir = path.join(root, id);
        await mkdir(dir, { recursive: true });
        const run: EngineRun = { engine, set, safari: version, status: 'ok' };
        results.push(run);
        if (engine === 'wbe' && buildErrors.wbe) {
          Object.assign(run, { status: 'failed', error: buildErrors.wbe });
          continue;
        }
        try {
          const wall: number[] = [];
          const rss: number[] = [];
          const internal: number[] = [];
          let first: Awaited<ReturnType<typeof runAdguard>> | Awaited<ReturnType<typeof runWbe>> | null = null;
          for (let r = 0; r < opts.runs; r++) {
            const sample = engine === 'adguard'
              ? await runAdguard(prepared[set], version, true)
              : await runWbe(prepared[set], version, path.join(dir, 'runtime.txt'), true);
            wall.push(sample.sample.wallMs);
            if (sample.sample.maxRssBytes !== null) rss.push(toMB(sample.sample.maxRssBytes));
            if ('internalMs' in sample.sample && sample.sample.internalMs) internal.push(sample.sample.internalMs);
            first ??= sample;
          }
          if (!first) throw new Error('no runs');
          const s = first.sample;
          run.compile = {
            wallMs: stat(wall),
            maxRssMB: stat(rss.length ? rss : [NaN]),
            nativeRules: s.nativeRules,
            jsonBytes: s.jsonBytes,
            advancedRules: s.advancedRules,
            runtimeRules: s.runtimeRules,
            dropped: s.dropped as Record<string, number>,
            ...(internal.length ? { internalMs: stat(internal) } : {}),
          };
          if (first.output.advancedText !== null && engine === 'adguard') {
            await writeFile(path.join(dir, 'advanced.txt'), first.output.advancedText);
          }
          run.safariCompile = await safariCompile(first.output, dir, id, opts.wkRuns);
          run.totalMs = run.safariCompile.accepted ? run.compile.wallMs.median + run.safariCompile.totalMs : undefined;
        } catch (error) {
          const e = error as Error & { unavailable?: boolean };
          Object.assign(run, { status: e.unavailable ? 'unavailable' : 'failed', error: e.message });
        }
      }
    }
  }

  if (opts.lookup) {
    for (const run of results) {
      if (run.status !== 'ok') continue;
      const workDir = path.join(root, 'lookup', `${run.engine}-${run.set}-${run.safari}`);
      if (run.engine === 'adguard' && buildErrors['ag-lookup']) {
        run.lookupStatus = 'unavailable';
        run.lookupError = buildErrors['ag-lookup'];
        continue;
      }
      try {
        run.lookup = run.engine === 'adguard'
          ? await runLookupAdguard(path.join(root, `adguard-${run.set}-${run.safari}`, 'advanced.txt'), workDir, run.safari, opts.lookupIterations)
          : await runLookupWbe(prepared[run.set], run.safari, workDir, opts.lookupIterations);
        run.lookupStatus = 'ok';
      } catch (error) {
        const e = error as Error & { unavailable?: boolean };
        run.lookupStatus = e.unavailable ? 'unavailable' : 'failed';
        run.lookupError = e.message;
      }
    }
  }

  const report: Report = {
    timestamp: stamp,
    machine: await machineInfo(),
    config: {
      engines: opts.engines,
      sets: opts.sets,
      safari: opts.safari,
      runs: opts.runs,
      wkRuns: opts.wkRuns,
      lookupIterations: opts.lookupIterations,
      quick: opts.quick,
      snapshot: opts.snapshot,
      ruleLimit: SAFARI_RULE_LIMIT,
    },
    lists: Object.fromEntries(
      Object.values(prepared).map((p) => [p.name, {
        store: p.store,
        combinedSha256: p.combinedSha256,
        combinedLines: p.combinedLines,
        combinedBytes: p.combinedBytes,
        lists: p.lists.map((l) => ({ url: l.url, lines: l.lines, bytes: l.bytes, includeDirectives: l.includeDirectives, rawSha256: l.rawSha256 })),
      }]),
    ),
    results,
    warnings,
  };
  const base = path.join(OUT_DIR, `bench-${stamp}`);
  await writeFile(`${base}.json`, JSON.stringify(report, null, 2) + '\n');
  await writeFile(`${base}.md`, renderMarkdown(report));
  await writeFile(`${base}.html`, renderHtml(report));
  console.log(renderMarkdown(report));
  console.log(`wrote ${base}.{json,md,html}`);
}

await main();
