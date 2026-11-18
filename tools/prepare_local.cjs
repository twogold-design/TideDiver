const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const sourceRoot = path.resolve(__dirname, '..');
const root = process.argv[2] ? path.resolve(process.argv[2]) : sourceRoot;
const bundle = {files:{}, worklets:{}};
for (const name of ['index.wasm', 'index.pck']) {
  const bytes = fs.readFileSync(path.join(root, name));
  const compressed = zlib.gzipSync(bytes, {level:9});
  // A neutral extension avoids hosts auto-decoding .gz before the browser loader.
  fs.writeFileSync(path.join(root, name + '.gz.bin'), compressed);
  bundle.files[name] = {
    size: bytes.length,
    mime: name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream',
    gzip: compressed.toString('base64'),
  };
}
for (const name of ['index.audio.worklet.js', 'index.audio.position.worklet.js']) {
  bundle.worklets[name] = fs.readFileSync(path.join(root, name), 'utf8');
}
// Godot's PWA probe cannot query service workers at a file:// origin.
// Fail visibly on engine upgrades instead of silently shipping a broken loader.
const enginePath = path.join(root, 'index.js');
let engine = fs.readFileSync(enginePath, 'utf8');
function patchEngine(original, replacement, label) {
  if (engine.includes(replacement)) {
    if (engine.split(replacement).length !== 2 || engine.replace(replacement, '').includes(original)) throw new Error(`Duplicate Godot ${label} hook.`);
    return;
  }
  if (engine.split(original).length !== 2) throw new Error(`Godot ${label} changed; review web compatibility.`);
  engine = engine.replace(original, replacement);
}
const hook = 'function _godot_js_pwa_cb(p_update_cb){';
const guarded = hook + 'if(location.protocol==="file:")return;';
patchEngine(hook, guarded, 'PWA callback');
// Godot normally scales an axis-aligned DOM rectangle. The portrait fallback
// rotates the canvas by 90 degrees, so both absolute and relative input need
// the inverse rotation. Keep normal desktop and native landscape input intact.
const positionHook = 'computePosition:function(evt,rect){const canvas=GodotConfig.canvas;const rw=canvas.width/rect.width;const rh=canvas.height/rect.height;const x=(evt.clientX-rect.x)*rw;const y=(evt.clientY-rect.y)*rh;return[x,y]}';
const rotatedPosition = positionHook.replace('{const canvas=', '{if(window.tideMobileLayout&&window.tideMobileLayout.rotated)return window.tideCanvasPoint(evt,rect,GodotConfig.canvas);const canvas=');
patchEngine(positionHook, rotatedPosition, 'canvas input position');
const movementHook = 'const rel_pos_x=evt.movementX*rw;const rel_pos_y=evt.movementY*rh;';
const rotatedMovement = 'const tideRotated=window.tideMobileLayout&&window.tideMobileLayout.rotated;const rel_pos_x=tideRotated?evt.movementY*canvas.width/rect.height:evt.movementX*rw;const rel_pos_y=tideRotated?-evt.movementX*canvas.height/rect.width:evt.movementY*rh;';
patchEngine(movementHook, rotatedMovement, 'canvas relative motion');
// Web music must keep playing while the single-threaded engine rebuilds UI.
// Godot's Sample source already runs on the browser audio thread, but its
// default forward loop uses an ended callback on the main thread. Whole-track
// loops can run natively instead, including across a busy UI frame.
const sampleLoopHook = '_addEndedListener(){if(this._onended!=null)';
const sampleLoopNative = '_addEndedListener(){const tideSample=this.getSample();this._source.loop=tideSample.loopMode==="forward"&&tideSample.loopBegin===0;if(this._onended!=null)';
patchEngine(sampleLoopHook, sampleLoopNative, 'native whole-track sample loop');
// Preserve a Sample's playhead across repeated mute/resume and loop boundaries.
// Recreated sources need their playback rate restored and an offset normalized
// to the native loop; otherwise an elapsed offset beyond the track ends silent.
const sampleRestartHook = 'this._source.start(this.startTime,this.offset+pauseTime);this.isStarted=true}_pause()';
const sampleRestartFixed = 'this._syncPlaybackRate();let tideOffset=this.offset+pauseTime;if(this._source.loop)tideOffset%=this._source.buffer.duration;this._resetSourceStartTime();this._source.start(0,tideOffset);this.isStarted=true}_pause()';
patchEngine(sampleRestartHook, sampleRestartFixed, 'sample resume offset');
const samplePauseHook = '_pause(){if(!this.isStarted){return}this.isPaused=true;this.pauseTime=(GodotAudio.ctx.currentTime-this._sourceStartTime)/this.getPlaybackRate();this._source.stop()}_unpause(){this._restart();this.isPaused=false;this.pauseTime=0}';
const samplePauseFixed = '_pause(){if(!this.isStarted||this.isPaused){return}this.isPaused=true;this.pauseTime+=(GodotAudio.ctx.currentTime-this._sourceStartTime)*this.getPlaybackRate()*this.getPitchScale();this._source.removeEventListener("ended",this._onended);this._source.stop()}_unpause(){if(!this.isPaused){return}this._restart();this.isPaused=false}';
patchEngine(samplePauseHook, samplePauseFixed, 'sample repeated mute');
fs.writeFileSync(enginePath, engine);
fs.writeFileSync(path.join(root, 'local-data.js'), 'window.TIDE_LOCAL_DATA=' + JSON.stringify(bundle) + ';\n');
fs.copyFileSync(path.join(sourceRoot, 'src/web/local-loader.js'), path.join(root, 'local-loader.js'));
console.log('Prepared double-click resources: ' + fs.statSync(path.join(root, 'local-data.js')).size + ' bytes.');
