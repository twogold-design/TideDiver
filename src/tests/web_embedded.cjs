// Contest-style iframe: preserve the fullscreen composition at every player size.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const root = path.resolve(__dirname, '../..');
const client = process.env.TIDE_CLIENT_ROOT || root;
const output = path.join(root, '.runtime', 'embedded-preview');
fs.mkdirSync(output, { recursive: true });
const fixture = path.join(output, 'player.html');
fs.writeFileSync(fixture, `<!doctype html><meta charset="utf-8"><title>Contest player fixture</title><style>body{margin:0;background:#17232f;color:white;font:16px system-ui}h1{font-size:20px;margin:24px}iframe{display:block;margin:24px;border:0;width:974.21875px;height:548px}</style><h1>在线试玩 · 嵌入窗口</h1><iframe id="player" src="/client/index.html" allow="fullscreen; autoplay" allowfullscreen></iframe>`);

(async () => {
  const errors = [];
  const measurements = [];
  // Same-origin HTTP matches the contest host and permits a genuine fullscreen
  // request; file:// parent/child frames have opaque origins in Chromium.
  const server = http.createServer((request, response) => {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    if (pathname === '/favicon.ico') { response.writeHead(204); response.end(); return; }
    const name = pathname.startsWith('/client/') ? path.basename(pathname) : '';
    const file = name ? path.join(client, name) : fixture;
    if (!fs.existsSync(file)) { response.writeHead(404); response.end(); return; }
    const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.wasm': 'application/wasm' };
    response.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({ channel: process.env.TIDE_BROWSER_CHANNEL || 'msedge', headless: true, args: ['--enable-webgl', '--ignore-gpu-blocklist'] });
  const context = await browser.newContext({ viewport: { width: 1200, height: 850 }, deviceScaleFactor: 1, hasTouch: false });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  let game;
  async function capture(name) {
    await page.screenshot({ path: path.join(output, `${name}.png`) });
  }
  async function clickGame(x, y, anchor = [.5, .5]) {
    const box = await game.locator('#canvas').boundingBox();
    assert(box, 'Embedded canvas is visible');
    const scale = Math.min(box.width / 1440, box.height / 900);
    await page.mouse.click(box.x + x * scale + (box.width - 1440 * scale) * anchor[0], box.y + y * scale + (box.height - 900 * scale) * anchor[1]);
    await page.waitForTimeout(350);
  }
  async function state(value) {
    await game.waitForFunction(expected => window.tideRenderStats?.state === expected, value, { timeout: 15000 });
  }
  async function measure(name) {
    await page.waitForTimeout(600);
    const result = await game.locator('#canvas').evaluate(canvas => {
      const rect = canvas.getBoundingClientRect();
      const stage = document.getElementById('stage').getBoundingClientRect();
      const gl = canvas.getContext('webgl2');
      return { css: [rect.width, rect.height], stage: [stage.width, stage.height], pixels: [canvas.width, canvas.height], buffer: [gl.drawingBufferWidth, gl.drawingBufferHeight], dpr: devicePixelRatio, touch: window.tideMobileEnabled };
    });
    assert.equal(result.touch, false, 'Small desktop iframe does not need touch mode');
    assert.deepEqual(result.buffer, result.pixels, `${name}: WebGL buffer matches canvas`);
    for (let i = 0; i < 2; i++) {
      assert(Math.abs(result.css[i] - result.stage[i]) <= 1, `${name}: canvas fills iframe stage`);
      assert.equal(result.pixels[i], Math.round(result.css[i] * result.dpr), `${name}: native pixel size`);
    }
    measurements.push({ name, ...result });
    return result;
  }
  try {
    await page.goto(`http://127.0.0.1:${server.address().port}/player.html`);
    await page.locator('#player').waitFor();
    game = page.frames().find(frame => frame.url().includes('index.html'));
    assert(game, 'The game runs inside a real iframe');
    await game.getByRole('button', { name: '启程 · 开始游戏' }).click();
    await game.waitForFunction(() => window.tideGameReady === true, null, { timeout: 150000 });
    await state('dock');
    for (const [name, width, height] of [['contest', 974.21875, 548], ['small', 640, 360], ['medium', 800, 450]]) {
      await page.locator('#player').evaluate((element, size) => { element.style.width = size.width + 'px'; element.style.height = size.height + 'px'; }, { width, height });
      await measure(`${name}-dock`);
      await capture(`${name}-dock`);
      await clickGame(340, 645, [0, .5]);
      await capture(`${name}-bestiary`);
      await clickGame(1206, 110);
      await clickGame(340, 585, [0, .5]);
      await state('restaurant');
      await capture(`${name}-restaurant`);
      await clickGame(107, 51, [0, 0]);
      await state('dock');
    }
    await page.locator('#player').evaluate(element => { element.style.width = '974.21875px'; element.style.height = '548px'; });
    await measure('before-fullscreen');
    await game.getByRole('button', { name: '全屏', exact: true }).click();
    await game.waitForFunction(() => document.fullscreenElement !== null);
    await measure('fullscreen');
    await capture('fullscreen-dock');
    await clickGame(340, 585, [0, .5]);
    await state('restaurant');
    await game.evaluate(() => document.exitFullscreen());
    await game.waitForFunction(() => document.fullscreenElement === null);
    await measure('restored-restaurant');
    await capture('restored-restaurant');
    await clickGame(107, 51, [0, 0]);
    await state('dock');
    await clickGame(340, 515, [0, .5]);
    await state('dive');
    await page.waitForTimeout(4500);
    await page.keyboard.press('p');
    await state('paused');
    await capture('contest-paused');
    await clickGame(720, 439);
    await state('dive');
    await page.keyboard.press('p');
    await state('paused');
    assert.deepEqual(errors, [], 'No browser, resource, or game script errors');
    console.log('PASS: contest iframe 974x548, 640x360, 800x450, original dock/restaurant/journal controls, fullscreen restore and pause.');
  } finally {
    await capture('last-state').catch(() => {});
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify({ errors, measurements }, null, 2));
    await context.close();
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
