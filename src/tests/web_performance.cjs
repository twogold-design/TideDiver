const {chromium} = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname,'../..');
const work = path.join(path.dirname(root),'.TideDiver-web-work');
process.env.TEMP = path.join(work,'temp'); process.env.TMP = process.env.TEMP;
const baseline = process.argv.includes('--baseline');
(async()=>{
  const browser = await chromium.launch({channel:'chrome',headless:true,downloadsPath:path.join(work,'downloads')});
  try {
    const context = await browser.newContext({viewport:{width:1366,height:800},deviceScaleFactor:2});
    const page = await context.newPage();
    const errors=[]; page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
    await page.goto(pathToFileURL(path.join(root,'index.html')).href);
    await page.getByRole('button',{name:'启程 · 开始游戏'}).click();
    await page.waitForFunction(()=>window.tideGameReady===true,null,{timeout:120000});
    const samples=[];
    async function sample(scene) {
      await page.waitForTimeout(4000);
      const result=await page.evaluate(()=>new Promise(resolve=>{
        const deltas=[]; const start=performance.now(); let previous=start;
        function frame(now) {
          deltas.push(now-previous);previous=now;
          if(now-start<6000){requestAnimationFrame(frame);return;}
          const sorted=deltas.slice(1).sort((a,b)=>a-b);
          const canvas=document.getElementById('canvas');const gl=canvas.getContext('webgl2');
          const ext=gl.getExtension('WEBGL_debug_renderer_info');
          resolve({fps:1000*sorted.length/sorted.reduce((a,b)=>a+b,0),p95ms:sorted[Math.floor(sorted.length*.95)],renderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):'unknown',pixels:[canvas.width,canvas.height],render:window.tideRenderStats||null});
        }
        requestAnimationFrame(frame);
      }));
      samples.push({scene,...result});console.log(scene,JSON.stringify(result));
      if(!baseline){
        assert.ok(result.render,'Render diagnostics available');
        if(scene==='dock'){
          assert.ok(result.render.scale3d<1,'High-DPI ocean buffer is budgeted');
          assert.ok(result.render.pixels3d<=1800000*1.01,'Ocean pixel budget');
        }else{assert.equal(result.render.scale3d,1,'Normal restaurant canvas avoids an unnecessary upscale pass');}
      }
    }
    await sample('dock');
    const box=await page.locator('#canvas').boundingBox();const scale=Math.min(box.width/1440,box.height/900);
    await page.mouse.click(box.x+240*scale,box.y+586*scale+(box.height-900*scale)/2);
    await sample('restaurant');
    assert.deepEqual(errors,[]);
    fs.writeFileSync(path.join(work,baseline?'performance-before.json':'performance-after.json'),JSON.stringify(samples,null,2));
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
