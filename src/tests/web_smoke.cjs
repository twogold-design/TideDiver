const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname,'../..');
const localFile = process.argv.includes('--file');
const entryURL = localFile ? pathToFileURL(path.join(root,'index.html')).href : 'http://127.0.0.1:8060/';
const work = path.join(path.dirname(root),'.'+path.basename(root)+'-web-work');
fs.mkdirSync(path.join(work,'temp'),{recursive:true});
process.env.TEMP = path.join(work,'temp'); process.env.TMP = process.env.TEMP;
const output = path.join(work,localFile ? 'browser-file-check' : 'browser-check');
fs.mkdirSync(output,{recursive:true});
const errors = [];
const messages = [];
(async () => {
  const browser = await chromium.launch({channel:process.env.TIDE_BROWSER_CHANNEL || 'msedge',headless:true,args:['--enable-webgl','--ignore-gpu-blocklist'],downloadsPath:path.join(work,'downloads')});
  const context = await browser.newContext({viewport:{width:1440,height:948},deviceScaleFactor:1});
  const page = await context.newPage();
  const requests = [];
  page.on('request', request => requests.push(request.url()));
  // The temporary plain-text storage-fixture page has no favicon.
  await page.route('**/favicon.ico', route => route.fulfill({status:204}));
  page.on('console', message => { messages.push(message.type()+': '+message.text()); if (message.type()==='error') errors.push(message.text()); });
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(entryURL);
    await page.screenshot({path:path.join(output,'web_landing.png')});
    await page.getByRole('button',{name:'启程 · 开始游戏'}).click();
    await page.waitForFunction(() => window.tideGameReady === true, null, {timeout:120000});
    await page.waitForTimeout(5000);
    await page.screenshot({path:path.join(output,'web_dock.png')});
    const clickGame = async (x,y) => {
      const box = await page.locator('#canvas').boundingBox();
      await page.mouse.click(box.x+x*box.width/1440, box.y+y*box.height/900);
      await page.waitForTimeout(750);
    };
    await clickGame(240,515);
    await page.waitForFunction(()=>document.pointerLockElement!==null,null,{timeout:10000});
    await page.waitForTimeout(4500);
    await page.keyboard.down('w'); await page.waitForTimeout(1000); await page.keyboard.up('w');
    await page.keyboard.press('Space'); await page.waitForTimeout(500);
    await page.screenshot({path:path.join(output,'web_dive.png')});
    await page.keyboard.press('Escape');
    await page.waitForFunction(()=>document.pointerLockElement===null);
    await page.waitForTimeout(750);
    await page.screenshot({path:path.join(output,'web_paused.png')});
    await clickGame(720,439);
    await page.waitForFunction(()=>document.pointerLockElement!==null,null,{timeout:10000});
    await page.keyboard.press('p');
    await page.waitForFunction(()=>document.pointerLockElement===null);
    await clickGame(720,510); // Rescue returns to dock and saves day 2.
    await page.waitForTimeout(2000);
    const databases = await page.evaluate(()=>indexedDB.databases());
    console.log('Persistent databases:', databases);
    const saves = await page.evaluate(async () => {
      const result=[];
      for (const info of await indexedDB.databases()) {
        const db=await new Promise((resolve,reject)=>{const req=indexedDB.open(info.name);req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
        for (const store of db.objectStoreNames) {
          await new Promise((resolve,reject)=>{const tx=db.transaction(store);const req=tx.objectStore(store).openCursor();req.onsuccess=()=>{const cursor=req.result;if(!cursor){resolve();return;}if(String(cursor.key).endsWith('progress.json'))result.push({key:cursor.key,value:new TextDecoder().decode(cursor.value.contents)});cursor.continue();};req.onerror=()=>reject(req.error);});
        }
        db.close();
      }
      return result;
    });
    assert.equal(saves.length,1,'Exactly one browser save exists');
    const save = JSON.parse(saves[0].value);
    assert.equal(save.day,2,'Rescue saved the next day in browser storage');
    fs.writeFileSync(path.join(output,'web-test-save.json'),JSON.stringify(save,null,2));
    await clickGame(240,586);
    await page.screenshot({path:path.join(output,'web_restaurant.png')});
    await page.reload();
    await page.getByRole('button',{name:'启程 · 开始游戏'}).click();
    await page.waitForFunction(() => window.tideGameReady === true, null, {timeout:120000});
    await page.waitForTimeout(1500);
    await page.screenshot({path:path.join(output,'web_reloaded.png')});
    // Seed only this fresh browser context, through its real IndexedDB storage.
    // No shipped test API and no desktop/player save is involved.
    await page.goto(localFile ? entryURL : 'http://127.0.0.1:8060/FONT-LICENSE.txt');
    const fixture = structuredClone(save);
    fixture.day=7; fixture.coins=6000;
    fixture.inventory.orange=8;
    for (const key of Object.keys(fixture.renovation)) fixture.renovation[key]=true;
    fixture.furnishings=[{uid:1,kind:'table',variant:'comfort',x:-3.5,z:1,rotation:0,color:0,placed:true}];
    await page.evaluate(async ({key,fixture})=>{
      const db=await new Promise((resolve,reject)=>{const r=indexedDB.open('/userfs');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});
      await new Promise((resolve,reject)=>{
        const tx=db.transaction('FILE_DATA','readwrite');const store=tx.objectStore('FILE_DATA');const get=store.get(key);
        get.onsuccess=()=>{const value=get.result;value.contents=new TextEncoder().encode(JSON.stringify(fixture));value.timestamp=new Date();store.put(value,key);};
        tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);
      });db.close();
    },{key:saves[0].key,fixture});
    await page.goto(entryURL);
    await page.getByRole('button',{name:'启程 · 开始游戏'}).click();
    await page.waitForFunction(() => window.tideGameReady === true, null, {timeout:120000});
    await clickGame(240,586); await clickGame(440,755);
    await page.waitForTimeout(1500);
    await page.screenshot({path:path.join(output,'web_layout.png')});
    await page.keyboard.down('Alt'); await page.mouse.move(900,470); await page.mouse.down({button:'middle'});
    await page.mouse.move(1090,430,{steps:8});await page.mouse.up({button:'middle'});await page.keyboard.up('Alt');
    await page.mouse.wheel(0,-200);await page.waitForTimeout(500);
    await page.screenshot({path:path.join(output,'web_layout_orbit.png')});
    await page.keyboard.press('f');
    await clickGame(220,370); // Select rug, then cancel without spending.
    await page.mouse.click(850,450,{button:'right'});
    await clickGame(1130,46); // Save layout.
    await clickGame(1310,130); // Menu.
    await clickGame(1330,285); await clickGame(1330,285);
    await clickGame(1300,327); // Prep.
    await page.waitForTimeout(4500);
    await clickGame(700,752); // Open service.
    await page.waitForTimeout(2500);
    await page.screenshot({path:path.join(output,'web_service.png')});
    await page.keyboard.press('p');
    await page.screenshot({path:path.join(output,'web_service_paused.png')});
    await clickGame(700,510); // End service and settle.
    await page.waitForTimeout(1800);
    const finalSave = await page.evaluate(async key=>{
      const db=await new Promise(resolve=>{const r=indexedDB.open('/userfs');r.onsuccess=()=>resolve(r.result);});
      const data=await new Promise(resolve=>{const r=db.transaction('FILE_DATA').objectStore('FILE_DATA').get(key);r.onsuccess=()=>resolve(r.result);});db.close();return JSON.parse(new TextDecoder().decode(data.contents));
    },saves[0].key);
    assert.equal(finalSave.coins,6000,'Cancelled web furniture purchase costs nothing');
    assert.equal(finalSave.day,7,'Reload loaded the browser save');
    assert.equal(finalSave.restaurant_runs,1,'Browser restaurant service completed');
    assert.equal(finalSave.service_active,false,'Restaurant settled before returning');
    await page.setViewportSize({width:1100,height:750});
    await page.screenshot({path:path.join(output,'web_resized.png')});
    assert.equal(errors.length,0,'No browser, script, or resource errors');
    if (localFile) {
      assert.equal(requests.some(url => /^https?:/.test(url)),false,'Double-click game needs no server or network');
      assert.ok(requests.some(url => url.endsWith('/local-data.js')),'Double-click loads bundled resources');
    } else {
      assert.equal(requests.some(url => url.endsWith('/local-data.js')),false,'Hosted game does not download duplicate resources');
    }
    console.log('Entry mode:', localFile ? 'file:// (no server)' : 'HTTP');
    console.log('PASS: browser launch, Chinese UI, dive, mouse capture, Escape/P, resume, rescue, persistent save/reload, layout orbit, cancelled purchase, cooking prep, service, settlement, resize.');
  } finally {
    fs.writeFileSync(path.join(output,'web-browser-log.json'),JSON.stringify({errors,messages},null,2));
    await browser.close();
  }
})().catch(error=>{ console.error(error);process.exitCode=1; });
