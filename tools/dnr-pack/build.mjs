import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

function parseArgs(argv) {
  const out = new Map();
  for (const arg of argv.slice(2)) {
    if (!arg.startsWith('--')) continue;
    const eq = arg.indexOf('=');
    if (eq === -1) {
      out.set(arg.slice(2), 'true');
    } else {
      out.set(arg.slice(2, eq), arg.slice(eq + 1));
    }
  }
  return out;
}

function run(cmd, args, options = {}) {
  const res = spawnSync(cmd, args, { stdio: 'inherit', ...options });
  if (res.status !== 0) {
    throw new Error(`Command failed: ${cmd} ${args.join(' ')}`);
  }
}

async function readJson(filePath) {
  return JSON.parse(await fs.readFile(filePath, 'utf8'));
}

async function fetchText(url) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) {
    throw new Error(`Fetch failed: ${url} (${res.status})`);
  }
  return await res.text();
}

function stableEnvForPlatform(platform) {
  // Mirrors the environment used by uBO/uBOL ruleset generation.
  return [platform, 'native_css_has', 'mv3', 'ublock', 'ubol', 'user_stylesheet'];
}

async function main() {
  const args = parseArgs(process.argv);

  const repoRoot = process.cwd();
  const configPath = path.resolve(
    repoRoot,
    args.get('config') || 'tools/dnr-pack/recommended-lists.json',
  );
  const rulesetOutPath = path.resolve(
    repoRoot,
    args.get('ruleset') || 'wBlock Scripts (iOS)/Resources/rulesets/base.json',
  );
  const packOutPath = args.get('pack')
    ? path.resolve(repoRoot, args.get('pack'))
    : '';

  const ublockRef = args.get('ublockRef') || 'master';

  const cfg = await readJson(configPath);
  const platform = String(cfg.platform || 'safari');
  const variant = String(cfg.variant || 'recommended');
  const lists = Array.isArray(cfg.lists) ? cfg.lists : [];
  if (lists.length === 0) {
    throw new Error(`No lists found in ${configPath}`);
  }

  const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'wblock-dnr-pack-'));
  const uboDir = path.join(tmpRoot, 'ublock');
  const uboNodeDir = path.join(tmpRoot, 'ubo-node');

  run('git', ['clone', '--depth', '1', '--branch', ublockRef, 'https://github.com/gorhill/uBlock.git', uboDir]);
  run('bash', ['tools/make-nodejs.sh', uboNodeDir], { cwd: uboDir });

  const { dnrRulesetFromRawLists } = await import(
    pathToFileURL(path.join(uboNodeDir, 'js/static-dnr-filtering.js')).href,
  );

  const env = stableEnvForPlatform(platform);
  const secret = crypto.randomBytes(8).toString('hex');

  const rawLists = [];
  for (const entry of lists) {
    const name = String(entry?.name || '').trim();
    const url = String(entry?.url || '').trim();
    if (!name || !url) continue;
    // eslint-disable-next-line no-console
    console.log(`Fetching: ${name}`);
    rawLists.push({ name, text: await fetchText(url) });
  }
  if (rawLists.length === 0) {
    throw new Error('No valid list entries to compile');
  }

  const result = await dnrRulesetFromRawLists(rawLists, {
    env,
    secret,
    networkBad: new Set(),
  });

  const rules = (result?.network?.ruleset || []).filter((rule) => {
    return rule && typeof rule.id === 'number' && rule.id > 0;
  });

  if (rules.length > 30000) {
    throw new Error(`Too many DNR rules for Safari dynamic/session cap: ${rules.length}`);
  }

  await fs.mkdir(path.dirname(rulesetOutPath), { recursive: true });
  await fs.writeFile(rulesetOutPath, `${JSON.stringify(rules)}\n`, 'utf8');

  if (packOutPath) {
    const pack = {
      schema: 1,
      variant,
      platform,
      createdAt: new Date().toISOString(),
      rules,
    };
    await fs.mkdir(path.dirname(packOutPath), { recursive: true });
    await fs.writeFile(packOutPath, `${JSON.stringify(pack)}\n`, 'utf8');
  }

  const invalid = (result?.network?.ruleset || [])
    .filter((rule) => rule && typeof rule.id === 'number' && rule.id === 0 && rule._error)
    .flatMap((rule) => rule._error)
    .filter((x) => typeof x === 'string');

  // eslint-disable-next-line no-console
  console.log(`\nDone (${variant}/${platform})`);
  // eslint-disable-next-line no-console
  console.log(`Rules:   ${rules.length}`);
  // eslint-disable-next-line no-console
  console.log(`Invalid: ${invalid.length}`);
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err);
  process.exitCode = 1;
});
