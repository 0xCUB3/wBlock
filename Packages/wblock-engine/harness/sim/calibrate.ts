// Runs the calibration cases in real WKWebView (via sim/calibrate.swift) and
// compares what reached the local server with simulate(). Writes
// sim/calibrate-expected.json with --write, which the test suite reads later.
//
//   node sim/calibrate.ts            compare live WebKit with the simulator
//   node sim/calibrate.ts --write    also record the observations

import { execFile } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { CALIBRATION_CASES, type CalibrationCase, type CalResource, HOSTS, PORT } from './calibration-cases.ts';
import { compileRuleList, simulate, type SimRequest, WebKitRuleError } from './webkit.ts';

const here = dirname(fileURLToPath(import.meta.url));
const buildDir = join(here, '.build');
const probePath = join(buildDir, 'calibrate-probe');
const expectedPath = join(here, 'calibrate-expected.json');
const run = promisify(execFile);

// A WebKit observation for one case, as stored in calibrate-expected.json.
export interface Observation {
    id: string;
    rejected?: string;
    pageReached: boolean;
    reached: Record<string, boolean>;
    hidden: string[];
}

const hits = new Set<string>();

function pageUrl(caseId: string): string {
    return `http://${HOSTS.top}:${PORT}/c/${caseId}/index.html?r=page`;
}

function resourceUrl(caseId: string, res: CalResource): string {
    return `http://${HOSTS[res.host]}:${PORT}/c/${caseId}/${res.path}?r=${res.id}`;
}

function elementFor(caseId: string, res: CalResource, urlOf: (r: CalResource) => string): string {
    const u = JSON.stringify(urlOf(res));
    switch (res.type) {
        case 'image': return `<img src=${u}>`;
        case 'script': return `<script src=${u}></script>`;
        case 'style-sheet': return `<link rel="stylesheet" href=${u}>`;
        case 'font': return `<style>@font-face{font-family:"f${res.id}";src:url(${u})}</style><p style="font-family:'f${res.id}'">text</p>`;
        case 'media': return `<video src=${u} preload="auto"></video>`;
        case 'child-document': return `<iframe src=${u}></iframe>`;
        case 'ping': return `<script>navigator.sendBeacon(${u},"x")</script>`;
        case 'other': return `<script>navigator.sendBeacon(${u},"x")</script>`;
        case 'fetch':
            return res.via === 'xhr'
                ? `<script>var x=new XMLHttpRequest();x.open("GET",${u});x.send()</script>`
                : `<script>fetch(${u}).catch(function(){})</script>`;
        default: throw new Error(`no element for ${res.type} in ${caseId}`);
    }
}

function documentHtml(c: CalibrationCase, frameId: string | undefined): string {
    const children = c.resources.filter((r) => r.frame === frameId);
    const urlOf = (r: CalResource) => resourceUrl(c.id, r);
    const hide = frameId === undefined ? (c.hide ?? []).map((h) => `<div class="cs-${h}" data-cs="${h}">${h}</div>`) : [];
    return `<!doctype html><html><head><meta charset="utf-8"></head><body>${hide.join('')}${children.map((r) => elementFor(c.id, r, urlOf)).join('')}</body></html>`;
}

const server = createServer((req, res) => {
    const url = new URL(req.url ?? '/', `http://127.0.0.1:${PORT}`);
    const match = /^\/c\/([^/]+)\/(.*)$/.exec(url.pathname);
    const id = url.searchParams.get('r');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Cache-Control', 'no-store');
    if (match === null || id === null) {
        res.writeHead(404).end();
        return;
    }
    const [, caseId] = match;
    hits.add(`${caseId}|${id}`);
    const c = CALIBRATION_CASES.find((x) => x.id === caseId);
    const resource = c?.resources.find((r) => r.id === id);
    if (c !== undefined && id === 'page') {
        res.writeHead(200, { 'content-type': 'text/html' }).end(documentHtml(c, undefined));
    } else if (c !== undefined && resource?.type === 'child-document') {
        res.writeHead(200, { 'content-type': 'text/html' }).end(documentHtml(c, id));
    } else {
        res.writeHead(200, { 'content-type': 'application/octet-stream' }).end('x');
    }
});

// Request as WebKit's loader would describe it to the content-blocker.
function simRequest(c: CalibrationCase, res: CalResource): SimRequest {
    const top = pageUrl(c.id);
    const frame = res.frame === undefined ? top : resourceUrl(c.id, c.resources.find((r) => r.id === res.frame)!);
    return {
        url: resourceUrl(c.id, res),
        resourceType: res.type,
        loadContext: res.frame === undefined ? 'top-frame' : 'child-frame',
        frameUrl: frame,
        topUrl: top,
    };
}

