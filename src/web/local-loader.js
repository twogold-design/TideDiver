// Compressed runtime resources for both static HTTP hosting and file:// play.
(() => {
  let pending;
  const report = message => document.dispatchEvent(new CustomEvent('tide-loading', {detail:message}));
  const responseFor = (body, entry) => new Response(body, {status:200, headers:{
    'Content-Type':entry.mime, 'Content-Length':String(entry.size),
  }});
  const unpack = body => body.pipeThrough(new DecompressionStream('gzip'));
  const decodeBase64 = async encoded => {
    if (typeof Uint8Array.fromBase64 === 'function') return Uint8Array.fromBase64(encoded);
    // Bound temporary strings and yield between chunks on older mobile browsers.
    const size = encoded.length / 4 * 3 - (encoded.endsWith('==') ? 2 : encoded.endsWith('=') ? 1 : 0);
    const bytes = new Uint8Array(size);
    const chunk = 262144;
    let offset = 0;
    for (let at = 0; at < encoded.length; at += chunk) {
      const binary = atob(encoded.slice(at, at + chunk));
      for (let index = 0; index < binary.length; index++) bytes[offset++] = binary.charCodeAt(index);
      if (at > 0 && at % (chunk * 4) === 0) await new Promise(resolve => setTimeout(resolve, 0));
    }
    return bytes;
  };
  window.tidePrepareLocal = config => {
    if (pending) return pending;
    const originalFetch = window.fetch.bind(window);
    if (location.protocol !== 'file:') {
      if (typeof DecompressionStream !== 'undefined') {
        const resources = new Map(['index.wasm','index.pck'].map(name => [new URL(name, document.baseURI).href, {
          size:config?.fileSizes?.[name] || 0,
          mime:name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream',
        }]));
        window.fetch = async (input, options) => {
          const url = new URL(input instanceof Request ? input.url : String(input), document.baseURI).href;
          const entry = resources.get(url);
          if (!entry || !entry.size) return originalFetch(input, options);
          let compressed;
          try { compressed = await originalFetch(url + '.gz.bin', options); }
          catch { return originalFetch(input, options); }
          if (!compressed.ok || !compressed.body || (compressed.headers.get('Content-Type') || '').includes('text/html')) {
            return originalFetch(input, options);
          }
          return responseFor(unpack(compressed.body), entry);
        };
      }
      pending = Promise.resolve();
      return pending;
    }
    pending = new Promise((resolve, reject) => {
      if (typeof DecompressionStream === 'undefined') {
        reject(new Error('请使用支持解压功能的新版 Edge / Chrome 打开。'));
        return;
      }
      report('正在读取本地压缩资源…');
      const script = document.createElement('script');
      script.src = new URL('local-data.js', document.baseURI).href;
      script.onerror = () => reject(new Error('缺少本地资源 local-data.js，请完整解压工程后再打开 index.html。'));
      script.onload = () => {
        try {
          const data = window.TIDE_LOCAL_DATA;
          if (!data?.files || !data?.worklets) throw new Error('本地资源不完整，请重新解压工程。');
          const resources = new Map(Object.entries(data.files).map(([name, value]) => [new URL(name, document.baseURI).href, value]));
          window.fetch = async (input, options) => {
            const url = new URL(input instanceof Request ? input.url : String(input), document.baseURI).href;
            const entry = resources.get(url);
            if (!entry) return originalFetch(input, options);
            if (!entry.decoding) {
              entry.decoding = decodeBase64(entry.gzip).then(bytes => {
                delete entry.gzip;
                return bytes;
              });
            }
            const bytes = await entry.decoding;
            return responseFor(unpack(new Blob([bytes]).stream()), entry);
          };
          const worklets = new Map(Object.entries(data.worklets).map(([name, source]) => [new URL(name, document.baseURI).href, 'data:text/javascript;charset=utf-8,' + encodeURIComponent(source)]));
          if (typeof Worklet !== 'undefined') {
            const originalAddModule = Worklet.prototype.addModule;
            Worklet.prototype.addModule = function (url, options) {
              const resolved = new URL(String(url), document.baseURI).href;
              return originalAddModule.call(this, worklets.get(resolved) || url, options);
            };
          }
          delete window.TIDE_LOCAL_DATA;
          script.remove();
          report('正在解压本地资源并启动引擎…');
          resolve();
        } catch (error) { reject(error); }
      };
      document.head.appendChild(script);
    });
    return pending;
  };
})();
