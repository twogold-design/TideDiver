const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname,'../..');
const work = path.join(path.dirname(root),'.TideDiver-web-work');
process.env.TEMP = path.join(work,'temp'); process.env.TMP = process.env.TEMP;
const output = path.join(work,'chrome-text-check');
fs.mkdirSync(output,{recursive:true});
const baseline = process.argv.includes('--baseline');
(async () => {
  const browser = await chromium.launch({channel:'chrome',headless:true,downloadsPath:path.join(work,'downloads')});
  try {
    const context = await browser.newContext({viewport:{width:1366,height:800},deviceScaleFactor:1});
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    const errors = [];
    page.on('pageerror',error=>errors.push(error.message));
    page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
    await page.goto(pathToFileURL(path.join(root,'index.html')).href);
    await page.getByRole('button',{name:'启程 · 开始游戏'}).click();
    await page.waitForFunction(()=>window.tideGameReady === true,null,{timeout:120000});
    const cdp = await context.newCDPSession(page);
    for (const [width,height,dpr] of [[1366,800,1],[1100,750,1],[1366,800,1.25]]) {
      await page.setViewportSize({width,height});
      await cdp.send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:dpr,mobile:false});
      await page.waitForTimeout(1800);
      const box = await page.locator('#canvas').boundingBox();
      const pixels = await page.locator('#canvas').evaluate(c=>[c.width,c.height]);
      const name = `${baseline?'before':'after'}-${width}-${dpr}`;
      console.log(name,JSON.stringify({box,pixels,dpr}));
      if (!baseline) {
        for (const value of [box.x,box.y,box.width,box.height]) {
          assert.ok(Math.abs(value*dpr-Math.round(value*dpr))<0.025,'Canvas must land on physical pixel boundaries');
        }
        assert.ok(Math.abs(box.width*dpr-pixels[0])<0.025,'No horizontal bitmap resampling');
        assert.ok(Math.abs(box.height*dpr-pixels[1])<0.025,'No vertical bitmap resampling');
      }
      // Capture directly so Playwright does not restore the context's original DPR.
      const full = await cdp.send('Page.captureScreenshot',{format:'png',fromSurface:true});
      fs.writeFileSync(path.join(output,name+'.png'),Buffer.from(full.data,'base64'));
      const text = await cdp.send('Page.captureScreenshot',{format:'png',fromSurface:true,clip:{x:box.x+60*box.width/1440,y:box.y+620*box.height/900,width:380*box.width/1440,height:150*box.height/900,scale:1}});
      fs.writeFileSync(path.join(output,name+'-text.png'),Buffer.from(text.data,'base64'));
      if (baseline) break;
    }
    assert.deepEqual(errors,[]);
    console.log(baseline?'Chrome baseline captured.':'PASS: Chrome window text uses aligned pixels at 100% and 125%, with no browser errors.');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
