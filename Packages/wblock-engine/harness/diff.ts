// Judges Safari content-blocker JSON against uBO on a request corpus built from
// uBO filter lists.
//
//   node diff.ts --lists a.txt b.txt --json engine.json [--json2 other.json]
//                [--seed 1] [--max-synthetic 400000] [--out out]
//
// Each engine is run through the corpus with the WebKit simulator and compared
// with uBO's verdict. OVER-BLOCK: the engine blocks, uBO does not. UNDER-BLOCK:
// uBO blocks, the engine does not. Reports go to <out>/<engine>.report.{json,md}.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildCorpus, type CorpusRequest, toSimRequest } from './corpus/index.ts';
import { createOracle, type Verdict } from './oracle/index.ts';
import { stripConditionals } from './oracle/preprocess.ts';
import { compileRuleList, simulate } from './sim/webkit.ts';

const here = dirname(fileURLToPath(import.meta.url));

interface Args {
    lists: string[];
    json: string[];
    seed: number;
    maxSynthetic: number;
    out: string;
}

function parseArgs(argv: string[]): Args {
    const args: Args = { lists: [], json: [], seed: 1, maxSynthetic: 400000, out: join(here, 'out') };
    let list: string[] | undefined;
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (!a.startsWith('--')) {
            if (list === undefined) { throw new Error(`unexpected argument ${a}`); }
            list.push(a);
            continue;
        }
        list = undefined;
        switch (a) {
            case '--lists': list = args.lists; break;
            case '--json':
            case '--json2': args.json.push(argv[++i]); break;
            case '--seed': args.seed = Number(argv[++i]); break;
            case '--max-synthetic': args.maxSynthetic = Number(argv[++i]); break;
            case '--out': args.out = argv[++i]; break;
            default: throw new Error(`unknown option ${a}`);
        }
    }
    if (args.lists.length === 0 || args.json.length === 0) {
        throw new Error('usage: node diff.ts --lists a.txt [b.txt ...] --json engine.json [--json2 other.json]');
    }
    return args;
}

interface Example {
    id: string;
    url: string;
    docUrl: string;
    topUrl: string;
    uboType: string;
    origin: string;
    ruleLine?: string;
    engineRule?: string;
    uboFilter?: string;
}

interface Group {
    cause: string;
    count: number;
    examples: Example[];
}

interface Report {
    engine: string;
    lists: string[];
    corpus: { total: number, synthetic: number, real: number };
    agree: number;
    agreement: number;
    // Recall over uBO blocks, precision over engine blocks.
    uboBlocked: number;
    engineBlocked: number;
    bothBlocked: number;
    overBlock: { count: number, groups: Group[] };
    underBlock: { count: number, groups: Group[] };
    byOrigin: Record<string, { total: number, agree: number, overBlock: number, underBlock: number }>;
    byContext: Record<string, { total: number, agree: number, overBlock: number, underBlock: number }>;
}

const MAX_EXAMPLES = 5;
const TOP_GROUPS = 25;

function addTo(groups: Map<string, Group>, cause: string, example: Example) {
    const group = groups.get(cause) ?? { cause, count: 0, examples: [] };
    group.count++;
    if (group.examples.length < MAX_EXAMPLES) { group.examples.push(example); }
    groups.set(cause, group);
}

function ruleKey(rule: any): string {
    return `${JSON.stringify(rule.trigger)} -> ${rule.action.type}`;
}

function judge(engineName: string, rules: unknown[], lists: string[], corpus: CorpusRequest[], verdicts: { verdict: Verdict, filter?: string }[]): Report {
    const compiled = compileRuleList(rules, { maxRules: Infinity });
    const overGroups = new Map<string, Group>();
    const underGroups = new Map<string, Group>();
    const byOrigin: Report['byOrigin'] = {};
    const byContext: Report['byContext'] = {};
    let agree = 0;
    let over = 0;
    let under = 0;
    let uboBlocked = 0;
    let engineBlocked = 0;
    let bothBlocked = 0;
    corpus.forEach((req, i) => {
        const sim = simulate(compiled, toSimRequest(req));
        const ubo = verdicts[i];
        const uboBlocks = ubo.verdict === 'block';
        const bucket = (table: Report['byOrigin'], key: string) => {
            table[key] ??= { total: 0, agree: 0, overBlock: 0, underBlock: 0 };
            return table[key];
        };
        const o = bucket(byOrigin, req.origin);
        const c = bucket(byContext, req.inChildFrame ? 'child-frame' : 'top-frame');
        o.total++;
        c.total++;
        const engineRule = sim.blockedBy === undefined ? undefined : ruleKey(rules[sim.blockedBy]);
        const example: Example = {
            id: req.id,
            url: req.url,
            docUrl: req.docUrl,
            topUrl: req.topUrl,
            uboType: req.uboType,
            origin: req.origin,
            ruleLine: req.ruleLine,
            engineRule,
            uboFilter: ubo.filter,
        };
        if (uboBlocks) { uboBlocked++; }
        if (sim.blocked) { engineBlocked++; }
        if (sim.blocked && uboBlocks) { bothBlocked++; }
        if (sim.blocked === uboBlocks) {
            agree++;
            o.agree++;
            c.agree++;
        } else if (sim.blocked) {
            over++;
            o.overBlock++;
            c.overBlock++;
            addTo(overGroups, `${engineRule ?? '?'}  [uBO: ${ubo.verdict}${ubo.filter ? ` ${ubo.filter}` : ''}]`, example);
        } else {
            under++;
            o.underBlock++;
            c.underBlock++;
            addTo(underGroups, `${ubo.filter ?? '?'}  [engine: no block]`, example);
        }
    });
    const top = (groups: Map<string, Group>) => [...groups.values()].sort((a, b) => b.count - a.count).slice(0, TOP_GROUPS);
    return {
        engine: engineName,
        lists: lists.map((l) => basename(l)),
        corpus: {
            total: corpus.length,
            synthetic: corpus.filter((r) => r.origin === 'synthetic').length,
            real: corpus.filter((r) => r.origin === 'real').length,
        },
        agree,
        agreement: corpus.length === 0 ? 1 : agree / corpus.length,
        uboBlocked,
        engineBlocked,
        bothBlocked,
        overBlock: { count: over, groups: top(overGroups) },
        underBlock: { count: under, groups: top(underGroups) },
        byOrigin,
        byContext,
    };
}

