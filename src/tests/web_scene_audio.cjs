// Real browser audio and ordinary UI: no gameplay mutation or playback stubs.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const clientRoot = process.env.TIDE_CLIENT_ROOT ? path.resolve(process.env.TIDE_CLIENT_ROOT) : root;
const output = path.join(root, '.runtime', 'scene-audio');
fs.mkdirSync(output, { recursive: true });

function installAudioProbe() {
  const probe = window.sceneAudioProbe = { starts: [], ends: [], stops: [], levels: [], workletLevels: [], marks: {}, meterReady: false };
  const originalConnect = AudioNode.prototype.connect;
  const meterSource = `class TideMeter extends AudioWorkletProcessor {
    constructor() { super(); this.frames=0; this.energy=0; }
    process(inputs,outputs) {
      const input=inputs[0];
      if (input && input[0]) {
        for (const sample of input[0]) { this.energy+=sample*sample; this.frames++; }
        if (this.frames>=1024) { this.port.postMessage({t:currentTime,rms:Math.sqrt(this.energy/this.frames)}); this.frames=0; this.energy=0; }
      }
      return true;
    }
  }; registerProcessor('tide-output-meter',TideMeter);`;
  window.sceneAudioContexts=[];
  function meter(context, analyser) {
    window.sceneAudioContexts.push(context);
    const url='data:text/javascript;charset=utf-8,'+encodeURIComponent(meterSource);
    context.audioWorklet.addModule(url).then(()=>{
      const node=new AudioWorkletNode(context,'tide-output-meter');
      const silence=context.createGain(); silence.gain.value=0;
      originalConnect.call(analyser,node);
      originalConnect.call(node,silence);
      originalConnect.call(silence,context.destination);
      node.port.onmessage=event=>probe.workletLevels.push(event.data);
      probe.meterReady=true;
    }).catch(error=>probe.meterError=error.message);
  }
  const taps = new WeakMap();
  AudioNode.prototype.connect = function (destination, ...args) {
    if (destination instanceof AudioDestinationNode) {
      let analyser = taps.get(destination);
      if (!analyser) {
        analyser = this.context.createAnalyser();
        analyser.fftSize = 2048;
        taps.set(destination, analyser);
        originalConnect.call(analyser, destination);
        meter(this.context,analyser);
        const data = new Float32Array(analyser.fftSize);
        setInterval(() => {
          analyser.getFloatTimeDomainData(data);
          let sum = 0, peak = 0;
          for (const value of data) { sum += value * value; peak = Math.max(peak, Math.abs(value)); }
          probe.levels.push({ t: performance.now(), rms: Math.sqrt(sum / data.length), peak, state: analyser.context.state });
        }, 25);
      }
      return originalConnect.call(this, analyser, ...args);
    }
    return originalConnect.call(this, destination, ...args);
  };
  const ids = new WeakMap();
  const start = AudioBufferSourceNode.prototype.start;
  const stop = AudioBufferSourceNode.prototype.stop;
  AudioBufferSourceNode.prototype.start = function (...args) {
    if (this.buffer) {
      const id = probe.starts.length;
      ids.set(this, id);
      probe.starts.push({ id, t: performance.now(), duration: this.buffer.duration, loop: this.loop, loopStart: this.loopStart, loopEnd: this.loopEnd, args });
      this.addEventListener('ended', () => probe.ends.push({ id, t: performance.now() }), { once: true });
    }
    return start.apply(this, args);
  };
  AudioBufferSourceNode.prototype.stop = function (...args) {
    if (ids.has(this)) probe.stops.push({ id: ids.get(this), t: performance.now(), args });
    return stop.apply(this, args);
  };
}

