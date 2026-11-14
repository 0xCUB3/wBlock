import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';
import { JSDOM } from 'jsdom';

const source = readFileSync(new URL('../youtube-player-request.js', import.meta.url), 'utf8');
const fixture = () => ({context:{client:{clientName:'WEB',clientScreen:'WATCH',configInfo:{appInstallData:'fixture',other:'keep'}}},videoId:'video',playbackContext:{contentPlaybackContext:{}}});
function setup({path='/watch?v=video',locked=false,status='OK',host='www.youtube.com'}={}) {
    const dom=new JSDOM('<div id="movie_player"></div>',{url:'https://'+host+path,runScripts:'outside-only'});
    const w=dom.window;
    w.Request=class extends Request {};
    w.TextEncoder=class extends TextEncoder {};
    w.document.getElementById('movie_player').getPlayerResponse=()=>({playabilityStatus:{status}});
    const stringify=w.JSON.stringify.bind(w.JSON);
    if(locked)for(const key of ['parse','stringify'])Object.defineProperty(w.JSON,key,{writable:false,configurable:false});
    w.eval(source+'\nyoutubePlayerRequest();');
    return {dom,w,stringify};
}
function run(name,fn,options) {
    test(name,async()=>{const state=setup(options);try{await fn(state)}finally{state.dom.window.close()}});
}
run('direct and nested player bodies use the same policy',({w})=>{
    for(const nested of [false,true]) {
        const input=fixture();
        if(nested){input.playerRequest={videoId:input.videoId,playbackContext:input.playbackContext};delete input.playbackContext}
        const out=JSON.parse(w.JSON.stringify(input));
        assert.equal(out.params,'eAFgAQ');
        const context=nested?out.playerRequest.playbackContext:out.playbackContext;
        if(nested)assert.equal(out.playerRequest.params,'eAFgAQ');
        assert.equal(context.params,'eAFgAQ');
        assert.match(context.contentPlaybackContext.lactMilliseconds,/^\d+$/);
        assert.deepEqual(out.context.client.configInfo,{other:'keep'});
        assert.equal(w.document.visibilityState,'visible');
    }
});
run('existing YAHI parameters are preserved',({w,stringify})=>{
    const input=fixture();input.params='YAHI-existing';
    assert.equal(w.JSON.stringify(input),stringify(input));
    assert.equal(input.context.client.configInfo.appInstallData,'fixture');
});
run('nested YAHI parameters are preserved',({w,stringify})=>{
    const input=fixture();
    input.playerRequest={params:'YAHI-existing',playbackContext:input.playbackContext};
    delete input.playbackContext;
    assert.equal(w.JSON.stringify(input),stringify(input));
    assert.equal(input.context.client.configInfo.appInstallData,'fixture');
});
run('unrelated values retain normal serialization',({w,stringify})=>{
    for(const input of [null,123,'text',{hello:'world'},{context:{client:{clientName:'WEB'}}}])assert.equal(w.JSON.stringify(input),stringify(input));
    const circular={};circular.self=circular;
    assert.throws(()=>w.JSON.stringify(circular),{name:'TypeError'});
    assert.equal(w.JSON.stringify({a:1,b:2},['a']),'{"a":1}');
});
for(const path of ['/shorts/video','/tv#/watch?v=video']) {
    run('excluded route stays untouched '+path,({w,stringify})=>{
        const input=fixture();assert.equal(w.JSON.stringify(input),stringify(input));
    },{path});
    run('route exclusions are checked after SPA navigation '+path,({dom,w,stringify})=>{
        dom.reconfigure({url:'https://www.youtube.com'+path});
        const input=fixture();assert.equal(w.JSON.stringify(input),stringify(input));
    });
}
for(const status of ['LOGIN_REQUIRED','CONTENT_CHECK_REQUIRED'])run('account gate is not bypassed '+status,({w,stringify})=>{
    const input=fixture();assert.equal(w.JSON.stringify(input),stringify(input));
},{status});
run('excluded SPA routes regain actual document visibility',({dom,w})=>{
    w.JSON.stringify(fixture());
    assert.equal(w.document.visibilityState,'visible');
    dom.reconfigure({url:'https://www.youtube.com/shorts/video'});
    assert.equal(w.document.visibilityState,w.document.hidden?'hidden':'visible');
});
run('Request preserves init, headers, and subclass semantics',async({w,stringify})=>{
    const body=stringify(fixture());const init=Object.freeze({method:'POST',body,headers:{'X-Test':'keep'},credentials:'include'});
    class Child extends w.Request {}
    const req=new Child(new w.URL('/youtubei/v1/player',w.location.href),init);
    assert.ok(req instanceof Child);assert.equal(req.method,'POST');assert.equal(req.headers.get('X-Test'),'keep');assert.equal(req.credentials,'include');
    assert.equal(init.body,body);assert.equal(JSON.parse(await req.text()).params,'eAFgAQ');
});
for(const url of ['https://www.youtube.com/unrelated','https://example.com/youtubei/v1/player'])run('Request does not edit unrelated target '+url,async({w,stringify})=>{
    const body=stringify(fixture());const req=new w.Request(url,{method:'POST',body});assert.equal(await req.text(),body);
});
run('encoded body is edited even when JSON methods are locked',({w,stringify})=>{
    const out=JSON.parse(new TextDecoder().decode(new w.TextEncoder().encode(stringify(fixture()))));
    assert.equal(out.context.client.clientScreen,'CHANNEL');
    assert.equal(out.context.client.configInfo.appInstallData,undefined);
    assert.equal(out.params,undefined);
    assert.equal(new w.TextEncoder().encode().length,0);
},{locked:true});
run('Request fallback works with locked JSON',async({w,stringify})=>{
    const req=new w.Request('https://www.youtube.com/youtubei/v1/player',{method:'POST',body:stringify(fixture())});
    assert.equal(JSON.parse(await req.text()).context.client.clientScreen,'CHANNEL');
},{locked:true});
run('installation is idempotent',({w})=>{
    const before=[w.JSON.stringify,w.TextEncoder.prototype.encode,w.Request];
    w.eval(source+'\nyoutubePlayerRequest();');
    assert.deepEqual([w.JSON.stringify,w.TextEncoder.prototype.encode,w.Request],before);
});
run('handler never installs on another origin',async({w,stringify})=>{
    const body=stringify(fixture());
    assert.equal(w.JSON.stringify(fixture()),body);
    const req=new w.Request('https://example.com/youtubei/v1/player',{method:'POST',body});
    assert.equal(await req.text(),body);
},{host:'example.com'});

