// Real Chromium touch events: no synthetic key presses or gameplay mutation hooks.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const clientRoot = process.env.TIDE_CLIENT_ROOT ? path.resolve(process.env.TIDE_CLIENT_ROOT) : root;
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
  async function menu(name) {
    await page.waitForTimeout(400); // Let landscape resizing and Godot anchors settle.
    const p = await canvasPoint(name);
    await page.touchscreen.tap(p.x, p.y);
    await page.waitForTimeout(500);
  }
  async function canvasPoint(name) {
    // Use the original 1440x900 desktop design and anchors, including when
    // portrait browsers rotate the stage instead of locking the screen.
    const targets = {
      dive: [345, 518, 0, .5],
      restaurant: [345, 585.5, 0, .5],
      resume: [720, 439, .5, .5],
      book: [1206, 110, .5, .5],
      dock: [107, 51.5, 0, 0],
    };
    assert(targets[name], `Known desktop-layout target ${name}`);
    return page.evaluate(target => {
      const stage = document.getElementById('stage');
      const canvas = document.getElementById('canvas');
      const rect = Element.prototype.getBoundingClientRect.call(stage);
      const matrix = new DOMMatrix(getComputedStyle(stage).transform);
      const corners = [[0,0],[stage.clientWidth,0],[0,stage.clientHeight],[stage.clientWidth,stage.clientHeight]];
      const left = Math.min(...corners.map(([x,y]) => matrix.a*x+matrix.c*y));
      const top = Math.min(...corners.map(([x,y]) => matrix.b*x+matrix.d*y));
      const scale = Math.min(canvas.clientWidth / 1440, canvas.clientHeight / 900);
      const [designX, designY, anchorX, anchorY] = target;
      const x = canvas.offsetLeft + designX * scale + (canvas.clientWidth - 1440 * scale) * anchorX;
      const y = canvas.offsetTop + designY * scale + (canvas.clientHeight - 900 * scale) * anchorY;
      return {x:rect.left+matrix.a*x+matrix.c*y-left,y:rect.top+matrix.b*x+matrix.d*y-top};
    }, targets[name]);
  }
  try {
    await page.goto(process.argv.includes('--http') ? 'http://127.0.0.1:8060/' : pathToFileURL(path.join(clientRoot, 'index.html')).href);
    assert.equal(await page.evaluate(() => window.tideMobileEnabled), true, 'A real touch viewport automatically enables mobile controls');
    await page.getByRole('button', { name: '启程 · 开始游戏' }).tap();
    await page.waitForFunction(() => window.tideGameReady === true, null, { timeout: 150000 });
    await page.waitForTimeout(1200);
    await shot('dock-landscape');
    assert.equal(await page.evaluate(() => window.tideMobileState.state), 'dock');
    await menu('dive');
    await page.waitForFunction(() => window.tideMobileState.state === 'dive', null, { timeout: 10000 });
    await page.waitForFunction(() => !window.tideMobileState.entryActive, null, { timeout: 20000 });
    await page.locator('#touch-joystick').waitFor({ state: 'visible' });
    assert.equal(await page.evaluate(() => document.pointerLockElement), null, 'Mobile swimming works without pointer lock');
    await shot('dive-controls');
    for (const name of ['ascend', 'descend', 'boost', 'stealth', 'shoot', 'knife', 'interact', 'pause', 'bestiary', 'tools']) await center(`#touch-layer [data-action="${name}"]`);
    assert.equal(await page.locator('#touch-topbar > button').count(),3,'Only pause, bestiary and tools occupy the compact top bar');
    assert.deepEqual(await page.locator('#touch-topbar > button').evaluateAll(buttons=>buttons.map(button=>button.dataset.action)),['pause','bestiary','tools']);
    await page.locator('#touch-call-boat').waitFor({state:'hidden'});
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
    assert.equal(await page.evaluate(()=>window.tideMobileState.canCallBoat),false,'A submerged diver cannot call the boat');
    await page.locator('#touch-call-boat').waitFor({state:'hidden'});
    await action('interact');
    assert.equal(await page.evaluate(() => window.tideMobileState.state), 'dive', 'Underwater interaction remains within normal dive rules');
    await action('pause');
    await page.waitForFunction(() => window.tideMobileState.state === 'paused');
    await page.locator('#touch-layer').waitFor({ state: 'hidden' });
    await shot('paused-menu');
    await menu('resume');
    await page.waitForFunction(() => window.tideMobileState.state === 'dive');
    await page.locator('#touch-layer').waitFor({ state: 'visible' });
    await action('bestiary');
    await page.waitForFunction(() => window.tideMobileState.bestiaryOpen === true);
    await page.locator('#touch-layer').waitFor({ state: 'hidden' });
    await shot('bestiary-landscape');
    // The journal retains the desktop top-right return button on phones.
    const bookClose = await canvasPoint('book');
    await page.touchscreen.tap(bookClose.x, bookClose.y);
    await page.waitForFunction(() => window.tideMobileState.bestiaryOpen === false, null, { timeout: 5000 });
    await page.locator('#touch-layer').waitFor({ state: 'visible' });
    const stick2 = await center('#touch-joystick');
    await finger('touchStart', 7, stick2.x, stick2.y - 35);
    await page.waitForFunction(() => window.tideRenderStats.touchMove[1] < -.5);
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    assert.equal(await page.locator('#touch-rotate').count(), 0, 'Portrait never shows a rotate-phone gate');
    assert.equal(await page.evaluate(() => window.tideMobileState.state), 'dive', 'Rotating the device keeps the dive running');
    assert(await page.evaluate(() => document.getElementById('canvas').clientWidth > document.getElementById('canvas').clientHeight), 'Portrait fallback retains a landscape game canvas');
    await page.waitForFunction(() => window.tideRenderStats.touchMove.every(value => Math.abs(value) < .01));
    await finger('touchCancel');
    await shot('portrait-landscape-fallback');
    const portraitStick = await center('#touch-joystick');
    const forward = await page.evaluate(() => {
      const m = new DOMMatrix(getComputedStyle(document.getElementById('stage')).transform);
      return { x:m.c*-35, y:m.d*-35 };
    });
    await finger('touchStart', 9, portraitStick.x, portraitStick.y);
    await finger('touchMove', 9, portraitStick.x+forward.x, portraitStick.y+forward.y);
    await page.waitForFunction(() => window.tideRenderStats.touchMove[1] < -.5 && Math.abs(window.tideRenderStats.touchMove[0]) < .15);
    await finger('touchCancel');
    await action('pause');
    await page.waitForFunction(() => window.tideMobileState.state === 'paused');
    await menu('resume');
    await page.waitForFunction(() => window.tideMobileState.state === 'dive');
    await action('bestiary');
    await page.waitForFunction(() => window.tideMobileState.bestiaryOpen === true);
    await page.locator('#touch-layer').waitFor({ state: 'hidden' });
    const rotatedBookClose = await canvasPoint('book');
    await page.touchscreen.tap(rotatedBookClose.x, rotatedBookClose.y);
    await page.waitForFunction(() => window.tideMobileState.bestiaryOpen === false);
    await page.setViewportSize({ width: 844, height: 390 });
    await page.waitForTimeout(500);
    if (await page.evaluate(() => window.tideMobileState.state === 'paused')) await menu('resume');
    await page.locator('#touch-layer').waitFor({ state: 'visible' });
    assert.equal(await page.evaluate(() => document.pointerLockElement), null);
    await page.setViewportSize({width:667,height:300});
    await page.waitForTimeout(400);
    const compactBar=await page.locator('#touch-topbar').boundingBox();
    assert(compactBar.x>667/2+50 && compactBar.y<=8 && compactBar.height===44,'Toolbar retains 44px hit areas beside the original HUD');
    assert(compactBar.x+compactBar.width<=667-300*.30,'Toolbar does not cover the original depth and backpack panel');
    await shot('compact-dive-667');
    // A real surface ascent exposes the normal pickup action. Keep the ascent
    // finger down while calling, so the return must clear all held input itself.
    const surfaceAscent=await center('[data-action="ascend"]');
    await finger('touchStart',11,surfaceAscent.x,surfaceAscent.y);
    await page.waitForFunction(()=>window.tideRenderStats.playerPosition[1]>=-3.5 && window.tideMobileState.canCallBoat===true,null,{timeout:15000});
    await page.locator('#touch-call-boat').waitFor({state:'visible'});
    await shot('surface-call-boat');
    samples.surface=await stats();
    const boat=await center('#touch-call-boat');
    await finger('touchStart',12,boat.x,boat.y);
    await page.waitForFunction(() => window.tideMobileState.state === 'dock', null, { timeout: 15000 });
    await page.waitForFunction(()=>!window.tideRenderStats.rescueResult && window.tideRenderStats.touchMove.every(value=>Math.abs(value)<.01) && Object.values(window.tideRenderStats.touchHeld).every(value=>!value));
    assert.equal(await page.evaluate(()=>window.tideMobileState.blocked),false,'Calling the boat returns normally without a rescue settlement modal');
    assert.equal(await page.evaluate(()=>window.tideMobileState.canCallBoat),false,'The pickup action becomes unavailable after returning');
    await page.locator('#touch-call-boat').waitFor({state:'hidden'});
    await finger('touchCancel');
    await shot('boat-return-dock');
    await page.setViewportSize({width:844,height:390});
    await page.waitForTimeout(400);
    await menu('restaurant');
    await page.waitForFunction(() => window.tideMobileState.state === 'restaurant');
    await shot('restaurant-landscape');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(500);
    await shot('restaurant-portrait-fallback');
    await menu('dock');
    await page.waitForFunction(() => window.tideMobileState.state === 'dock');
    await shot('dock-portrait-fallback');
    await page.setViewportSize({ width: 667, height: 300 });
    await page.waitForTimeout(500);
    await shot('dock-667');
    await menu('restaurant');
    await page.waitForFunction(() => window.tideMobileState.state === 'restaurant');
    await shot('restaurant-667');
    await menu('dock');
    await page.waitForFunction(() => window.tideMobileState.state === 'dock');
    assert.deepEqual(errors, [], 'No browser, script, shader, or resource errors');
    console.log('PASS: original desktop layout on phones, landscape and portrait dock/restaurant hitboxes, real surface boat pickup, held-input reset, multitouch, weapons and pause/journal.');
  } finally {
    samples.last = await stats().catch(() => null);
    samples.pointerEvents = await page.evaluate(() => window.touchTrace).catch(() => null);
    await shot('last-state').catch(() => {});
    fs.writeFileSync(path.join(output, 'browser-log.json'), JSON.stringify({ errors, messages, samples }, null, 2));
    await context.close();
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
