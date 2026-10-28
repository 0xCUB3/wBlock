// Filter-list download, pinning, and uBO-style preprocessing for the benchmark harness.
// Conditionals mirror wBlockCoreService/ConditionalEvaluator.swift; includes mirror
// wBlockCoreService/IncludeResolver.swift and FilterPreprocessor.swift.
//
// CLI: node harness/lib/lists.ts [--set NAME]... [--snapshot NAME] [--refresh]

import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HARNESS_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const CACHE_DIR = path.join(HARNESS_DIR, '.cache');

const AG_SAFARI = 'https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters';
const AG_MAC = 'https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/mac_v3/filters';
const UBO = 'https://ublockorigin.github.io/uAssets';

// Default-enabled entries of uBO assets/assets.json (no "off": true), first contentURL.
const UBO_DEFAULT = [
  `${UBO}/filters/filters.txt`, // ublock-filters
  `${UBO}/filters/badware.txt`, // ublock-badware
  `${UBO}/filters/privacy.txt`, // ublock-privacy
  `${UBO}/filters/unbreak.txt`, // ublock-unbreak
  `${UBO}/filters/quick-fixes.txt`, // ublock-quick-fixes
  `${UBO}/thirdparties/easylist.txt`, // easylist
  `${UBO}/thirdparties/easyprivacy.txt`, // easyprivacy
  'https://malware-filter.gitlab.io/urlhaus-filter/urlhaus-filter-vivaldi-online.txt', // urlhaus-1
  'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=1&mimetype=plaintext', // plowe-0
];

// wBlock's effective default selection on macOS: FilterListLoader.recommendedFilterNames
// (overrides the inline isSelected flags).
const WBLOCK_CURRENT = [
  `${AG_SAFARI}/2_optimized.txt`, // AdGuard Base Filter
  `${AG_SAFARI}/3_optimized.txt`, // AdGuard Tracking Protection Filter
  `${AG_MAC}/17_optimized.txt`, // AdGuard URL Tracking Protection Filter
  `${AG_MAC}/251_optimized.txt`, // Actually Legitimate URL Shortener Tool
  `${AG_SAFARI}/204_optimized.txt`, // Peter Lowe's Blocklist
  `${AG_SAFARI}/18_optimized.txt`, // AdGuard Cookie Notices
  'https://raw.githubusercontent.com/0xCUB3/wBlock/main/filters/ad-tracking-hosts.txt', // wBlock Ad and Tracking Hosts
];

// Regional picks: the three largest of AdGuard's regional lists by size (Japanese, Chinese, Russian).
const HEAVY = [
  ...UBO_DEFAULT,
  `${UBO}/filters/annoyances.txt`, // ublock-annoyances (includes annoyances-others.txt)
  `${UBO}/filters/annoyances-cookies.txt`, // ublock-cookies-adguard / -easylist
  `${AG_SAFARI}/2_optimized.txt`, // AdGuard Base
  `${AG_SAFARI}/3_optimized.txt`, // AdGuard Tracking Protection
  `${AG_SAFARI}/14_optimized.txt`, // AdGuard Annoyances
  `${AG_SAFARI}/7_optimized.txt`, // AdGuard Japanese
  `${AG_SAFARI}/224_optimized.txt`, // AdGuard Chinese
  `${AG_SAFARI}/1_optimized.txt`, // AdGuard Russian
];

export const LIST_SETS: Record<string, { description: string; urls: string[] }> = {
  'ubo-default': { description: "uBlock Origin's default-enabled lists", urls: [...new Set(UBO_DEFAULT)] },
  'wblock-current': { description: "wBlock's default-selected lists (macOS)", urls: [...new Set(WBLOCK_CURRENT)] },
  heavy: { description: 'ubo-default + uBO annoyances + AdGuard Base/Tracking/Annoyances + 3 regional', urls: [...new Set(HEAVY)] },
};

// PlatformConstants.value(for:) is true only for these names on macOS (env_mobile is false).
const TRUE_CONSTANTS = new Set(['true', 'adguard', 'adguard_ext_safari', 'env_safari']);
const MAX_INCLUDE_DEPTH = 5;
const MAX_EXPANDED_LINES = 500_000;

const isIfLine = (t: string) => t === '!#if' || t.startsWith('!#if ');

export function splitLines(text: string): string[] {
  return text.split(/\r\n|[\n\v\f\r\u0085\u2028\u2029]/);
}

