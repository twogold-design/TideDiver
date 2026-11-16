// Real browser audio and ordinary UI: no gameplay mutation or playback stubs.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, '.runtime', 'scene-audio');
fs.mkdirSync(output, { recursive: true });

function installAudioProbe() {
  const probe = window.sceneAudioProbe = { starts: [], ends: [], stops: [], levels: [], marks: {} };
  const originalConnect = AudioNode.prototype.connect;
  const taps = new WeakMap();
  AudioNode.prototype.connect = function (destination, ...args) {
    if (destination instanceof AudioDestinationNode) {
      let analyser = taps.get(destination);
      if (!analyser) {
        analyser = this.context.createAnalyser();
        analyser.fftSize = 2048;
        taps.set(destination, analyser);
        originalConnect.call(analyser, destination);
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
  async function menu(index) {
    const p = await page.evaluate(index => {
      const canvas = document.getElementById('canvas');
      const rect = canvas.getBoundingClientRect();
      const width = (canvas.clientWidth - 32) / 2;
      return { x: rect.x + 12 + (index % 2) * (width + 8) + width / 2, y: rect.y + 76 + Math.floor(index / 2) * 52 + 23 };
    }, index);
    await page.touchscreen.tap(p.x, p.y);
  }
  async function audible(since, label) {
    const sample = await data();
    assert(sample.levels.some(level => level.t >= since && level.state === 'running' && level.rms > .001), `${label} reaches the real Web Audio output`);
  }
  try {
    await page.goto(process.argv.includes('--http') ? 'http://127.0.0.1:8060/' : pathToFileURL(path.join(root, 'index.html')).href);
    await page.getByRole('button', { name: '启程 · 开始游戏' }).tap();
    await page.waitForFunction(() => window.tideGameReady === true, null, { timeout: 150000 });
    await state('dock');
    await mark('dock');
    await page.waitForTimeout(1800);
    let sample = await data();
    assert(!sample.starts.some(source => source.duration > 10), 'Long loops use continuous streaming rather than the Web Sample ended/restart path');
    await audible(sample.marks.dock, 'Main menu music');

    await mark('restaurant');
    await menu(4);
    await state('restaurant');
    await page.waitForTimeout(1600);
    sample = await data();
    await audible(sample.marks.restaurant + 800, 'Restaurant music');

    await mark('mute');
    await page.keyboard.press('m');
    await page.waitForTimeout(700);
    sample = await data();
    assert(sample.levels.filter(level => level.t > sample.marks.mute + 250).every(level => level.rms < .0001), 'Mute silences actual output');
    await mark('unmute');
    await page.keyboard.press('m');
    await page.waitForTimeout(1000);
    await audible((await data()).marks.unmute + 200, 'Restored restaurant music');

    await mark('returnDock');
    await menu(0);
    await state('dock');
    await page.waitForTimeout(1300);
    sample = await data();
    await audible(sample.marks.returnDock + 800, 'Main menu music after restaurant');
    await mark('dive');
    await menu(0);
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
      assert(!sample.starts.some(source => source.duration > 10), 'Continuous streaming never creates or restarts a long Sample source');
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
    await menu(1);
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
    console.log(`PASS: actual main/restaurant audio, repeated underwater mute/resume, underwater output after splash, ${process.argv.includes('--quick') ? 'quick regression' : 'continuous full-loop boundary'}, and normal boat return. Lifecycle and exact fade timing are covered by test_scene_audio.gd.`);
  } finally {
    fs.writeFileSync(path.join(output, process.argv.includes('--quick') ? 'browser-audio-quick.json' : 'browser-audio.json'), JSON.stringify({ ...await data().catch(() => ({})), errors, messages }, null, 2));
    await page.screenshot({ path: path.join(output, 'last-state.png') }).catch(() => {});
    await context.close();
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
