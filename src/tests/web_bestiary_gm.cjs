// Real UI, fresh browser storage, and exported file:// resources.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname, '../..');
const output = path.join(root, '.runtime', 'bestiary-web');
fs.mkdirSync(output, { recursive: true });

(async () => {
  const browser = await chromium.launch({
    channel: process.env.TIDE_BROWSER_CHANNEL || 'msedge', headless: true,
    args: ['--enable-webgl', '--ignore-gpu-blocklist'],
  });
  const context = await browser.newContext({ viewport: { width: 1440, height: 948 }, deviceScaleFactor: 1 });
  const page = await context.newPage();
  const errors = [];
  const messages = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    messages.push(`${message.type()}: ${message.text()}`);
    if (message.type() === 'error') errors.push(message.text());
  });
  await page.route('**/favicon.ico', route => route.fulfill({ status: 204 }));

  async function ready() {
    await page.getByRole('button', { name: '启程 · 开始游戏' }).click();
    await page.waitForFunction(() => window.tideGameReady === true, null, { timeout: 120000 });
    await page.waitForTimeout(1800);
  }

  async function clickGame(x, y, anchor = [.5, .5]) {
    const box = await page.locator('#canvas').boundingBox();
    const scale = Math.min(box.width / 1440, box.height / 900);
    await page.mouse.click(
      box.x + x * scale + (box.width - 1440 * scale) * anchor[0],
      box.y + y * scale + (box.height - 900 * scale) * anchor[1],
    );
    await page.waitForTimeout(450);
  }

  async function readSave() {
    return page.evaluate(async () => {
      for (const info of await indexedDB.databases()) {
        const db = await new Promise((resolve, reject) => {
          const request = indexedDB.open(info.name);
          request.onsuccess = () => resolve(request.result);
          request.onerror = () => reject(request.error);
        });
        let found = null;
        for (const store of db.objectStoreNames) {
          await new Promise((resolve, reject) => {
            const request = db.transaction(store).objectStore(store).openCursor();
            request.onsuccess = () => {
              const cursor = request.result;
              if (!cursor) return resolve();
              if (String(cursor.key).endsWith('progress.json')) {
                found = JSON.parse(new TextDecoder().decode(cursor.value.contents));
              }
              cursor.continue();
            };
            request.onerror = () => reject(request.error);
          });
        }
        db.close();
        if (found) return found;
      }
      return null;
    });
  }

  async function savedWhen(predicate, label) {
    const deadline = Date.now() + 10000;
    do {
      const save = await readSave();
      if (save && predicate(save)) return save;
      await page.waitForTimeout(250);
    } while (Date.now() < deadline);
    assert.fail(`Browser save did not reach: ${label}`);
  }

  async function capture(name) {
    await page.screenshot({ path: path.join(output, `${name}.png`) });
  }

  try {
    await page.goto(pathToFileURL(path.join(root, 'index.html')).href);
    await ready();
    await page.keyboard.press('b');
    await page.waitForTimeout(700);
    await capture('dock-bestiary');
    await clickGame(450, 750);
    await capture('bestiary-page-two');
    await page.keyboard.press('b');
    await page.waitForTimeout(700);
    await clickGame(240, 586, [0, .5]);
    await page.keyboard.press('F1');
    await page.waitForTimeout(250);
    await capture('restaurant-gm-on');
    await clickGame(1310, 199, [1, .5]);
    let save = await savedWhen(value => value.renovation.clean === true, 'free clean renovation');
    assert.equal(save.coins, 0, 'GM renovation does not overwrite the genuine zero-coin balance');
    assert.equal(save.renovation.kitchen, false);
    assert.equal(Object.hasOwn(save, 'gm_infinite_coins'), false, 'GM flag is session-only');
    assert.equal(typeof save.discoveries, 'object', 'Journal dictionary persists with the save');
    assert(!Array.isArray(save.discoveries));

    await page.keyboard.press('F1');
    await page.waitForTimeout(250);
    await clickGame(1310, 293, [1, .5]);
    save = await readSave();
    assert.equal(save.renovation.kitchen, false, 'Turning GM off restores normal insufficient-funds rules');
    await capture('restaurant-gm-off');
    await page.keyboard.press('F1');
    await page.waitForTimeout(250);
    await clickGame(1310, 293, [1, .5]);
    save = await savedWhen(value => value.renovation.kitchen === true, 'free kitchen renovation');
    assert.equal(save.coins, 0);
    assert.equal(save.renovation.tables, false);
    assert.equal(Object.hasOwn(save, 'gm_infinite_coins'), false);

    await page.keyboard.press('b');
    await page.waitForTimeout(650);
    await capture('restaurant-bestiary');
    await page.keyboard.press('b');
    await page.waitForTimeout(700);
    await capture('restaurant-returned');
    await page.reload();
    await ready();
    await clickGame(240, 586, [0, .5]);
    await clickGame(1310, 387, [1, .5]);
    save = await readSave();
    assert(save.renovation.clean && save.renovation.kitchen, 'Actual saved free renovations survive reloading');
    assert.equal(save.renovation.tables, false, 'Reload defaults GM to off: zero-coin table renovation remains blocked');
    assert.equal(save.coins, 0);
    assert.equal(Object.hasOwn(save, 'gm_infinite_coins'), false);
    await capture('restaurant-reloaded-gm-off');
    await page.keyboard.press('F1');
    await page.waitForTimeout(250);
    for (const [id, y] of [['tables', 387], ['sign', 481], ['expansion', 575], ['decor', 669]]) {
      await clickGame(1310, y, [1, .5]);
      save = await savedWhen(value => value.renovation[id] === true, `complete ${id} renovation`);
    }
    assert(Object.values(save.renovation).every(Boolean), 'All six real renovation controls complete successfully');
    assert.equal(save.coins, 0, 'Completing the shop under GM preserves actual zero funds');
    await capture('restaurant-completed-menu');
    await page.reload();
    await ready();
    await clickGame(240, 586, [0, .5]);
    await capture('restaurant-completed-menu-reloaded');
    save = await readSave();
    assert(Object.values(save.renovation).every(Boolean), 'Fully renovated state survives browser reload');
    assert.equal(save.coins, 0);
    assert.equal(Object.hasOwn(save, 'gm_infinite_coins'), false);
    fs.writeFileSync(path.join(output, 'verified-save.json'), JSON.stringify(save, null, 2));
    assert.deepEqual(errors, [], 'No browser, resource, script, or shader errors');
    console.log('PASS: browser bestiary open/page/close, restaurant entry, F1 free renovations, GM off restriction, journal persistence, completed-shop menu and reload with GM off.');
  } finally {
    fs.writeFileSync(path.join(output, 'browser-log.json'), JSON.stringify({ errors, messages }, null, 2));
    await context.close();
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