function findBlockEnd(lines: string[], target: string, from: number, to: number): number {
  let depth = 0;
  for (let i = from; i < to; i++) {
    const t = lines[i].trim();
    if (isIfLine(t)) {
      depth++;
    } else if (t.startsWith('!#endif')) {
      if (depth === 0) return target === '!#endif' ? i : -1;
      depth--;
    } else if (depth === 0 && t.startsWith(target)) {
      return i;
    }
  }
  return -1;
}

function evaluateExpression(raw: string): boolean {
  const expr = raw.trim();
  if (!expr) return false;

  const open = expr.lastIndexOf('(');
  if (open !== -1) {
    const close = expr.indexOf(')', open + 1);
    if (close !== -1) {
      const inner = evaluateExpression(expr.slice(open + 1, close));
      return evaluateExpression(`${expr.slice(0, open)}${inner ? 'true' : 'false'}${expr.slice(close + 1)}`);
    }
  }

  const or = expr.indexOf('||');
  if (or !== -1) {
    return evaluateExpression(expr.slice(0, or)) || evaluateExpression(expr.slice(or + 2));
  }
  const and = expr.indexOf('&&');
  if (and !== -1) {
    return evaluateExpression(expr.slice(0, and)) && evaluateExpression(expr.slice(and + 2));
  }
  if (expr.startsWith('!')) return !evaluateExpression(expr.slice(1));
  return TRUE_CONSTANTS.has(expr);
}

function evaluateCondition(ifLine: string): boolean {
  const prefix = '!#if ';
  if (!ifLine.startsWith(prefix)) return false;
  return evaluateExpression(ifLine.slice(prefix.length));
}

// ConditionalEvaluator.resolveConditions: keeps non-directive lines verbatim, drops directives.
export function evaluateConditionals(lines: string[]): string[] {
  const out: string[] = [];
  let i = 0;
  while (i < lines.length) {
    const t = lines[i].trim();
    if (isIfLine(t)) {
      const end = findBlockEnd(lines, '!#endif', i + 1, lines.length);
      if (end === -1) {
        i++;
        continue;
      }
      const elseIdx = findBlockEnd(lines, '!#else', i + 1, end);
      if (evaluateCondition(t)) {
        pushAll(out, evaluateConditionals(lines.slice(i + 1, elseIdx === -1 ? end : elseIdx)));
      } else if (elseIdx !== -1) {
        pushAll(out, evaluateConditionals(lines.slice(elseIdx + 1, end)));
      }
      i = end + 1;
    } else if (t.startsWith('!#else') || t.startsWith('!#endif')) {
      i++;
    } else {
      out.push(lines[i]);
      i++;
    }
  }
  return out;
}

// Avoids spreading huge arrays into push(), which overflows the call stack.
function pushAll(target: string[], items: string[]): void {
  for (const item of items) target.push(item);
}

// IncludePath.includePath(from:): "!#include p" or "%include p%" (non-https URLs rejected).
export function includePath(line: string): string | null {
  if (line.startsWith('!#include')) return line.slice('!#include'.length).trim();
  if (!line.startsWith('%include ') || !line.endsWith('%')) return null;
  const p = line.slice('%include '.length, -1).trim();
  if (p.includes(':') && !p.startsWith('https://')) return null;
  return p;
}

