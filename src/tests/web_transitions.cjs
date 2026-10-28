const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
const work=path.join(path.dirname(root),'.TideDiver-web-work');
process.env.TEMP=path.join(work,'temp'); process.env.TMP=process.env.TEMP;
(async()=>{
  const browser=await chromium.launch({channel:'chrome',headless:true,downloadsPath:path.join(work,'downloads')});
  try {
    const page=await browser.newPage({viewport:{width:1366,height:800},deviceScaleFactor:1});
    const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error'){errors.push(m.text());console.error(m.text());}});
    await page.goto(pathToFileURL(path.join(root,'index.html')).href);
    await page.getByRole('button',{name:'启程 · 开始游戏'}).click();
    const launchAt=Date.now();
    await page.waitForFunction(()=>window.tideGameReady===true,null,{timeout:120000});
    console.log('Ready after',Date.now()-launchAt,'ms');
    await page.waitForTimeout(2500);
    const trace=process.argv.includes('--trace');
    const cdp=await page.context().newCDPSession(page);
    const events=[];
    if(trace){
      cdp.on('Tracing.dataCollected',({value})=>events.push(...value));
      await cdp.send('Tracing.start',{categories:'devtools.timeline,v8,disabled-by-default-devtools.timeline',transferMode:'ReportEvents'});
      await cdp.send('Profiler.enable'); await cdp.send('Profiler.start');
    }
    const click=async(x,y,anchor=[0,.5])=>{
      const b=await page.locator('#canvas').boundingBox();const s=Math.min(b.width/1440,b.height/900);
      await page.mouse.click(b.x+x*s+(b.width-1440*s)*anchor[0],b.y+y*s+(b.height-900*s)*anchor[1]);
    };
    const samples=[];
    const measure=async(name,x,y,anchor=[0,.5])=>{
      await page.evaluate(()=>{
        window.transitionFrames=[];window.transitionRecording=true;
        let last=performance.now();
        const frame=now=>{if(!window.transitionRecording)return;window.transitionFrames.push(now-last);last=now;requestAnimationFrame(frame);};
        requestAnimationFrame(frame);
      });
      await page.waitForTimeout(150); // Keep a pre-click frame so the transition gap is never discarded.
      const clickedAt=Date.now();
      await click(x,y,anchor);
      const clickMs=Date.now()-clickedAt;
      await page.waitForTimeout(5000);
      const result=await page.evaluate(()=>{
        window.transitionRecording=false;
        const frames=window.transitionFrames.slice(1);
        const sorted=[...frames].sort((a,b)=>a-b);
        return {maxMs:Math.max(...frames),p95Ms:sorted[Math.floor(sorted.length*.95)],over100Ms:frames.filter(v=>v>100),render:window.tideRenderStats};
      });
      samples.push({name,clickMs,...result}); console.log(name,JSON.stringify({clickMs,...result}));
      assert.equal(result.render.state,name.startsWith('restaurant')?'restaurant':'dive','The intended scene opened');
      await page.screenshot({path:path.join(work,`transition-${name}.png`)});
    };
    await measure('restaurant-first',240,586);
    await click(106,51,[0,0]); await page.waitForTimeout(1000);
    await measure('restaurant-repeat',240,586);
    await click(106,51,[0,0]); await page.waitForTimeout(1000);
    if(process.argv.includes('--first-site')){
      const site=Number(process.argv[process.argv.indexOf('--first-site')+1]);
      await page.keyboard.press('F1'); await page.waitForTimeout(350);
      await measure('dive-first',890,243+site*66,[.5,.5]);
    } else await measure('dive-first',240,515);
    await page.keyboard.press('p'); await page.waitForTimeout(500);
    await click(720,510,[.5,.5]); await page.waitForTimeout(1000);
    await click(720,639,[.5,.5]); await page.waitForTimeout(500);
    await measure('dive-repeat',240,515);
    if(trace){
      const {profile}=await cdp.send('Profiler.stop');
      fs.writeFileSync(path.join(work,'transition-cpu.json'),JSON.stringify(profile));
      const finished=new Promise(resolve=>cdp.once('Tracing.tracingComplete',resolve));
      await cdp.send('Tracing.end'); await finished;
      fs.writeFileSync(path.join(work,'transition-trace.json'),JSON.stringify(events));
      console.log('Longest tasks',events.filter(e=>e.dur>100000).sort((a,b)=>b.dur-a.dur).slice(0,20).map(e=>({name:e.name,ms:e.dur/1000,args:e.args})));
    }
    if(process.argv.includes('--all-sites')){
      for(let site=0;site<7;site++){
        await page.keyboard.press('F1'); await page.waitForTimeout(350);
        await measure(`site-${site}`,890,243+site*66,[.5,.5]);
      }
    }
    if(!process.argv.includes('--baseline')){
      assert.ok(samples.filter(s=>s.name.startsWith('restaurant')).every(s=>s.maxMs<300),'Restaurant transitions avoid a long freeze');
      assert.ok(samples.filter(s=>!s.name.startsWith('restaurant')).every(s=>s.maxMs<750),'Dive entries avoid multi-second freezes');
    }
    assert.deepEqual(errors,[]);
    fs.writeFileSync(path.join(work,process.argv.includes('--baseline')?'transitions-web-before.json':'transitions-web-after.json'),JSON.stringify(samples,null,2));
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