run('mobile updates direct and nested content contexts without desktop changes',({w})=>{
    const input=fixture();input.params='original';input.playerRequest={params:'nested',playbackContext:{contentPlaybackContext:{}}};
    const out=JSON.parse(w.JSON.stringify(input));
    const direct=out.playbackContext.contentPlaybackContext.lactMilliseconds;
    assert.match(direct,/^\d+$/);assert.equal(out.playerRequest.playbackContext.contentPlaybackContext.lactMilliseconds,direct);
    assert.equal(out.params,'original');assert.equal(out.playerRequest.params,'nested');
    assert.equal(out.playbackContext.params,undefined);assert.equal(out.context.client.clientScreen,'WATCH');
    assert.equal(out.context.client.configInfo.appInstallData,'fixture');assert.equal(w.document.visibilityState,'prerender');
},{host:'m.youtube.com'});
run('mobile leaves ad contexts untouched and processes eligible siblings',({w})=>{
    for(const ad of [null,{},false])for(const nestedAd of [true,false]) {
        const input=fixture();input.playerRequest={playbackContext:{contentPlaybackContext:{}}};
        const blocked=nestedAd?input.playerRequest.playbackContext:input.playbackContext;
        const eligible=nestedAd?input.playbackContext:input.playerRequest.playbackContext;
        blocked.adPlaybackContext=ad;
        w.JSON.stringify(input);
        assert.equal(blocked.contentPlaybackContext.lactMilliseconds,undefined);
        assert.match(eligible.contentPlaybackContext.lactMilliseconds,/^\d+$/);
    }
},{host:'m.youtube.com'});
for(const path of ['/shorts/video','/tv#/watch?v=video','/embed/video'])run('mobile route exclusions follow SPA navigation '+path,({dom,w,stringify})=>{
    dom.reconfigure({url:'https://m.youtube.com'+path});const input=fixture();assert.equal(w.JSON.stringify(input),stringify(input));
    dom.reconfigure({url:'https://m.youtube.com/watch?v=video'});assert.match(JSON.parse(w.JSON.stringify(input)).playbackContext.contentPlaybackContext.lactMilliseconds,/^\d+$/);
},{host:'m.youtube.com'});
run('mobile ignores unrelated and incomplete objects',({w,stringify})=>{
    for(const input of [null,123,{playbackContext:{contentPlaybackContext:{}}},{context:{client:{}},playbackContext:{}},{context:{client:{}},playerRequest:{}}])assert.equal(w.JSON.stringify(input),stringify(input));
},{host:'m.youtube.com'});
run('mobile serialized bodies and API transports follow the same policy',async({w,stringify})=>{
    const body=stringify(fixture());
    const encoded=JSON.parse(new TextDecoder().decode(new w.TextEncoder().encode(body)));
    const req=new w.Request('https://m.youtube.com/youtubei/v1/player',{method:'POST',body});
    for(const out of [encoded,JSON.parse(await req.text())]){
        assert.match(out.playbackContext.contentPlaybackContext.lactMilliseconds,/^\d+$/);
        assert.equal(out.params,undefined);assert.equal(out.context.client.configInfo.appInstallData,'fixture');
    }
    const unrelated=new w.Request('https://example.com/youtubei/v1/player',{method:'POST',body});assert.equal(await unrelated.text(),body);
},{host:'m.youtube.com'});