// IncludeResolver.resolveSublistURL: percent-encodes stray characters but keeps existing escapes.
function resolveSublistURL(rawPath: string, base: URL): URL | null {
  const trimmed = rawPath.trim();
  if (!trimmed) return null;
  const encoded = trimmed.replace(/[^\w\-.~!$&'()*+,;=:@/?#%[\]]/gu, (c) => encodeURIComponent(c));
  try {
    return new URL(encoded, base);
  } catch {
    return null;
  }
}

function visitKey(url: URL): string {
  const copy = new URL(url.href);
  copy.hash = '';
  return copy.href;
}

const GITHUB_CONTENT_HOSTS = new Set(['raw.githubusercontent.com', 'cdn.jsdelivr.net']);

function githubRevision(url: URL): string | null {
  const parts = url.pathname.split('/').filter(Boolean);
  if (url.hostname === 'raw.githubusercontent.com') {
    if (parts.length < 3) return null;
    let ref = parts[2];
    if (parts[2] === 'refs') {
      if (parts.length < 5 || (parts[3] !== 'heads' && parts[3] !== 'tags')) return null;
      ref = parts[4];
    }
    return `${parts[0].toLowerCase()}/${parts[1].toLowerCase()}@${ref}`;
  }
  if (parts.length < 3 || parts[0] !== 'gh') return null;
  const repo = parts[2].split('@');
  if (repo.length !== 2 || !repo[0] || !repo[1]) return null;
  return `${parts[1].toLowerCase()}/${repo[0].toLowerCase()}@${repo[1]}`;
}

// IncludeResolver.isSameOrigin: scheme and host must match (default ports compare equal);
// raw.githubusercontent.com and cdn.jsdelivr.net may serve the same repo at the same revision.
export function isSameOrigin(url: URL, base: URL): boolean {
  if (url.protocol !== base.protocol) return false;
  if (url.hostname !== base.hostname) {
    const rev = githubRevision(url);
    return (
      url.protocol === 'https:' &&
      GITHUB_CONTENT_HOSTS.has(url.hostname) &&
      GITHUB_CONTENT_HOSTS.has(base.hostname) &&
      url.port === '' &&
      base.port === '' &&
      url.username === '' &&
      base.username === '' &&
      rev !== null &&
      rev === githubRevision(base)
    );
  }
  return url.port === base.port;
}

interface Context {
  store: ListStore;
  warnings: string[];
  includeDirectives: number;
}

async function expandIncludes(lines: string[], base: URL, visited: Set<string>, depth: number, ctx: Context): Promise<string[]> {
  const out: string[] = [];
  for (const line of lines) {
    if (out.length >= MAX_EXPANDED_LINES) break;
    const t = line.trim();
    if (includePath(t) === null) {
      out.push(line);
      continue;
    }
    ctx.includeDirectives++;
    pushAll(out, await resolveInclude(t, base, visited, depth, ctx));
  }
  return out;
}

async function resolveInclude(line: string, base: URL, visited: Set<string>, depth: number, ctx: Context): Promise<string[]> {
  if (depth >= MAX_INCLUDE_DEPTH) return [];
  const rawPath = includePath(line);
  if (rawPath === null) return [];
  const sub = resolveSublistURL(rawPath, base);
  if (!sub || !isSameOrigin(sub, base)) return [];
  const key = visitKey(sub);
  if (visited.has(key)) return [];

  let text: string;
  try {
    text = await ctx.store.get(sub.href);
  } catch (error) {
    ctx.warnings.push(`include failed: ${sub.href}: ${(error as Error).message}`);
    return [];
  }
  const nextVisited = new Set(visited).add(key);
  const lines = evaluateConditionals(splitLines(text));
  return expandIncludes(lines, new URL('.', sub), nextVisited, depth + 1, ctx);
}

// FilterPreprocessor.preprocess: conditionals on the parent, then recursive includes.
// Output keeps every non-blank line verbatim; blank lines are dropped because
// ConverterTool stops reading stdin at the first empty line.
export async function preprocess(text: string, listURL: URL, store: ListStore) {
  const ctx: Context = { store, warnings: [], includeDirectives: 0 };
  const lines = evaluateConditionals(splitLines(text));
  const expanded = await expandIncludes(lines, new URL('.', listURL), new Set([visitKey(listURL)]), 0, ctx);
  const body = expanded.filter((l) => l.trim() !== '');
  return { text: body.join('\n') + '\n', lines: body.length, includes: ctx.includeDirectives, warnings: ctx.warnings };
}

export const sha256 = (data: string | Buffer) => createHash('sha256').update(data).digest('hex');

interface ManifestEntry {
  file: string;
  sha256: string;
  bytes: number;
  fetchedAt: string;
}

interface Manifest {
  createdAt: string;
  entries: Record<string, ManifestEntry>;
}

// A store is either the fresh cache (.cache/lists, always re-downloaded) or a named snapshot
// (.cache/lists/snapshots/NAME, downloads pinned by sha256 and reused on later runs).
export class ListStore {
  readonly dir: string;
  readonly name: string;
  readonly warnings: string[] = [];
  private readonly reuse: boolean;
  private readonly manifest: Manifest;
  private readonly memo = new Map<string, Promise<string>>();

  private constructor(name: string, dir: string, reuse: boolean, manifest: Manifest) {
    this.name = name;
    this.dir = dir;
    this.reuse = reuse;
    this.manifest = manifest;
  }

  static async open(snapshot: string | null, refresh = false): Promise<ListStore> {
    const dir = snapshot ? path.join(CACHE_DIR, 'lists', 'snapshots', snapshot) : path.join(CACHE_DIR, 'lists');
    await mkdir(path.join(dir, 'prep'), { recursive: true });
    const manifest = await readJson<Manifest>(path.join(dir, 'manifest.json')) ?? {
      createdAt: new Date().toISOString(),
      entries: {},
    };
    return new ListStore(snapshot ?? 'fresh', dir, snapshot !== null && !refresh, manifest);
  }

  get(url: string): Promise<string> {
    let text = this.memo.get(url);
    if (!text) {
      text = this.load(url);
      this.memo.set(url, text);
    }
    return text;
  }

  private async load(url: string): Promise<string> {
    const pinned = this.manifest.entries[url];
    if (pinned && this.reuse) {
      const body = await readFile(path.join(this.dir, pinned.file), 'utf8');
      if (sha256(body) !== pinned.sha256) throw new Error(`${this.name}: ${url} no longer matches its pinned sha256`);
      return body;
    }
    const body = await download(url);
    const file = `${sha256(url).slice(0, 16)}.txt`;
    await writeFile(path.join(this.dir, file), body);
    this.manifest.entries[url] = {
      file,
      sha256: sha256(body),
      bytes: Buffer.byteLength(body),
      fetchedAt: new Date().toISOString(),
    };
    return body;
  }

  async save(): Promise<void> {
    await writeFile(path.join(this.dir, 'manifest.json'), JSON.stringify(this.manifest, null, 2) + '\n');
  }

  manifestEntry(url: string): ManifestEntry | undefined {
    return this.manifest.entries[url];
  }
}

async function download(url: string): Promise<string> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await fetch(url, {
        headers: { 'user-agent': 'wblock-engine-bench/1.0' },
        signal: AbortSignal.timeout(120_000),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.text();
    } catch (error) {
      lastError = error;
      await new Promise((r) => setTimeout(r, 1000 * attempt));
    }
  }
  throw new Error(`download failed: ${url}: ${(lastError as Error).message}`);
}

async function readJson<T>(file: string): Promise<T | undefined> {
  try {
    return JSON.parse(await readFile(file, 'utf8')) as T;
  } catch {
    return undefined;
  }
}

export interface PreparedList {
  url: string;
  file: string;
  sha256: string;
  bytes: number;
  lines: number;
  includeDirectives: number;
  rawSha256: string;
}

export interface PreparedSet {
  name: string;
  store: string;
  lists: PreparedList[];
  combinedFile: string;
  combinedSha256: string;
  combinedBytes: number;
  combinedLines: number;
  warnings: string[];
}

export async function prepareList(url: string, store: ListStore): Promise<PreparedList> {
  const raw = await store.get(url);
  const out = await preprocess(raw, new URL(url), store);
  const file = path.join(store.dir, 'prep', `${sha256(url).slice(0, 16)}.txt`);
  await writeFile(file, out.text);
  return {
    url,
    file,
    sha256: sha256(out.text),
    bytes: Buffer.byteLength(out.text),
    lines: out.lines,
    includeDirectives: out.includes,
    rawSha256: store.manifestEntry(url)?.sha256 ?? sha256(raw),
  };
}

// Preprocesses every list in a set and concatenates them in set order.
export async function prepareSet(name: string, store: ListStore): Promise<PreparedSet> {
  const set = LIST_SETS[name];
  if (!set) throw new Error(`unknown list set: ${name}`);
  const lists = await Promise.all(set.urls.map((url) => prepareList(url, store)));
  const parts: string[] = [];
  for (const list of lists) parts.push(await readFile(list.file, 'utf8'));
  const combined = parts.join('');
  const combinedFile = path.join(store.dir, 'prep', `set-${name}.txt`);
  await writeFile(combinedFile, combined);
  await store.save();
  return {
    name,
    store: store.name,
    lists,
    combinedFile,
    combinedSha256: sha256(combined),
    combinedBytes: Buffer.byteLength(combined),
    combinedLines: combined.split('\n').length - 1,
    warnings: store.warnings,
  };
}

function parseArgs(argv: string[]) {
  const sets: string[] = [];
  let snapshot: string | null = null;
  let refresh = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--set') sets.push(argv[++i]);
    else if (argv[i] === '--snapshot') snapshot = argv[++i];
    else if (argv[i] === '--refresh') refresh = true;
    else throw new Error(`unknown argument: ${argv[i]}`);
  }
  return { sets: sets.length ? sets : Object.keys(LIST_SETS), snapshot, refresh };
}

if (import.meta.main) {
  const { sets, snapshot, refresh } = parseArgs(process.argv.slice(2));
  const store = await ListStore.open(snapshot, refresh);
  for (const name of sets) {
    const prepared = await prepareSet(name, store);
    console.log(`${name} [${prepared.store}]: ${prepared.lists.length} lists, ${prepared.combinedLines} lines, ${prepared.combinedBytes} bytes, sha256 ${prepared.combinedSha256.slice(0, 12)}`);
    for (const l of prepared.lists) console.log(`  ${l.lines.toString().padStart(8)} lines  ${l.includeDirectives} includes  ${l.url}`);
  }
  for (const w of store.warnings) console.warn(`warning: ${w}`);
}
