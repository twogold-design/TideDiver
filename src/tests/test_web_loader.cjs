const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const path = require('node:path');
const source = fs.readFileSync(path.resolve(__dirname,'../web/local-loader.js'),'utf8');
const payload = crypto.randomBytes(1200001);
const compressed = zlib.gzipSync(payload);
function environment(protocol, missingCompressed = false, decompression = true) {
  const requests = [];
  const events = [];
  const baseURI = protocol === 'file:' ? 'file:///game/index.html' : 'https://example.test/game/index.html';
  const context = {
    URL, Request, Response, Blob, Uint8Array, Map, Promise, atob, setTimeout,
    DecompressionStream:decompression ? DecompressionStream : undefined,
    CustomEvent:class {constructor(type, detail) {this.type=type;this.detail=detail.detail;}},
    location:{protocol},
    fetch:async input => {
      const url = String(input);
      requests.push(url);
      if (url.endsWith('.gz.bin')) return missingCompressed ? new Response('missing',{status:404}) : new Response(compressed);
      return new Response(payload);
    },
    document:{baseURI,dispatchEvent:event=>events.push(event.detail),createElement:()=>({remove(){}}),head:{appendChild:script=>{
      context.TIDE_LOCAL_DATA = {files:{'index.wasm':{size:payload.length,mime:'application/wasm',gzip:compressed.toString('base64')}},worklets:{}};
      queueMicrotask(()=>script.onload());
    }}},
  };
  context.window = context;
  vm.runInNewContext(source,context);
  return {context,requests,events,baseURI};
}
(async()=>{
  for(const local of [false,true]) {
    const run=environment(local?'file:':'https:');
    await run.context.tidePrepareLocal({fileSizes:{'index.wasm':payload.length}});
    const response=await run.context.fetch(new URL('index.wasm',run.baseURI).href);
    assert.equal(response.headers.get('Content-Type'),'application/wasm');
    assert.equal(Number(response.headers.get('Content-Length')),payload.length);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()),payload);
    assert.equal(run.requests.length,local?0:1);
    if(!local) assert.ok(run.requests[0].endsWith('index.wasm.gz.bin'));
    else assert.ok(run.events.some(message=>message.includes('本地')));
    // A subsequent resource request can decode independently from the same bytes.
    const repeated=await run.context.fetch(new URL('index.wasm',run.baseURI).href);
    assert.deepEqual(Buffer.from(await repeated.arrayBuffer()),payload);
  }
  for(const supported of [true,false]) {
    const run=environment('https:',true,supported);
    await run.context.tidePrepareLocal({fileSizes:{'index.wasm':payload.length}});
    const response=await run.context.fetch(new URL('index.wasm',run.baseURI).href);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()),payload);
    assert.equal(run.requests.length,supported?2:1);
  }
  console.log('WEB_LOADER_PASS: HTTP compressed delivery, local decoding, repeated fetch, missing-file fallback and older-browser fallback');
})().catch(error=>{console.error(error);process.exitCode=1;});
