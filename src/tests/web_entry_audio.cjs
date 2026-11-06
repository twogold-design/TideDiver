// Exercise the normal UI entry and measure the real Web Audio output, not .playing.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, '.runtime', 'entry-audio');
fs.mkdirSync(output, { recursive: true });
const entryURL = process.argv.includes('--http')
  ? 'http://127.0.0.1:8060/' : pathToFileURL(path.join(root, 'index.html')).href;

function installAudioProbe() {
  const probe = window.entryAudioProbe = { starts: [], ends: [], levels: [] };
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
          for (const value of data) {
            sum += value * value;
            peak = Math.max(peak, Math.abs(value));
          }
          probe.levels.push({ t: performance.now(), rms: Math.sqrt(sum / data.length), peak, state: analyser.context.state });
        }, 25);
      }
      return originalConnect.call(this, analyser, ...args);
    }
    return originalConnect.call(this, destination, ...args);
  };
  const originalStart = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...args) {
    // Metadata only: scanning all PCM samples on every restart would conceal timing bugs.
    if (this.buffer && Math.abs(this.buffer.duration - 4.28096) < .015) {
      const id = probe.starts.length;
      probe.starts.push({ id, t: performance.now(), duration: this.buffer.duration, rate: this.buffer.sampleRate, args });
      this.addEventListener('ended', () => probe.ends.push({ id, t: performance.now() }), { once: true });
    }
    return originalStart.apply(this, args);
  };
}

function audibleSpan(levels) {
  // The supplied tail fades naturally; quiet troughs need not remain above a gate.
  const active = levels.filter(sample => sample.state === 'running' && sample.rms > .001);
  return active.length > 1 ? active.at(-1).t - active[0].t : 0;
}

(async () => {
  const browser = await chromium.launch({
    channel: process.env.TIDE_BROWSER_CHANNEL || 'msedge', headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist'],
  });
  async function scenario(withPause) {
    const context = await browser.newContext({ viewport: { width: 1440, height: 948 }, deviceScaleFactor: 1 });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    await page.route('**/favicon.ico', route => route.fulfill({ status: 204 }));
    await page.addInitScript(installAudioProbe);
    let data;
    try {
      await page.goto(entryURL);
      await page.getByRole('button', { name: '启程 · 开始游戏' }).click();
      await page.waitForFunction(() => window.tideGameReady === true, null, { timeout: 120000 });
      await page.waitForTimeout(1800);
      const box = await page.locator('#canvas').boundingBox();
      const scale = Math.min(box.width / 1440, box.height / 900);
      await page.mouse.click(box.x + 240 * scale, box.y + 515 * scale + (box.height - 900 * scale) / 2);
      await page.waitForFunction(() => window.entryAudioProbe.starts.length > 0, null, { timeout: 15000 });
      if (withPause) {
        await page.waitForTimeout(400);
        await page.keyboard.press('p');
        await page.waitForTimeout(550);
        const pausedStarts = await page.evaluate(() => window.entryAudioProbe.starts.length);
        assert.equal(pausedStarts, 1, 'Entry starts once before pausing');
        await page.waitForTimeout(450);
        assert.equal(await page.evaluate(() => window.entryAudioProbe.starts.length), pausedStarts, 'Paused audio does not restart');
        await page.keyboard.press('p');
      }
      await page.waitForTimeout(5200);
      data = await page.evaluate(() => window.entryAudioProbe);
      const firstStart = data.starts[0].t;
      const levels = data.levels.filter(sample => sample.t >= firstStart);
      const peak = Math.max(0, ...levels.map(sample => sample.peak));
      const audibleMs = audibleSpan(levels);
      const firstRms = Math.max(0, ...levels.filter(sample => sample.t < firstStart + 1500).map(sample => sample.rms));
      assert.equal(data.starts.length, withPause ? 2 : 1, 'Only entry and an explicit resume may start the splash buffer');
      assert(peak > .015, `Real output must contain an audible splash (peak ${peak})`);
      assert(firstRms > .005, `The opening splash must have meaningful output RMS (${firstRms})`);
      assert(audibleMs > 2000, `Audible output must extend into the underwater tail (${audibleMs.toFixed(0)}ms)`);
      if (!withPause) {
        const end = data.ends.find(event => event.id === 0);
        assert(end && end.t - firstStart > 4000, 'The complete source reaches its natural end after four seconds');
      }
      assert.equal(errors.length, 0, `No browser/resource errors: ${errors.join('; ')}`);
      console.log(`PASS: Web entry audio${withPause ? ' pause/resume' : ''}: ${data.starts.length} start(s), peak ${peak.toFixed(4)}, audible tail ${(audibleMs / 1000).toFixed(2)}s.`);
    } finally {
      data ||= await page.evaluate(() => window.entryAudioProbe).catch(() => ({}));
      fs.writeFileSync(path.join(output, withPause ? 'pause-resume.json' : 'normal-entry.json'), JSON.stringify({ ...data, errors }, null, 2));
      await context.close();
    }
  }
  try {
    await scenario(false);
    if (process.argv.includes('--pause')) await scenario(true);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
