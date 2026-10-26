const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const root = path.resolve(__dirname, '..');
const bundle = {files:{}, worklets:{}};
for (const name of ['index.wasm', 'index.pck']) {
  const bytes = fs.readFileSync(path.join(root, name));
  bundle.files[name] = {
    size: bytes.length,
    mime: name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream',
    gzip: zlib.gzipSync(bytes, {level:9}).toString('base64'),
  };
}
for (const name of ['index.audio.worklet.js', 'index.audio.position.worklet.js']) {
  bundle.worklets[name] = fs.readFileSync(path.join(root, name), 'utf8');
}
// Godot's PWA probe cannot query service workers at a file:// origin.
// Fail visibly on engine upgrades instead of silently shipping a broken loader.
const enginePath = path.join(root, 'index.js');
const engine = fs.readFileSync(enginePath, 'utf8');
const hook = 'function _godot_js_pwa_cb(p_update_cb){';
const guarded = hook + 'if(location.protocol==="file:")return;';
if (!engine.includes(hook)) throw new Error('Godot PWA callback changed; review local-file compatibility.');
if (!engine.includes(guarded)) fs.writeFileSync(enginePath, engine.replace(hook, guarded));
fs.writeFileSync(path.join(root, 'local-data.js'), 'window.TIDE_LOCAL_DATA=' + JSON.stringify(bundle) + ';\n');
fs.copyFileSync(path.join(root, 'src/web/local-loader.js'), path.join(root, 'local-loader.js'));
console.log('Prepared double-click resources: ' + fs.statSync(path.join(root, 'local-data.js')).size + ' bytes.');
