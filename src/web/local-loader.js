// The file:// entry loads compressed resources through a classic script.
// HTTP/HTTPS continues to use Godot's normal resource loading.
(() => {
  let pending;
  window.tidePrepareLocal = () => {
    if (location.protocol !== 'file:') return Promise.resolve();
    if (pending) return pending;
    pending = new Promise((resolve, reject) => {
      if (typeof DecompressionStream === 'undefined') {
        reject(new Error('请使用新版 Edge / Chrome 打开，或双击 Launch.cmd 启动。'));
        return;
      }
      const script = document.createElement('script');
      script.src = new URL('local-data.js', document.baseURI).href;
      script.onerror = () => reject(new Error('缺少本地资源 local-data.js，请完整解压工程后再打开 index.html。'));
      script.onload = () => {
        try {
          const data = window.TIDE_LOCAL_DATA;
          if (!data?.files || !data?.worklets) throw new Error('本地资源不完整，请重新解压工程。');
          const resources = new Map(Object.entries(data.files).map(([name, value]) => [new URL(name, document.baseURI).href, value]));
          const originalFetch = window.fetch.bind(window);
          window.fetch = (input, options) => {
            const url = new URL(input instanceof Request ? input.url : String(input), document.baseURI).href;
            const entry = resources.get(url);
            if (!entry) return originalFetch(input, options);
            if (!entry.bytes) {
              const binary = atob(entry.gzip);
              entry.bytes = new Uint8Array(binary.length);
              for (let i = 0; i < binary.length; i++) entry.bytes[i] = binary.charCodeAt(i);
              delete entry.gzip;
            }
            const stream = new Blob([entry.bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
            return Promise.resolve(new Response(stream, {status:200, headers:{'Content-Type':entry.mime, 'Content-Length':String(entry.size)}}));
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
          resolve();
        } catch (error) { reject(error); }
      };
      document.head.appendChild(script);
    });
    return pending;
  };
})();
