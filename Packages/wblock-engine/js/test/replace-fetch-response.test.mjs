import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { setImmediate as tick } from 'node:timers/promises';
import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';

const dir=mkdtempSync(join(tmpdir(),'wbe-scriptlets-'));
let source, requestSource;
try {
    execFileSync(process.execPath,[new URL('../build-scriptlets.mjs',import.meta.url).pathname,dir]);
    source=readFileSync(join(dir,'trusted-replace-fetch-response.js'),'utf8');
    requestSource=readFileSync(join(dir,'trusted-youtube-player-request.js'),'utf8');
} finally {rmSync(dir,{recursive:true,force:true})}
const encode=text=>new TextEncoder().encode(text);
function setup(response,call=['"adSlots"','"no_ads"','get_watch?']) {
    const dom=new JSDOM('',{url:'https://example.com/',runScripts:'outside-only'});
    const w=dom.window;
    Object.assign(w,{Response,Request,TransformStream,ReadableStream,TextEncoder,TextDecoder,fetch:()=>Promise.resolve(response),__wbeScriptletCalls:{'trusted-replace-fetch-response':[call]}});
    w.eval(source);
    return {dom,fetch:()=>w.fetch('https://example.com/get_watch?v=video')};
}
async function filtered(response,call) {
    const {dom,fetch}=setup(response,call);
    try {return await fetch()} finally {dom.window.close()}
}
test('generated player adapter consumes its matched call',()=>{
    const dom=new JSDOM('',{url:'https://www.youtube.com/watch?v=video',runScripts:'outside-only'});
    const w=dom.window;
    try {
        Object.assign(w,{Request,TextEncoder:class extends TextEncoder {},__wbeScriptletCalls:{'trusted-youtube-player-request':[[]]}});
        w.eval(requestSource);
        const request={context:{client:{clientName:'WEB'}},playbackContext:{contentPlaybackContext:{}}};
        assert.equal(JSON.parse(w.JSON.stringify(request)).params,'eAFgAQ');
        assert.equal(w.__wbeScriptletCalls['trusted-youtube-player-request'],undefined);
    } finally {w.close()}
});
test('headers and initial bytes arrive before the server closes the stream',{timeout:3000},async()=>{
    let controller;
    const before=new Response(new ReadableStream({start(c){controller=c;c.enqueue(encode('FIRST '.repeat(20)))}}));
    const {dom,fetch}=setup(before);
    try {
        let resolved=false;
        const pending=fetch().then(r=>{resolved=true;return r});
        await tick();
        assert.equal(resolved,true,'fetch must not wait for EOF');
        const response=await pending;
        const reader=response.body.getReader();
        let received=false;
        const chunk=reader.read().then(r=>{received=true;return r});
        await tick();
        assert.equal(received,true,'the first chunk must not wait for EOF');
        assert.match(new TextDecoder().decode((await chunk).value),/^FIRST/);
        await reader.cancel();
    } finally {try{controller.close()}catch{}dom.window.close()}
});
test('complete frames and nonmatching suffixes are not held for another chunk',async()=>{
    for(const [chunk,want] of [['{"videoId":"video"}\n','{"videoId":"video"}\n'],['prefix "adS','prefix ']]) {
        const before=new Response(new ReadableStream({start(c){c.enqueue(encode(chunk))}}));
        const after=await filtered(before);
        const reader=after.body.getReader();
        try {assert.equal(new TextDecoder().decode((await reader.read()).value),want)}
        finally {await reader.cancel()}
    }
});
test('literal matches spanning any UTF-8 chunk boundary retain first-match semantics',async()=>{
    const text='😀 before "adSlots" and "adSlots" after é';
    const bytes=encode(text);
    for(let i=1;i<bytes.length;i++) {
        const response=new Response(new ReadableStream({start(c){c.enqueue(bytes.slice(0,i));c.enqueue(bytes.slice(i));c.close()}}));
        assert.equal(await (await filtered(response)).text(),text.replace('"adSlots"','"no_ads"'),'byte split '+i);
    }
});
test('overlapping and Unicode prefixes work at every byte split',async()=>{
    for(const pattern of ['abab','aaab','😀x','x😀','a']) {
        const text=pattern.slice(0,-1)+' outside '+pattern+' twice '+pattern;
        const bytes=encode(text);
        // The leading partial prefix may contain an unpaired surrogate.
        const decoded=new TextDecoder().decode(bytes);
        for(let i=1;i<bytes.length;i++) {
            const response=new Response(new ReadableStream({start(c){c.enqueue(bytes.slice(0,i));c.enqueue(bytes.slice(i));c.close()}}));
            const after=await filtered(response,[pattern,'replacement','get_watch?']);
            assert.equal(await after.text(),decoded.replace(pattern,'replacement'));
        }
    }
});
test('one-byte chunks and incomplete final matches are decoded correctly',async()=>{
    for(const text of ['é😀"adSlots" tail','nothing matches','partial "adS','']) {
        const response=new Response(new ReadableStream({start(c){for(const byte of encode(text))c.enqueue(Uint8Array.of(byte));c.close()}}));
        assert.equal(await (await filtered(response)).text(),text.replace('"adSlots"','"no_ads"'));
    }
});
test('regex and replacement expansions keep whole-body behavior',async()=>{
    for(const [pattern,replacement,text,want] of [
        ['/ad/g','x','ad and ad','x and x'],
        ['ad','$&!','ad and ad','ad! and ad'],
        ['/.*/','empty','anything','empty'],
    ])assert.equal(await (await filtered(new Response(text),[pattern,replacement,'get_watch?'])).text(),want);
});
test('includes predicates are decided on the complete body',async()=>{
    for(const [text,want] of [['ad without marker','ad without marker'],['ad with ALLOW','x with ALLOW']]) {
        assert.equal(await (await filtered(new Response(text),['ad','x','get_watch?','includes','ALLOW'])).text(),want);
    }
});
test('unmatched binary response bytes are preserved',async()=>{
    const bytes=Uint8Array.of(0xFF,0xC2,0x80,0x00,0xEF,0xBB,0xBF,0xFE);
    const after=await filtered(new Response(bytes));
    assert.deepEqual(new Uint8Array(await after.arrayBuffer()),bytes);
});
test('decoded-text edge cases retain the buffered replacement behavior',async()=>{
    const bom=String.fromCodePoint(0xFEFF);
    for(const [bytes,pattern,replacement,want] of [
        [Uint8Array.of(0xC2,0x61,0x80),'a','','��'],
        [Uint8Array.of(0xFF),'�','x','x'],
        [encode(bom+'before '+bom+'after'),bom,'x','before xafter'],
        [encode(bom+'ad'),'ad',bom+'x','x'],
    ])assert.equal(await (await filtered(new Response(bytes),[pattern,replacement,'get_watch?'])).text(),want);
});
test('unmatched requests pass through without consuming their response',async()=>{
    const before=new Response('"adSlots"');
    assert.equal(await filtered(before,['"adSlots"','"no_ads"','/different-path/']),before);
    assert.equal(before.bodyUsed,false);
});
test('response metadata and headers survive streaming',async()=>{
    const before=new Response('"adSlots"',{status:201,statusText:'Created',headers:{'X-Test':'keep','Content-Type':'application/json'}});
    Object.defineProperties(before,{url:{value:'https://example.com/original'},redirected:{value:true},type:{value:'cors'}});
    const after=await filtered(before);
    for(const key of ['status','statusText','ok','url','redirected','type'])assert.equal(after[key],before[key],key);
    assert.equal(after.headers.get('X-Test'),'keep');
    assert.equal(after.headers.get('Content-Type'),'application/json');
    assert.equal(await after.text(),'"no_ads"');
});
test('empty-body responses pass through',async()=>{
    const before=new Response(null,{status:204});assert.equal(await filtered(before),before);
});
test('cancellation propagates to the upstream stream',async()=>{
    let reason;
    const before=new Response(new ReadableStream({cancel(r){reason=r}}));
    const after=await filtered(before);await after.body.cancel('stop');await tick();
    assert.equal(reason,'stop');
});
test('stream errors propagate to body readers',async()=>{
    const before=new Response(new ReadableStream({start(c){c.error(new Error('disconnected'))}}));
    const after=await filtered(before);await assert.rejects(after.text(),/disconnected/);
});
