// Real Chromium touch events: no synthetic key presses or gameplay mutation hooks.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, '.runtime', 'mobile', 'browser', process.argv.includes('--http') ? 'http' : 'file');
fs.mkdirSync(output, { recursive: true });

(async () => {
  const browser = await chromium.launch({
    channel: process.env.TIDE_BROWSER_CHANNEL || 'msedge', headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist'],
  });
  const context = await browser.newContext({
    viewport: { width: 844, height: 390 }, screen: { width: 844, height: 390 },
    deviceScaleFactor: 2, hasTouch: true, isMobile: true,
  });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await page.addInitScript(() => {
    window.touchTrace = [];
    for (const type of ['pointerdown', 'pointermove', 'pointerup', 'pointercancel', 'lostpointercapture']) {
      document.addEventListener(type, event => {
        window.touchTrace.push({ type, id:event.pointerId, target:event.target.id || event.target.dataset?.action, x:event.clientX, y:event.clientY });
      }, true);
    }
  });
  const errors = [];
  const messages = [];
  const samples = {};
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    messages.push(`${message.type()}: ${message.text()}`);
    if (message.type() === 'error') errors.push(message.text());
  });
  await page.route('**/favicon.ico', route => route.fulfill({ status: 204 }));
  const points = new Map();
  const stats = () => page.evaluate(() => structuredClone(window.tideRenderStats));
  const shot = name => page.screenshot({ path: path.join(output, `${name}.png`) });
  async function finger(type, id, x, y) {
    const ended = points.get(id);
    if (type === 'touchEnd') points.delete(id);
    else if (type === 'touchCancel') points.clear();
    else points.set(id, { id, x, y, radiusX: 4, radiusY: 4, force: 1 });
    // Chromium's per-finger touchEnd uses the point being lifted, not the remaining set.
    const dispatched = type === 'touchEnd' && ended ? [ended] : [...points.values()];
    await cdp.send('Input.dispatchTouchEvent', { type, touchPoints: dispatched });
  }
  async function center(selector) {
    const box = await page.locator(selector).boundingBox();
    assert(box, `Visible touch target ${selector}`);
    assert(box.width >= 44 && box.height >= 44, `Touch target ${selector} is at least 44 CSS pixels`);
    const viewport = page.viewportSize();
    assert(box.x >= 0 && box.y >= 0 && box.x + box.width <= viewport.width + 1 && box.y + box.height <= viewport.height + 1, `Touch target ${selector} stays within the phone screen`);
    return { x: box.x + box.width / 2, y: box.y + box.height / 2, box };
  }
  async function action(name) {
    const p = await center(`#touch-layer [data-action="${name}"]`);
    await page.touchscreen.tap(p.x, p.y);
  }
  async function menu(index) {
    await page.waitForTimeout(400); // Let the mobile header and Godot canvas resize settle.
    const canvas = await page.locator('#canvas').boundingBox();
    const width = (canvas.width - 32) / 2;
    const x = canvas.x + 12 + (index % 2) * (width + 8) + width / 2;
    const y = canvas.y + 76 + Math.floor(index / 2) * 52 + 23;
    await page.touchscreen.tap(x, y);
    await page.waitForTimeout(500);
  }
  try {
    await page.goto(process.argv.includes('--http') ? 'http://127.0.0.1:8060/' : pathToFileURL(path.join(root, 'index.html')).href);
    assert.equal(await page.evaluate(() => window.tideMobileEnabled), true, 'A real touch viewport automatically enables mobile controls');
    await page.getByRole('button', { name: '启程 · 开始游戏' }).tap();
    await page.waitForFunction(() => window.tideGameReady === true, null, { timeout: 150000 });
    await page.waitForTimeout(1200);
    await shot('dock-landscape');
    assert.equal(await page.evaluate(() => window.tideMobileState.state), 'dock');
    await menu(0);
    await page.waitForFunction(() => window.tideMobileState.state === 'dive', null, { timeout: 10000 });
    await page.waitForFunction(() => !window.tideMobileState.entryActive, null, { timeout: 20000 });
    await page.locator('#touch-joystick').waitFor({ state: 'visible' });
    assert.equal(await page.evaluate(() => document.pointerLockElement), null, 'Mobile swimming works without pointer lock');
    await shot('dive-controls');
    for (const name of ['ascend', 'descend', 'boost', 'stealth', 'shoot', 'knife', 'interact', 'pause', 'bestiary']) await center(`#touch-layer [data-action="${name}"]`);
    const stick = await center('#touch-joystick');
    const ascend = await center('[data-action="ascend"]');
    samples.before = await stats();
    await finger('touchStart', 1, stick.x, stick.y);
    await finger('touchMove', 1, stick.x, stick.y - 38);
    await finger('touchStart', 2, 510, 175);
    await finger('touchMove', 2, 545, 157);
    await finger('touchStart', 3, ascend.x, ascend.y);
    await page.waitForFunction(() => window.tideRenderStats.touchMove[1] < -.5 && window.tideRenderStats.touchHeld.ascend === true);
    await page.waitForTimeout(650);
    samples.multitouch = await stats();
    assert(Math.abs(samples.multitouch.yaw - samples.before.yaw) > .05, 'A second touch turns the real camera while swimming');
    assert(samples.multitouch.playerPosition[1] > samples.before.playerPosition[1] + .2, 'A third touch ascends the actual diver concurrently');
    assert(Math.hypot(samples.multitouch.playerPosition[0] - samples.before.playerPosition[0], samples.multitouch.playerPosition[2] - samples.before.playerPosition[2]) > .2, 'The joystick moves the actual diver');
    await finger('touchEnd', 3);
    await page.waitForFunction(() => !window.tideRenderStats.touchHeld.ascend && window.tideRenderStats.touchMove[1] < -.5);
    await finger('touchCancel');
    await page.waitForFunction(() => window.tideRenderStats.touchMove.every(value => Math.abs(value) < .01) && Object.values(window.tideRenderStats.touchHeld).every(value => !value));
    samples.released = await stats();
    assert.equal(samples.released.shotCooldown, 0, 'Movement and look touches never synthesize an unintended harpoon click');
    await action('shoot');
    await page.waitForFunction(() => window.tideRenderStats.shotCooldown > 0);
    samples.fire = await stats();
    await action('knife');
    await page.waitForFunction(() => window.tideRenderStats.knifeRemaining > 0);
    // Move below the return-to-shore threshold with a real held descent button.
    const descend = await center('[data-action="descend"]');
    await finger('touchStart', 8, descend.x, descend.y);
    await page.waitForFunction(() => window.tideRenderStats.playerPosition[1] < -7, null, {timeout: 12000});
    await finger('touchEnd', 8);
    await page.waitForFunction(() => !window.tideRenderStats.touchHeld.descend);
    await action('interact');
    assert.equal(await page.evaluate(() => window.tideMobileState.state), 'dive', 'Underwater interaction remains within normal dive rules');
    await action('pause');
    await page.waitForFunction(() => window.tideMobileState.state === 'paused');
    await page.locator('#touch-layer').waitFor({ state: 'hidden' });
    await shot('paused-menu');
    await menu(1);
    await page.waitForFunction(() => window.tideMobileState.state === 'dive');
    await page.locator('#touch-layer').waitFor({ state: 'visible' });
    await action('bestiary');
    await page.waitForFunction(() => window.tideMobileState.bestiaryOpen === true);
    await shot('bestiary-landscape');
    // Dedicated mobile journal controls use a full-width, three-button bottom row.
    const bookBox = await page.locator('#canvas').boundingBox();
    await page.touchscreen.tap(bookBox.x + bookBox.width / 2, bookBox.y + bookBox.height - 31);
    await page.waitForFunction(() => window.tideMobileState.bestiaryOpen === false, null, { timeout: 5000 });
    await page.locator('#touch-layer').waitFor({ state: 'visible' });
    const stick2 = await center('#touch-joystick');
    await finger('touchStart', 7, stick2.x, stick2.y - 35);
    await page.waitForFunction(() => window.tideRenderStats.touchMove[1] < -.5);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.locator('#touch-rotate').waitFor({ state: 'visible' });
    await page.waitForFunction(() => window.tideRenderStats.touchMove.every(value => Math.abs(value) < .01));
    await finger('touchCancel');
    await shot('portrait-guidance');
    await page.setViewportSize({ width: 844, height: 390 });
    await page.locator('#touch-rotate').waitFor({ state: 'hidden' });
    if (await page.evaluate(() => window.tideMobileState.state === 'paused')) await menu(1);
    await page.locator('#touch-layer').waitFor({ state: 'visible' });
    assert.equal(await page.evaluate(() => document.pointerLockElement), null);
    await action('pause');
    await page.waitForFunction(() => window.tideMobileState.state === 'paused');
    await menu(2); // Normal rescue settlement back to the dock.
    await page.waitForFunction(() => window.tideMobileState.state === 'dock', null, { timeout: 15000 });
    await menu(0); // Dismiss the rescue result.
    await menu(4); // Restaurant.
    await page.waitForFunction(() => window.tideMobileState.state === 'restaurant');
    await shot('restaurant-landscape');
    await menu(0);
    await page.waitForFunction(() => window.tideMobileState.state === 'dock');
    assert.deepEqual(errors, [], 'No browser, script, shader, or resource errors');
    console.log('PASS: mobile dock and restaurant menus, multi-touch movement/look/ascent, cancellation, harpoon/knife/interaction, pause/resume, journal, orientation, and no pointer lock.');
  } finally {
    samples.last = await stats().catch(() => null);
    samples.pointerEvents = await page.evaluate(() => window.touchTrace).catch(() => null);
    await shot('last-state').catch(() => {});
    fs.writeFileSync(path.join(output, 'browser-log.json'), JSON.stringify({ errors, messages, samples }, null, 2));
    await context.close();
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