async function probe(rulesPath: string, url: string): Promise<string> {
    const { stdout } = await run(probePath, [rulesPath, url, '2.5'], { timeout: 60000 }).catch((e) => ({ stdout: String(e.stdout ?? '') + '\n' + String(e.stderr ?? '') }));
    const line = stdout.split('\n').reverse().find((l) => l.startsWith('RESULT '));
    if (line === undefined) { throw new Error(`probe produced no result for ${url}: ${stdout}`); }
    return line.slice('RESULT '.length);
}

async function observe(c: CalibrationCase): Promise<Observation> {
    const rulesPath = join(buildDir, `rules-${c.id}.json`);
    writeFileSync(rulesPath, JSON.stringify(c.rules));
    const result = JSON.parse(await probe(rulesPath, pageUrl(c.id)));
    if (typeof result.rejected === 'string') {
        return { id: c.id, rejected: result.rejected, pageReached: false, reached: {}, hidden: [] };
    }
    const pageReached = !(result.navigation === 'failed' || result.error === 'timeout');
    const reached: Record<string, boolean> = {};
    if (pageReached) {
        for (const r of c.resources) { reached[r.id] = hits.has(`${c.id}|${r.id}`); }
    }
    return { id: c.id, pageReached, reached, hidden: Array.isArray(result.hidden) ? result.hidden.map((h: string) => String(h)) : [] };
}

// Compares one observation with simulate(). Returns the disagreements.
export function compare(c: CalibrationCase, obs: Observation): string[] {
    const problems: string[] = [];
    if (obs.rejected !== undefined) {
        try {
            compileRuleList(c.rules);
            problems.push(`${c.id}: WebKit rejected (${obs.rejected}) but simulator accepts`);
        } catch (error) {
            if (!(error instanceof WebKitRuleError)) { throw error; }
        }
        return problems;
    }
    const list = compileRuleList(c.rules);
    const pageReq = { url: pageUrl(c.id), resourceType: 'top-document' as const, loadContext: 'top-frame' as const, frameUrl: pageUrl(c.id), topUrl: pageUrl(c.id) };
    const pageSim = simulate(list, pageReq);
    if (pageSim.blocked === obs.pageReached) {
        problems.push(`${c.id}: page ${obs.pageReached ? 'loaded in WebKit' : 'blocked in WebKit'}, simulator says blocked=${pageSim.blocked}`);
    }
    if (!obs.pageReached) { return problems; }
    for (const r of c.resources) {
        const parentOk = r.frame === undefined || obs.reached[r.frame];
        if (!parentOk) { continue; }
        const sim = simulate(list, simRequest(c, r));
        if (sim.blocked === obs.reached[r.id]) {
            problems.push(`${c.id}/${r.id} (${r.type} ${r.path}): WebKit ${obs.reached[r.id] ? 'loaded' : 'blocked'}, simulator blocked=${sim.blocked}`);
        }
    }
    const hiddenSim = pageSim.hiddenSelectors.map((s) => s.replace(/^\.cs-/, '')).sort();
    const hiddenWk = [...obs.hidden].sort();
    if (JSON.stringify(hiddenSim) !== JSON.stringify(hiddenWk)) {
        problems.push(`${c.id}: hidden in WebKit ${JSON.stringify(hiddenWk)}, simulator ${JSON.stringify(hiddenSim)}`);
    }
    return problems;
}

async function main(): Promise<void> {
    const write = process.argv.includes('--write');
    mkdirSync(buildDir, { recursive: true });
    await run('swiftc', ['-O', join(here, 'calibrate.swift'), '-o', probePath]);
    await new Promise<void>((resolve) => server.listen(PORT, '127.0.0.1', resolve));
    const observations: Observation[] = [];
    const problems: string[] = [];
    try {
        for (const c of CALIBRATION_CASES) {
            const obs = await observe(c);
            observations.push(obs);
            problems.push(...compare(c, obs));
        }
    } finally {
        server.close();
    }
    if (write) {
        writeFileSync(expectedPath, `${JSON.stringify({ hosts: HOSTS, port: PORT, cases: observations }, null, 2)}\n`);
    }
    console.log(`${CALIBRATION_CASES.length} cases, ${CALIBRATION_CASES.reduce((n, c) => n + c.resources.length, 0)} resources, ${problems.length} disagreements`);
    for (const p of problems) { console.log(`  ${p}`); }
    process.exitCode = problems.length === 0 ? 0 : 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
    await main();
}
