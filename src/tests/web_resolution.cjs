const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const work = path.join(path.dirname(root), '.TideDiver-web-work');
process.env.TEMP = path.join(work, 'temp');
process.env.TMP = process.env.TEMP;
const baseline = process.argv.includes('--baseline');
const output = path.join(work, 'resolution-check');
fs.mkdirSync(output, {recursive:true});
const measurements = [];
(async () => {
  const browser = await chromium.launch({channel:process.env.TIDE_BROWSER_CHANNEL || 'msedge', headless:true, downloadsPath:path.join(work,'downloads')});
  try {
    const context = await browser.newContext({viewport:{width:1440,height:948},deviceScaleFactor:2});
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    await page.goto(pathToFileURL(path.join(root,'index.html')).href);
    await page.getByRole('button',{name:'启程 · 开始游戏'}).click();
    await page.waitForFunction(()=>window.tideGameReady === true, null, {timeout:120000});
    async function measure(name) {
      await page.waitForTimeout(1500);
      const result = await page.locator('#canvas').evaluate(canvas => {
        const box = canvas.getBoundingClientRect();
        const gl = canvas.getContext('webgl2');
        const stage = document.getElementById('stage').getBoundingClientRect();
        return {css:[box.width,box.height], origin:[box.x,box.y], stage:[stage.x,stage.y,stage.width,stage.height], pixels:[canvas.width,canvas.height], buffer:[gl.drawingBufferWidth,gl.drawingBufferHeight], dpr:devicePixelRatio};
      });
      measurements.push({name,...result});
      console.log(name, JSON.stringify(result));
      if (!baseline) {
        assert.equal(result.pixels[0],Math.round(result.css[0]*result.dpr),name+' native width');
        assert.equal(result.pixels[1],Math.round(result.css[1]*result.dpr),name+' native height');
        assert.deepEqual(result.buffer,result.pixels,name+' WebGL buffer matches canvas');
        for (let i=0;i<2;i++) {
          assert.ok(Math.abs(result.css[i]-result.stage[i+2])*result.dpr<=1,name+' fills stage');
          assert.ok(Math.abs(result.origin[i]-result.stage[i])*result.dpr<=1,name+' no letterbox offset');
        }
      }
      return result;
    }
    await measure('high-dpi-start');
    await page.screenshot({path:path.join(output,baseline?'before.png':'after.png')});
    if (!baseline) {
      for (const [name,width,height] of [['wide-dock',1920,900],['tall-dock',1000,1000],['compact-dock',1100,750]]) {
        await page.setViewportSize({width,height});
        await measure(name);
        await page.screenshot({path:path.join(output,name+'.png')});
      }
      await page.setViewportSize({width:1440,height:948});
      await measure('restore-design-size');
      const box = await page.locator('#canvas').boundingBox();
      await page.mouse.click(box.x+240*box.width/1440,box.y+586*box.height/900);
      await page.waitForTimeout(1500);
      await page.screenshot({path:path.join(output,'restaurant.png')});
      await page.getByRole('button',{name:'全屏',exact:true}).click();
      await page.waitForFunction(()=>document.fullscreenElement !== null);
      await measure('fullscreen');
      // Headless Chromium does not implement the browser's native Escape shortcut.
      await page.evaluate(()=>document.exitFullscreen());
      await page.waitForFunction(()=>document.fullscreenElement === null);
      await page.setViewportSize({width:1100,height:750});
      await measure('resize');
      const cdp = await context.newCDPSession(page);
      await cdp.send('Emulation.setDeviceMetricsOverride',{width:1100,height:750,deviceScaleFactor:1.25,mobile:false});
      await measure('screen-scale-change');
      await cdp.send('Emulation.setDeviceMetricsOverride',{width:2560,height:1440,deviceScaleFactor:1,mobile:false});
      await measure('large-desktop');
      const shot = await cdp.send('Page.captureScreenshot',{format:'png',fromSurface:true});
      fs.writeFileSync(path.join(output,'wide-restaurant.png'),Buffer.from(shot.data,'base64'));
    }
    assert.deepEqual(errors,[],'No rendering errors');
    fs.writeFileSync(path.join(output,baseline?'before.json':'after.json'),JSON.stringify(measurements,null,2));
    console.log(JSON.stringify(measurements));
    console.log(baseline?'Baseline captured.':'PASS: native canvas and WebGL resolution, fullscreen, window resize and screen scaling.');
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
