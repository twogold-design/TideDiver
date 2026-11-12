// A local, static-only preview server for the root web runtime.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const root = path.resolve(__dirname, '..');
const port = Number(process.env.PORT || 8060);
const mime = {'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.otf':'font/otf','.js':'text/javascript; charset=utf-8','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.txt':'text/plain; charset=utf-8','.json':'application/json'};
const publicFiles = new Set(['/index.html','/index.js','/index.wasm','/index.pck','/index.wasm.gz.bin','/index.pck.gz.bin','/index.audio.worklet.js','/index.audio.position.worklet.js','/local-loader.js','/local-data.js','/mobile-controls.js','/mobile-controls.css','/FONT-LICENSE.txt','/THIRD-PARTY-NOTICES.txt']);
if (!fs.existsSync(path.join(root, 'index.html'))) {
  console.error('Web build missing. Run BuildWeb.cmd first.'); process.exit(1);
}
const server = http.createServer((req, res) => {
  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); }
  catch { res.writeHead(400).end(); return; }
  if (pathname === '/') pathname = '/index.html';
  if (!publicFiles.has(pathname)) { res.writeHead(404).end('Not found'); return; }
  const file = path.resolve(root, '.' + (pathname.endsWith('/') ? pathname + 'index.html' : pathname));
  if (!file.startsWith(root + path.sep) || !['GET','HEAD'].includes(req.method)) { res.writeHead(403).end(); return; }
  fs.stat(file, (error, stat) => {
    if (error || !stat.isFile()) { res.writeHead(404).end('Not found'); return; }
    // No COOP/COEP headers: verify compatibility with ordinary contest hosting.
    const etag = `W/"${stat.size.toString(16)}-${Math.trunc(stat.mtimeMs).toString(16)}"`;
    const headers = {'Content-Type':mime[path.extname(file)] || 'application/octet-stream',
      'Cache-Control':'no-cache','ETag':etag,'Vary':'Accept-Encoding','X-Content-Type-Options':'nosniff'};
    if (req.headers['if-none-match'] === etag) { res.writeHead(304,headers).end(); return; }
    // Precompressed binary files must remain byte-identical for DecompressionStream.
    const compress = !file.endsWith('.gz.bin') && stat.size > 1024 && /\bgzip\b/.test(req.headers['accept-encoding'] || '');
    if (compress) headers['Content-Encoding'] = 'gzip';
    else headers['Content-Length'] = stat.size;
    res.writeHead(200,headers);
    if (req.method === 'HEAD') { res.end(); return; }
    const stream = fs.createReadStream(file);
    stream.on('error', () => res.destroy());
    if (compress) stream.pipe(zlib.createGzip()).pipe(res);
    else stream.pipe(res);
  });
});
server.listen(port, '127.0.0.1', () => {
  const url = `http://127.0.0.1:${port}/`;
  console.log('Tide Diver web preview: ' + url);
  if (process.argv.includes('--open')) require('node:child_process').spawn('powershell.exe', ['-NoProfile','-Command',`Start-Process '${url}'`], {windowsHide:true, stdio:'ignore'}).unref();
});
server.on('error', error => { console.error(error.message); process.exitCode = 1; });