function markdown(r: Report): string {
    const pct = (n: number, d: number) => (d === 0 ? '0.0' : ((100 * n) / d).toFixed(2));
    const lines: string[] = [];
    lines.push(`# Engine vs uBO: ${r.engine}`, '');
    lines.push(`Lists: ${r.lists.join(', ')}`, '');
    lines.push(`Corpus: ${r.corpus.total} requests (${r.corpus.synthetic} synthetic, ${r.corpus.real} real-world)`, '');
    lines.push(`Agreement: ${r.agree} / ${r.corpus.total} (${pct(r.agree, r.corpus.total)}%)`, '');
    lines.push(`uBO blocks ${r.uboBlocked}, engine blocks ${r.engineBlocked}, both ${r.bothBlocked}`);
    lines.push(`Recall (engine blocks what uBO blocks): ${pct(r.bothBlocked, r.uboBlocked)}%. Precision (uBO blocks what engine blocks): ${pct(r.bothBlocked, r.engineBlocked)}%`, '');
    lines.push(`OVER-BLOCK (engine blocks, uBO does not): ${r.overBlock.count} (${pct(r.overBlock.count, r.corpus.total)}%)`);
    lines.push(`UNDER-BLOCK (uBO blocks, engine does not): ${r.underBlock.count} (${pct(r.underBlock.count, r.corpus.total)}%)`, '');
    lines.push('| slice | total | agree | over-block | under-block |', '|---|---|---|---|---|');
    for (const [name, t] of [...Object.entries(r.byOrigin), ...Object.entries(r.byContext)]) {
        lines.push(`| ${name} | ${t.total} | ${pct(t.agree, t.total)}% | ${t.overBlock} | ${t.underBlock} |`);
    }
    const section = (title: string, groups: Group[]) => {
        lines.push('', `## ${title}`, '');
        for (const g of groups) {
            lines.push(`- ${g.count}x \`${g.cause.replace(/`/g, "'")}\``);
            for (const e of g.examples) {
                lines.push(`    - ${e.id} ${e.uboType} ${e.url} (doc ${e.docUrl}${e.topUrl !== e.docUrl ? `, top ${e.topUrl}` : ''})${e.ruleLine ? ` from \`${e.ruleLine.replace(/`/g, "'")}\`` : ''}`);
            }
        }
    };
    section('Over-block causes', r.overBlock.groups);
    section('Under-block causes', r.underBlock.groups);
    return `${lines.join('\n')}\n`;
}

async function main(): Promise<void> {
    const args = parseArgs(process.argv.slice(2));
    const lists = args.lists.map((path) => stripConditionals(readFileSync(path, 'utf8')));
    const corpus = buildCorpus(lists, { seed: args.seed, maxSynthetic: args.maxSynthetic });
    console.log(`corpus: ${corpus.length} requests`);
    const oracle = await createOracle(lists);
    const verdicts = corpus.map((req) => oracle.explain({ url: req.url, type: req.uboType, docUrl: req.docUrl }));
    mkdirSync(args.out, { recursive: true });
    for (const path of args.json) {
        const rules = JSON.parse(readFileSync(path, 'utf8')) as unknown[];
        const report = judge(basename(path), rules, args.lists, corpus, verdicts);
        const stem = join(args.out, basename(path).replace(/\.json$/, ''));
        writeFileSync(`${stem}.report.json`, `${JSON.stringify(report, null, 2)}\n`);
        writeFileSync(`${stem}.report.md`, markdown(report));
        console.log(`${report.engine}: agreement ${(100 * report.agreement).toFixed(2)}%, recall ${(100 * report.bothBlocked / Math.max(1, report.uboBlocked)).toFixed(2)}%, precision ${(100 * report.bothBlocked / Math.max(1, report.engineBlocked)).toFixed(2)}%, over-block ${report.overBlock.count}, under-block ${report.underBlock.count} -> ${stem}.report.md`);
    }
}

await main();
