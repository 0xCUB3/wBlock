// uBO's static network filtering engine (pinned commit, built by setup.sh) as
// the reference verdict for a request.

import { pathToFileURL } from 'node:url';

export type UboType =
    | 'main_frame' | 'sub_frame' | 'stylesheet' | 'script' | 'image' | 'font'
    | 'media' | 'xmlhttprequest' | 'websocket' | 'ping' | 'other' | 'popup';

export interface OracleRequest {
    url: string;
    type: UboType;
    // Document the request is made from. For main_frame, the URL itself; for
    // sub_frame, the parent document; for subresources, the frame's document.
    docUrl: string;
}

export type Verdict = 'block' | 'allow' | 'none';

export interface Oracle {
    match(req: OracleRequest): Verdict;
    // Verdict plus the uBO filter line that decided it, when there is one.
    explain(req: OracleRequest): { verdict: Verdict, filter?: string };
}

interface UboEngine {
    useLists(lists: { name: string, raw: string }[]): Promise<void>;
    matchRequest(details: { url: string, type: string, originURL: string }): number;
    toLogData(): { raw?: string } | undefined;
}

interface UboCore {
    StaticNetFilteringEngine: {
        create(): Promise<UboEngine>;
        release(): Promise<void>;
    };
    enableWASM(): Promise<boolean>;
}

const corePath = new URL('../.cache/ublock-core/index.js', import.meta.url);
let core: UboCore | undefined;

async function loadCore(): Promise<UboCore> {
    if (core === undefined) {
        try {
            core = await import(pathToFileURL(corePath.pathname).href) as UboCore;
        } catch (error) {
            throw new Error(`uBO core missing; run harness/setup.sh (${String(error)})`);
        }
    }
    return core;
}

// uBO matchRequest() return codes: 0 no match, 1 blocked, 2 exception (allowed).
const VERDICTS: Verdict[] = ['none', 'block', 'allow'];

// Creates an engine over the given lists. Lists must already be preprocessed
// (no `!#if` / `!#include`). The uBO engine is a process-wide singleton, so
// creating a new oracle releases the previous one.
export async function createOracle(listTexts: string[]): Promise<Oracle> {
    const { StaticNetFilteringEngine, enableWASM } = await loadCore();
    await StaticNetFilteringEngine.release();
    await enableWASM();
    const engine = await StaticNetFilteringEngine.create();
    await engine.useLists(listTexts.map((raw, i) => ({ name: `list-${i}`, raw })));
    const explain = ({ url, type, docUrl }: OracleRequest) => {
        const verdict = VERDICTS[engine.matchRequest({ url, type, originURL: docUrl })] ?? 'none';
        const filter = verdict === 'none' ? undefined : engine.toLogData()?.raw;
        return { verdict, filter };
    };
    return {
        match: (req: OracleRequest): Verdict => explain(req).verdict,
        explain,
    };
}
