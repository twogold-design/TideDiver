const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const root = path.resolve(__dirname,'../..');
const work = path.join(path.dirname(root),'.'+path.basename(root)+'-web-work');
const output = path.join(work,'marine-browser-check');
fs.mkdirSync(output,{recursive:true});
process.env.TEMP = path.join(work,'temp');
process.env.TMP = process.env.TEMP;

(async()=>{
  const browser = await chromium.launch({channel:process.env.TIDE_BROWSER_CHANNEL || 'msedge',headless:true,args:['--enable-webgl','--ignore-gpu-blocklist']});
  const context = await browser.newContext({viewport:{width:1440,height:948},deviceScaleFactor:1});
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
  const clickGame = async(x,y)=>{
    const box = await page.locator('#canvas').boundingBox();
    const scale = Math.min(box.width/1440,box.height/900);
    await page.mouse.click(box.x+x*scale+(box.width-1440*scale)/2,box.y+y*scale+(box.height-900*scale)/2);
    await page.waitForTimeout(250);
  };
  const screenshot = async(name)=>page.screenshot({path:path.join(output,name+'.png')});
  const airPixels = async()=>{
    const box = await page.locator('#canvas').boundingBox();
    const scale = Math.min(box.width/1440,box.height/900);
    const png = await page.screenshot();
    return page.evaluate(async({data,x,y,width})=>{
      const picture = new Image(); picture.src='data:image/png;base64,'+data; await picture.decode();
      const canvas=document.createElement('canvas');canvas.width=picture.width;canvas.height=picture.height;
      const ctx=canvas.getContext('2d');ctx.drawImage(picture,0,0);
      const pixels=ctx.getImageData(x,y,width,1).data;
      let filled=0;for(let i=0;i<pixels.length;i+=4)if(pixels[i+1]>170&&pixels[i+1]>pixels[i]*1.1&&pixels[i+2]>pixels[i])filled++;
      return filled;
    },{data:png.toString('base64'),x:Math.round(box.x+95*scale+(box.width-1440*scale)/2),y:Math.round(box.y+82*scale+(box.height-900*scale)/2),width:Math.round(210*scale)});
  };
  try{
    await page.goto(pathToFileURL(path.join(root,'index.html')).href);
    await page.getByRole('button',{name:'启程 · 开始游戏'}).click();
    await page.waitForFunction(()=>window.tideGameReady===true,null,{timeout:120000});
    await page.waitForTimeout(1500);
    await page.keyboard.press('F1');await page.waitForTimeout(250);
    await clickGame(500,739);
    await screenshot('gm-infinite-air');
    await clickGame(892,309); // Canyon boat entry between the emergent ridges.
    await page.waitForTimeout(150);
    await screenshot('canyon-boat-entry');
    await page.waitForTimeout(3000);
    await page.waitForFunction(()=>document.pointerLockElement!==null);
    await screenshot('canyon-surface-banks');
    await page.keyboard.press('F1');await page.waitForTimeout(250);
    await clickGame(1067,309); // Direct underwater view along the curved current.
    await page.waitForTimeout(2000);
    await screenshot('canyon-curved-channel');
    await page.waitForTimeout(2500);
    await screenshot('canyon-downstream-drift');
    await page.keyboard.press('F1');await page.waitForTimeout(250);
    await clickGame(1067,507); // Coral reef, direct arrival.
    await page.waitForFunction(()=>document.pointerLockElement!==null);
    await page.waitForTimeout(3500);
    const firstAir=await airPixels();
    await screenshot('coral-and-bubbles');
    await page.waitForTimeout(4500);
    const infiniteAir=await airPixels();
    assert(firstAir>190&&Math.abs(firstAir-infiniteAir)<=2,'The actual rendered air gauge stays full while infinite air is enabled');
    await page.keyboard.press('F1');await page.waitForTimeout(250);
    await clickGame(1067,573); // Jackfish storm.
    await page.waitForTimeout(1800);
    await screenshot('jackfish-forward-orbit');
    await page.keyboard.press('F1');await page.waitForTimeout(250);
    await clickGame(1067,639); // Atoll ecology.
    await page.waitForTimeout(1800);
    await screenshot('atoll-life');
    await page.keyboard.press('F1');await page.waitForTimeout(250);
    await clickGame(500,739); // Disable through the same visible button.
    await screenshot('gm-air-disabled');
    await clickGame(950,739);
    await page.waitForFunction(()=>document.pointerLockElement!==null);
    await page.waitForTimeout(8000);
    const normalAir=await airPixels();
    assert(normalAir<infiniteAir-5,'Disabling infinite air visibly resumes tank consumption');
    await screenshot('normal-air-restored');
    assert.deepEqual(errors,[],'No browser, script or shader errors');
    fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({firstAir,infiniteAir,normalAir,errors},null,2));
    console.log('PASS: real GM air toggle, persistent full gauge, normal consumption restored, canyon boat entry and curved channel, coral/storm/atoll views and bubble rendering.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