(async () => {
  const browser = await chromium.launch({ channel: process.env.TIDE_BROWSER_CHANNEL || 'msedge', headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist'] });
  const context = await browser.newContext({ viewport: { width: 844, height: 390 }, screen: { width: 844, height: 390 }, deviceScaleFactor: 1, hasTouch: true, isMobile: true });
  const page = await context.newPage();
  const errors = [];
  const messages = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { messages.push(message.text()); if (message.type() === 'error') errors.push(message.text()); });
  await page.route('**/favicon.ico', route => route.fulfill({ status: 204 }));
  await page.addInitScript(installAudioProbe);
  const data = () => page.evaluate(() => window.sceneAudioProbe);
  const mark = name => page.evaluate(name => window.sceneAudioProbe.marks[name] = performance.now(), name);
  async function state(value) { await page.waitForFunction(value => window.tideMobileState?.state === value, value, { timeout: 15000 }); }
  async function menu(name) {
    const targets={
      dive:[345,518,0,.5], restaurant:[345,585.5,0,.5], resume:[720,439,.5,.5],
      book:[1206,110,.5,.5], dock:[107,51.5,0,0],
      nextWarehouse:[245,641,0,.5], previousWarehouse:[93,641,0,.5],
      restaurantBook:[443.5,814,.5,1], renovation:[1133,131,1,.5],
    };
    assert(targets[name],`Known original-layout target ${name}`);
    const p = await page.evaluate(target => {
      const canvas=document.getElementById('canvas');
      const rect=canvas.getBoundingClientRect();
      const scale=Math.min(canvas.clientWidth/1440,canvas.clientHeight/900);
      const [x,y,ax,ay]=target;
      return {x:rect.x+x*scale+(canvas.clientWidth-1440*scale)*ax,y:rect.y+y*scale+(canvas.clientHeight-900*scale)*ay};
    }, targets[name]);
    await page.touchscreen.tap(p.x,p.y);
    await page.waitForTimeout(100);
  }
  async function audible(since, label) {
    const sample = await data();
    assert(sample.levels.some(level => level.t >= since && level.state === 'running' && level.rms > .001), `${label} reaches the real Web Audio output`);
  }
  try {
    await page.goto(process.argv.includes('--http') ? 'http://127.0.0.1:8060/' : pathToFileURL(path.join(clientRoot, 'index.html')).href);
    await page.getByRole('button', { name: '启程 · 开始游戏' }).tap();
    await page.waitForFunction(() => window.tideGameReady === true, null, { timeout: 150000 });
    await state('dock');
    await mark('dock');
    await page.waitForTimeout(1800);
    let sample = await data();
    assert(sample.starts.some(source => source.duration > 10 && source.loop), 'Main music uses a native browser loop independent of game frames');
    await audible(sample.marks.dock, 'Main menu music');

    await mark('restaurant');
    await menu('restaurant');
    await state('restaurant');
    await page.waitForTimeout(1600);
    sample = await data();
    await audible(sample.marks.restaurant + 900, 'Restaurant music');
    const restaurantSource=sample.starts.filter(source=>source.duration>10).at(-1);
    assert(restaurantSource && restaurantSource.loop,'Restaurant music uses native browser looping');
    const restaurantStarts=sample.starts.filter(source=>source.duration>10).length;
    await mark('restaurantUi');
    for(let i=0;i<5;i++) {
      await menu('nextWarehouse');
      await menu('previousWarehouse');
      await menu('renovation');
      await menu('restaurantBook');
      await page.waitForFunction(()=>window.tideMobileState?.bestiaryOpen===true);
      await menu('book');
      await page.waitForFunction(()=>window.tideMobileState?.bestiaryOpen===false);
    }
    await state('restaurant');
    sample=await data();
    assert.equal(sample.starts.filter(source=>source.duration>10).length,restaurantStarts,'Repeated restaurant controls do not start replacement music');
    assert(!sample.stops.some(source=>source.id===restaurantSource.id),'Restaurant UI never stops the active music source');
    assert(!sample.ends.some(source=>source.id===restaurantSource.id),'Restaurant UI never ends the active music source');
    await audible(sample.marks.restaurantUi,'Restaurant music during repeated UI refreshes');
    await page.waitForFunction(()=>window.sceneAudioProbe.meterReady===true,null,{timeout:10000});
    // Isolate the original failure: a busy UI/main thread must not starve music.
    // The meter runs on the browser audio thread and queues real output samples.
    const busy=await page.evaluate(()=>{
      const context=window.sceneAudioContexts[0];
      const start=context.currentTime;
      const until=performance.now()+850;
      while(performance.now()<until) Math.sqrt(Math.random());
      return {start,end:context.currentTime};
    });
    await page.waitForTimeout(250);
    sample=await data();
    const duringBusy=sample.workletLevels.filter(level=>level.t>busy.start+.15 && level.t<busy.end-.05);
    assert(duringBusy.length>=10,'Audio thread records output while the UI thread is blocked');
    assert(duringBusy.every(level=>level.rms>.00001),'Music remains audible throughout an 850ms UI-thread stall');
    assert(!sample.stops.some(source=>source.id===restaurantSource.id),'UI-thread stall does not stop or recreate music');
    await page.screenshot({path:path.join(output,'restaurant-continuity.png')});

    await mark('mute');
    await page.keyboard.press('m');
    await page.waitForTimeout(700);
    sample = await data();
    assert(sample.levels.filter(level => level.t > sample.marks.mute + 250).every(level => level.rms < .0001), 'Mute silences actual output');
    await mark('unmute');
    await page.keyboard.press('m');
    await page.waitForTimeout(1000);
    await audible((await data()).marks.unmute + 200, 'Restored restaurant music');
    sample=await data();
    const firstResume=sample.starts.filter(source=>source.duration>10).at(-1);
    assert(firstResume.loop && firstResume.args[1]>1,'Unmuting preserves the native music loop and elapsed position');
    await page.keyboard.press('m');
    await page.waitForTimeout(500);
    await page.keyboard.press('m');
    await page.waitForTimeout(650);
    sample=await data();
    const secondResume=sample.starts.filter(source=>source.duration>10).at(-1);
    assert(secondResume.loop && secondResume.args[1]>firstResume.args[1]+.3,'Repeated music mute/resume continues forward instead of resetting the playhead');
    await audible(secondResume.t+100,'Restaurant music after the second unmute');

    await mark('returnDock');
    await menu('dock');
    await state('dock');
    await page.waitForTimeout(1300);
    sample = await data();
    await audible(sample.marks.returnDock + 800, 'Main menu music after restaurant');
    await mark('dive');
    await menu('dive');
    await state('dive');
    await page.waitForFunction(() => !window.tideMobileState.entryActive, null, { timeout: 20000 });
    await mark('submerged');
    await page.waitForTimeout(5000); // Let the independent splash finish first.
    sample = await data();
    assert(sample.starts.some(source => Math.abs(source.duration - 4.28096) < .015), 'Normal entry still plays its independent splash');
    await audible(sample.marks.submerged + 4500, 'Underwater ambience after splash finishes');
    // Pause gameplay to isolate one complete ambience loop without oxygen loss.
    await page.locator('[data-action="pause"]').tap();
    await state('paused');
    if (!process.argv.includes('--quick')) {
      const remaining = Math.max(0, sample.marks.submerged + 39000 - await page.evaluate(() => performance.now()));
      await page.waitForTimeout(remaining);
      sample = await data();
      assert(!sample.starts.some(source => source.t >= sample.marks.submerged && source.duration > 10), 'Underwater continuous streaming never creates or restarts a long Sample source');
      await audible(sample.marks.submerged + 37111, 'Ambience after its first complete loop');
      const boundary = sample.levels.filter(level => level.t > sample.marks.submerged + 33000 && level.t < sample.marks.submerged + 39000);
      assert(boundary.length > 40 && boundary.every(level => level.state === 'running' && level.rms > .0001), 'Actual output remains non-silent throughout the first loop-boundary window');
    }
    for (let i = 0; i < 2; i++) {
      const mutedAt = await mark(`underwaterMute${i}`);
      await page.keyboard.press('m');
      await page.waitForTimeout(1200);
      sample = await data();
      const silent = sample.levels.filter(level => level.t > mutedAt + 300);
      assert(silent.length > 5 && silent.every(level => level.rms < .0001), 'Underwater ambience stays silent throughout consecutive paused frames');
      const resumedAt = await mark(`underwaterResume${i}`);
      await page.keyboard.press('m');
      await page.waitForTimeout(1000);
      await audible(resumedAt + 250, 'Underwater ambience after unmute');
    }
    await menu('resume');
    await state('dive');
    const ascend = page.locator('[data-action="ascend"]');
    const box = await ascend.boundingBox();
    const cdp = await context.newCDPSession(page);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: box.x + box.width/2, y: box.y + box.height/2, id: 1 }] });
    await page.waitForFunction(() => window.tideMobileState.canCallBoat === true, null, { timeout: 12000 });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await mark('boat');
    await page.locator('#touch-call-boat').tap();
    await state('dock');
    await page.waitForTimeout(900);
    sample = await data();
    await audible(sample.marks.boat + 300, 'Main menu music after returning');
    assert.deepEqual(errors, [], 'No browser/audio/resource errors');
    console.log(`PASS: native-loop main/restaurant audio, repeated restaurant UI and 850ms busy-thread continuity, repeated underwater mute/resume, underwater output after splash, ${process.argv.includes('--quick') ? 'quick regression' : 'continuous full-loop boundary'}, and normal boat return. Lifecycle and exact fade timing are covered by test_scene_audio.gd.`);
  } finally {
    fs.writeFileSync(path.join(output, process.argv.includes('--quick') ? 'browser-audio-quick.json' : 'browser-audio.json'), JSON.stringify({ ...await data().catch(() => ({})), errors, messages }, null, 2));
    await page.screenshot({ path: path.join(output, 'last-state.png') }).catch(() => {});
    await context.close();
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
