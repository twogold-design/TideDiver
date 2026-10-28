const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { pathToFileURL } = require('node:url');
const root = path.resolve(__dirname,'../..');
const localFile = process.argv.includes('--file');
const wide = process.argv.includes('--wide');
const uiText = process.argv.includes('--ui-text');
const summer = process.argv.includes('--summer');
const layoutPerf = process.argv.includes('--layout-perf');
const layoutTransitions = process.argv.includes('--layout-transitions');
const entryURL = localFile ? pathToFileURL(path.join(root,'index.html')).href : 'http://127.0.0.1:8060/';
const work = path.join(path.dirname(root),'.'+path.basename(root)+'-web-work');
fs.mkdirSync(path.join(work,'temp'),{recursive:true});
process.env.TEMP = path.join(work,'temp'); process.env.TMP = process.env.TEMP;
const output = path.join(work,(localFile ? 'browser-file-check' : 'browser-check')+(wide?'-wide':''));
fs.mkdirSync(output,{recursive:true});
const errors = [];
const messages = [];
(async () => {
  const browser = await chromium.launch({channel:process.env.TIDE_BROWSER_CHANNEL || 'msedge',headless:true,args:['--enable-webgl','--ignore-gpu-blocklist'],downloadsPath:path.join(work,'downloads')});
  const context = await browser.newContext({viewport:wide?{width:1920,height:900}:{width:1440,height:948},deviceScaleFactor:1});
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
    const clickGame = async (x,y,anchor=[0.5,0.5]) => {
      const box = await page.locator('#canvas').boundingBox();
      const scale = Math.min(box.width/1440,box.height/900);
      await page.mouse.click(box.x+x*scale+(box.width-1440*scale)*anchor[0], box.y+y*scale+(box.height-900*scale)*anchor[1]);
      await page.waitForTimeout(750);
    };
    await clickGame(240,515,[0,0.5]);
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
    await page.screenshot({path:path.join(output,'web_rescue_result.png')});
    await clickGame(720,639); // Acknowledge the persistent rescue summary.
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
    await clickGame(240,586,[0,0.5]);
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
    fixture.furnishings=[{uid:1,kind:'table',variant:summer?'summer':'comfort',x:-3.5,z:1,rotation:0,color:0,placed:true}];
    if(summer)fixture.furnishings.push({uid:100,kind:'soft',variant:'summer',x:0,z:8.5,rotation:0,color:2,placed:true});
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
    await clickGame(240,586,[0,0.5]);
    if(layoutTransitions){
      const samples=[];
      const measure=async(name,x,y,anchor)=>{
        await page.evaluate(()=>{
          window.layoutTransitionFrames=[];window.layoutTransitionRecording=true;
          let last=performance.now();
          const frame=now=>{if(!window.layoutTransitionRecording)return;window.layoutTransitionFrames.push(now-last);last=now;requestAnimationFrame(frame);};
          requestAnimationFrame(frame);
        });
        await page.waitForTimeout(150);
        await clickGame(x,y,anchor);
        await page.waitForTimeout(2000);
        const result=await page.evaluate(()=>{
          window.layoutTransitionRecording=false;
          const frames=window.layoutTransitionFrames.slice(1).sort((a,b)=>a-b);
          return {maxMs:Math.max(...frames),p95Ms:frames[Math.floor(frames.length*.95)],over100Ms:frames.filter(v=>v>100)};
        });
        samples.push({name,...result});console.log('LAYOUT_TRANSITION',name,JSON.stringify(result));
        await page.screenshot({path:path.join(output,`layout-transition-${name}.png`)});
      };
      await measure('enter-first',440,755,[.5,1]);
      await measure('cancel',1323,46,[1,0]);
      await measure('enter-repeat',440,755,[.5,1]);
      await measure('save',1135,46,[1,0]);
      fs.writeFileSync(path.join(work,process.argv.includes('--baseline')?'layout-transitions-before.json':'layout-transitions-after.json'),JSON.stringify(samples,null,2));
      assert.deepEqual(errors,[]);
      if(!process.argv.includes('--baseline'))assert.ok(samples.every(v=>v.maxMs<300),'Layout entry and exit avoid long freezes');
      if(!summer)return;
    }
    await clickGame(440,755,[0.5,1]);
    await page.waitForTimeout(1500);
    await page.screenshot({path:path.join(output,'web_layout.png')});
    if(layoutPerf){
      await page.setViewportSize({width:1366,height:800});
      await page.waitForTimeout(1000);
      await clickGame(90,251,[0,0]); // Detailed soft-decoration models.
      const samples=[];
      const measure=async(name,move)=>{
        await page.evaluate(()=>{
          window.layoutFrames=[];window.layoutMeasuring=true;
          let last=performance.now();
          const frame=now=>{if(!window.layoutMeasuring)return;window.layoutFrames.push(now-last);last=now;requestAnimationFrame(frame);};
          requestAnimationFrame(frame);
        });
        const box=await page.locator('#canvas').boundingBox();
        const started=Date.now();let step=0;
        while(Date.now()-started<6000){
          if(move){await page.mouse.move(box.x+box.width*(.62+.16*Math.sin(step*.16)),box.y+box.height*(.56+.19*Math.cos(step*.23)));step++;}
          await page.waitForTimeout(move?16:250);
        }
        const result=await page.evaluate(()=>{
          window.layoutMeasuring=false;
          const frames=window.layoutFrames.slice(1).sort((a,b)=>a-b);
          return {fps:1000*frames.length/frames.reduce((a,b)=>a+b,0),p95ms:frames[Math.floor(frames.length*.95)],over50ms:frames.filter(v=>v>50).length,render:window.tideRenderStats};
        });
        samples.push({name,...result});console.log('LAYOUT_WEB_PROFILE',name,JSON.stringify(result));
      };
      await measure('idle',false);
      await clickGame(220,770,[0,0]); // Rattan lantern string, the most detailed decoration.
      await page.mouse.move(850,450);await page.waitForTimeout(750);
      await measure('drag_preview',true);
      await page.screenshot({path:path.join(output,'layout-performance-preview.png')});
      await page.keyboard.press('Escape');
      assert.deepEqual(errors,[]);
      const name=process.argv.includes('--baseline')?'layout-browser-before.json':'layout-browser-after.json';
      fs.writeFileSync(path.join(work,name),JSON.stringify(samples,null,2));
      if(process.argv.includes('--baseline'))return;
      await clickGame(205,175,[0,0]);
      await page.setViewportSize(wide?{width:1920,height:900}:{width:1440,height:948});
      await page.waitForTimeout(750);
    }
    if(summer){
      await page.setViewportSize({width:1100,height:750});
      await page.waitForTimeout(1000); // Allow Godot's canvas layout to catch up with the resize.
      for(let index=0;index<9;index++){
        await clickGame(55+(index%4)*75,175+Math.floor(index/4)*38,[0,0]);
        if(index===4 || index===6 || index===8)await page.screenshot({path:path.join(output,`summer-shop-${index}.png`)});
        await clickGame(220,642,[0,0]); // Third card: colorful furniture sorted by price.
        await page.keyboard.press('Escape'); // Cancels the pending purchase without spending.
        await page.waitForTimeout(150);
      }
      await clickGame(205,175,[0,0]);
      await page.setViewportSize(wide?{width:1920,height:900}:{width:1440,height:948});
    }
    if(uiText){
      const cdp=await context.newCDPSession(page);
      for(const [width,height,dpr] of [[1100,750,1],[1366,800,1.25]]){
        await page.setViewportSize({width,height});
        await cdp.send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:dpr,mobile:false});
        await page.waitForTimeout(1000);
        const shot=await cdp.send('Page.captureScreenshot',{format:'png',fromSurface:true});
        fs.writeFileSync(path.join(output,`layout-text-${width}-${dpr}.png`),Buffer.from(shot.data,'base64'));
      }
      await clickGame(240,130,[0,0]); // Native-pixel owned list retains selection hitboxes.
      await clickGame(100,210,[0,0]);
      await clickGame(1180,860,[1,1]); // Change selected table color; verify in the saved fixture below.
      const shot=await cdp.send('Page.captureScreenshot',{format:'png',fromSurface:true});
      fs.writeFileSync(path.join(output,'owned-text-125.png'),Buffer.from(shot.data,'base64'));
      await clickGame(90,130,[0,0]);
      await cdp.send('Emulation.clearDeviceMetricsOverride');
      await page.setViewportSize(wide?{width:1920,height:900}:{width:1440,height:948});
      await page.waitForTimeout(750);
    }
    await page.keyboard.down('Alt'); await page.mouse.move(900,470); await page.mouse.down({button:'middle'});
    await page.mouse.move(1090,430,{steps:8});await page.mouse.up({button:'middle'});await page.keyboard.up('Alt');
    await page.mouse.wheel(0,-200);await page.waitForTimeout(500);
    await page.screenshot({path:path.join(output,'web_layout_orbit.png')});
    await page.keyboard.press('f');
    await clickGame(220,386,[0,0]); // Select rug, then cancel without spending.
    await page.mouse.click(850,450,{button:'right'});
    await clickGame(1130,46,[1,0]); // Save layout.
    await clickGame(1310,130,[1,0.5]); // Menu.
    await clickGame(1330,285,[1,0.5]); await clickGame(1330,285,[1,0.5]);
    await clickGame(1300,327,[1,0.5]); // Prep.
    await page.waitForTimeout(4500);
    if(uiText){
      await page.setViewportSize({width:1100,height:750});
      await page.waitForTimeout(750);
      await page.screenshot({path:path.join(output,'web_open_service.png')});
      await page.setViewportSize(wide?{width:1920,height:900}:{width:1440,height:948});
      await page.waitForTimeout(750);
    }
    await clickGame(700,752,[0.5,1]); // Open service.
    await page.waitForTimeout(2500);
    await page.screenshot({path:path.join(output,'web_service.png')});
    if(uiText){
      const cdp=await context.newCDPSession(page);
      const capture=async name=>{
        const shot=await cdp.send('Page.captureScreenshot',{format:'png',fromSurface:true});
        fs.writeFileSync(path.join(output,name+'.png'),Buffer.from(shot.data,'base64'));
      };
      for(const [width,height,dpr] of [[1366,800,1.25],[1100,750,1]]){
        await page.setViewportSize({width,height});
        await cdp.send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:dpr,mobile:false});
        await page.waitForTimeout(750);
        const canvas=await page.locator('#canvas').evaluate(c=>({width:c.width,height:c.height,box:c.getBoundingClientRect().toJSON()}));
        assert.ok(Math.abs(canvas.width-canvas.box.width*dpr)<0.025,'Service UI has no horizontal resampling');
        assert.ok(Math.abs(canvas.height-canvas.box.height*dpr)<0.025,'Service UI has no vertical resampling');
        await capture(`service-text-${width}-${dpr}`);
      }
      await clickGame(196,767,[0.5,1]); // Actual cooking state and its longer action label.
      await capture('service-text-cooking');
      await page.waitForTimeout(3000);
      await capture('service-text-ready'); // Split plating/serving buttons.
      await cdp.send('Emulation.clearDeviceMetricsOverride');
      await page.setViewportSize(wide?{width:1920,height:900}:{width:1440,height:948});
      await page.waitForTimeout(750);
    }
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
    if(uiText)assert.equal(finalSave.furnishings.find(item=>item.uid===1).color,1,'Owned-list selection and furniture button hitboxes survive fractional DPI');
    if(summer)assert.equal(finalSave.furnishings.find(item=>item.uid===1).variant,'summer','Summer furniture survives layout saving and restaurant service');
    if(summer)assert.equal(finalSave.furnishings.find(item=>item.uid===100).color,2,'Soft decoration keeps its palette after layout saving and service');
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
