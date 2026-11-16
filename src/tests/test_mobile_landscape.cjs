// Browser API boundary tests run the real shell and touch controls with a tiny
// engine stub. Real Godot touch/menu integration remains in web_mobile.cjs.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const source = name => fs.readFileSync(path.join(root, 'src/web', name), 'utf8');
const html = source('shell.html').replaceAll('$GODOT_HEAD_INCLUDE','').replaceAll('$GODOT_URL','engine.js').replaceAll('$GODOT_CONFIG','{}').replaceAll('$GODOT_THREADS_ENABLED','false');
const output = path.join(root,'.runtime','mobile-landscape');
fs.mkdirSync(output,{recursive:true});

(async () => {
  const browser = await chromium.launch({channel:process.env.TIDE_BROWSER_CHANNEL || 'msedge',headless:true});
  const reports = [];
  try {
    for (const mode of ['supported','fullscreen-rejected','lock-rejected','unsupported','desktop']) {
      const mobile = mode !== 'desktop';
      const context = await browser.newContext({viewport:mobile ? {width:390,height:844} : {width:938,height:528},screen:mobile ? {width:390,height:844} : {width:938,height:528},hasTouch:mobile,isMobile:mobile,deviceScaleFactor:2});
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror',error=>errors.push(error.message));
      await page.addInitScript(mode => {
        window.apiCalls = [];
        let full = null;
        Object.defineProperty(document,'fullscreenElement',{configurable:true,get:()=>full});
        if (mode === 'unsupported') {
          Element.prototype.requestFullscreen = undefined;
          Element.prototype.webkitRequestFullscreen = undefined;
          Object.defineProperty(screen,'orientation',{configurable:true,value:undefined});
        } else {
          Element.prototype.requestFullscreen = async function() {
            window.apiCalls.push({name:'fullscreen',tag:this.tagName,gesture:navigator.userActivation.isActive});
            if(mode==='fullscreen-rejected') throw new DOMException('Denied for test','NotAllowedError');
            full=this;
            document.dispatchEvent(new Event('fullscreenchange'));
          };
          document.exitFullscreen = async () => { full=null; document.dispatchEvent(new Event('fullscreenchange')); };
          Object.defineProperty(screen.orientation,'lock',{configurable:true,value:async orientation => {
            window.apiCalls.push({name:'lock',orientation});
            if(mode==='lock-rejected') throw new DOMException('Unsupported for test','NotSupportedError');
          }});
        }
      },mode);
      await page.route('http://tide.test/**', async route => {
        const name = new URL(route.request().url()).pathname.slice(1);
        const bodies = {
          '':html,
          'local-loader.js':'window.tidePrepareLocal = async () => {};',
          'engine.js':`window.Engine=class { static getMissingFeatures(){return []} async startGame(){window.tideGameReady=true;window.tideMobileState={state:'dock'};document.dispatchEvent(new Event('tide-ready'));} };`,
          'mobile-controls.js':source('mobile-controls.js'),
          'mobile-controls.css':source('mobile-controls.css'),
        };
        await route.fulfill({status:200,contentType:name.endsWith('.js')?'application/javascript':name.endsWith('.css')?'text/css':'text/html',body:bodies[name] || ''});
      });
      try {
        await page.goto('http://tide.test/');
        assert.equal(await page.locator('#touch-rotate').count(),0,`${mode}: no rotate prompt is mounted`);
        await page.locator('#start').click();
        await page.waitForFunction(()=>window.tideGameReady===true);
        await page.waitForTimeout(120);
        const calls=await page.evaluate(()=>window.apiCalls);
        if(mode==='desktop') {
          assert.deepEqual(calls,[],'Desktop does not automatically enter fullscreen or lock orientation');
          assert.equal(await page.evaluate(()=>window.tideMobileEnabled),false);
        } else {
          const layout=await page.evaluate(()=>({...window.tideMobileLayout,canvasWidth:document.getElementById('canvas').clientWidth,canvasHeight:document.getElementById('canvas').clientHeight}));
          assert(layout.width>layout.height && layout.canvasWidth>layout.canvasHeight,`${mode}: portrait always presents a logical landscape canvas`);
          assert.equal(layout.rotated,true,`${mode}: portrait viewport uses rotation until actual orientation changes`);
          if(mode!=='unsupported') {
            assert.equal(calls[0]?.name,'fullscreen',`${mode}: fullscreen is requested first`);
            assert.equal(calls[0].gesture,true,`${mode}: fullscreen request retains the Start user gesture`);
            assert.equal(calls[0].tag,'HTML',`${mode}: fullscreen includes the help dialog`);
          }
          if(mode==='supported' || mode==='lock-rejected') assert(calls.some(call=>call.name==='lock' && call.orientation==='landscape'),`${mode}: requests landscape orientation`);
          const mapping=await page.evaluate(()=>window.tideStagePoint(100,200));
          assert(Math.abs(mapping.x-200)<1 && Math.abs(mapping.y-290)<1,`${mode}: portrait physical input maps to logical landscape coordinates`);
          await page.screenshot({path:path.join(output,`${mode}-portrait.png`)});
          // Fixture state exposes the real HTML controls without loading Godot.
          await page.evaluate(()=>{window.tideMobileState={state:'dive'};});
          await page.locator('#touch-layer [data-action="tools"]').tap();
          await page.locator('#touch-layer [data-action="help"]').tap();
          const dialog=page.locator('#instructions');
          await dialog.waitFor({state:'visible'});
          const box=await dialog.boundingBox();
          assert(box.x>=-1 && box.y>=-1 && box.x+box.width<=391 && box.y+box.height<=845,`${mode}: rotated help dialog fits the portrait phone`);
          if(mode==='unsupported') await page.screenshot({path:path.join(output,'portrait-help.png')});
          await dialog.getByRole('button',{name:'知道了'}).tap();
          await dialog.waitFor({state:'hidden'});
          await page.setViewportSize({width:844,height:390});
          await page.waitForTimeout(150);
          assert.equal(await page.evaluate(()=>window.tideMobileLayout.rotated),false,`${mode}: native landscape removes fallback rotation`);
          const landscapeMap=await page.evaluate(()=>window.tideStagePoint(100,200));
          assert(Math.abs(landscapeMap.x-100)<1 && Math.abs(landscapeMap.y-200)<1,`${mode}: landscape input mapping is unchanged`);
          assert.equal(await page.locator('#touch-topbar > button').count(),3,`${mode}: compact top bar has only three controls`);
          await page.locator('#touch-call-boat').waitFor({state:'hidden'});
          await page.evaluate(()=>{window.tideMobileState.canCallBoat=true;});
          await page.locator('#touch-call-boat').waitFor({state:'visible'});
          await page.locator('#touch-layer [data-action="tools"]').tap();
          await page.locator('#touch-tools').waitFor({state:'visible'});
          await page.evaluate(()=>{window.tideMobileState.state='paused';});
          await page.locator('#touch-call-boat').waitFor({state:'hidden'});
          await page.locator('#touch-tools').waitFor({state:'hidden'});
          await page.evaluate(()=>{window.tideMobileState={state:'dive',canCallBoat:true};});
          await page.setViewportSize({width:667,height:300});
          await page.waitForFunction(()=>window.tideMobileLayout.width===667 && window.tideMobileLayout.height===300);
          await page.locator('#touch-call-boat').waitFor({state:'visible'});
          const targets=await page.locator('#touch-topbar > button, #touch-call-boat').evaluateAll(buttons=>buttons.map(button=>{
            const r=button.getBoundingClientRect();return {id:button.id,action:button.dataset.action,x:r.x,y:r.y,width:r.width,height:r.height};
          }));
          for(const target of targets) {
            assert(target.width>=44 && target.height>=44,`${mode}: ${target.action} retains a 44px touch target`);
            assert(target.x>=-1 && target.y>=-1 && target.x+target.width<=668 && target.y+target.height<=301,`${mode}: ${target.action} remains on the 667x300 screen`);
          }
          const bar=targets.filter(target=>target.action!=='call_boat');
          const icons=await page.locator('#touch-topbar .tool-icon').evaluateAll(items=>items.map(item=>({width:item.clientWidth,height:item.clientHeight})));
          assert(icons.every(icon=>icon.width<=30 && icon.height<=30),`${mode}: visible toolbar art stays compact inside accessible touch targets`);
          for(let i=0;i<bar.length;i++) for(let j=i+1;j<bar.length;j++) {
            assert(bar[i].x+bar[i].width<=bar[j].x+.5 || bar[j].x+bar[j].width<=bar[i].x+.5 || bar[i].y+bar[i].height<=bar[j].y+.5 || bar[j].y+bar[j].height<=bar[i].y+.5,`${mode}: compact controls never overlap each other`);
          }
          if(mode==='unsupported') await page.screenshot({path:path.join(output,'compact-tools-and-pickup.png')});
          await page.evaluate(()=>{window.tideMobileState={state:'dock',canCallBoat:false};});
          await page.locator('#touch-call-boat').waitFor({state:'hidden'});
        }
        assert.deepEqual(errors,[],`${mode}: API rejection/absence produces no uncaught script errors`);
        reports.push({mode,calls,errors});
      } finally { await context.close(); }
    }
  } finally {
    fs.writeFileSync(path.join(output,'api-report.json'),JSON.stringify(reports,null,2));
    await browser.close();
  }
  console.log('PASS: mobile fullscreen gesture, landscape lock, rejected/missing API fallback, portrait input mapping, native landscape and desktop preservation.');
})().catch(error=>{console.error(error);process.exitCode=1;});
