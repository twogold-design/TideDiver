(() => {
  'use strict';
  const coarse = matchMedia('(any-pointer: coarse)');
  const forced = new URLSearchParams(location.search).get('touch') === '1';
  const enabled = forced || ((coarse.matches || navigator.maxTouchPoints > 0) && Math.min(screen.width, screen.height) <= 900);
  window.tideMobileEnabled = enabled;
  if (!enabled) return;
  document.documentElement.classList.add('tide-touch');
  const stage = document.getElementById('stage');
  const layer = document.createElement('section');
  layer.id = 'touch-layer';
  layer.hidden = true;
  layer.setAttribute('aria-label', '触屏潜水控制');
  layer.innerHTML = `
    <div id="touch-look" aria-label="在右侧空白处拖动转向"></div>
    <div id="touch-topbar">
      <button type="button" data-action="pause" aria-label="暂停潜水" title="暂停"><span class="tool-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14M16 5v14"/></svg></span></button>
      <button type="button" data-action="bestiary" aria-label="查看海洋图鉴" title="图鉴"><span class="tool-icon"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 6v15M12 6C9 3 5 3 3 4v15c3-1 6-1 9 2 3-3 6-3 9-2V4c-2-1-6-1-9 2Z"/></svg></span></button>
      <button type="button" data-action="tools" aria-label="更多工具" aria-expanded="false" aria-controls="touch-tools" title="更多"><span class="tool-icon">⋯</span></button>
    </div>
    <div id="touch-tools" hidden aria-label="更多游戏工具">
      <button type="button" data-action="help" aria-label="触屏操作说明">操作说明</button>
      <button type="button" data-action="fullscreen" aria-label="切换全屏">全屏显示</button>
    </div>
    <button type="button" id="touch-call-boat" data-action="call_boat" hidden aria-label="呼叫接驳船，返航入库"><span>呼叫接驳船</span><small>返航入库 · 保留全部渔获</small></button>
    <button type="button" id="touch-sketch" data-action="sketch" hidden aria-label="描绘观赏生物轮廓">描绘轮廓</button>
    <div id="touch-joystick" role="application" aria-label="移动摇杆，拖动控制前后左右">
      <span class="stick-ring"></span><span id="touch-stick"></span><span class="stick-caption">移动</span>
    </div>
    <div id="touch-swim">
      <button type="button" data-action="boost" data-hold aria-label="按住加速游动">加速</button>
      <button type="button" data-action="stealth" data-hold aria-label="按住静潜">静潜</button>
    </div>
    <div id="touch-actions">
      <button type="button" data-action="ascend" data-hold aria-label="按住上浮">上浮</button>
      <button type="button" data-action="descend" data-hold aria-label="按住下潜">下潜</button>
      <button type="button" data-action="shoot" class="touch-shoot" aria-label="发射鱼叉">鱼叉</button>
      <button type="button" data-action="knife" aria-label="挥动小刀">小刀</button>
      <button type="button" data-action="interact" class="touch-interact" aria-label="拾取、交互或水面返航">交互</button>
    </div>
    <span id="touch-look-hint">右侧空白处拖动转向</span>
    <div id="touch-entry-note" hidden>正在入水…</div>`;
  stage.appendChild(layer);
  const stick = document.getElementById('touch-stick');
  const joystick = document.getElementById('touch-joystick');
  const topbar = document.getElementById('touch-topbar');
  const entryNote = document.getElementById('touch-entry-note');
  const pointers = new Map();
  const holdActions = new Set(['ascend', 'descend', 'boost', 'stealth']);
  let movePointer = null;
  let lookPointer = null;
  let playable = false;
  let toolsOpen = false;
  let lastMode = '';
  let lastSize = `${innerWidth}:${innerHeight}`;
  let layoutSize = '';

  function updateLayout() {
    const width = innerWidth;
    const height = innerHeight;
    const signature = `${width}:${height}`;
    if (signature === layoutSize) return;
    layoutSize = signature;
    releaseAll();
    const rotated = height > width;
    window.tideMobileLayout = { rotated, width: rotated ? height : width, height: rotated ? width : height };
    const style = document.documentElement.style;
    style.setProperty('--tide-viewport-width', width + 'px');
    style.setProperty('--tide-game-width', window.tideMobileLayout.width + 'px');
    style.setProperty('--tide-game-height', window.tideMobileLayout.height + 'px');
    document.documentElement.classList.toggle('tide-rotated', rotated);
    document.dispatchEvent(new Event('tide-layout'));
  }
  // Inverse of the clockwise fallback rotation, shared by joystick and look.
  window.tideStagePoint = (clientX, clientY) => {
    const rect = stage.getBoundingClientRect();
    return window.tideMobileLayout.rotated
      ? { x: (clientY - rect.top) * stage.clientWidth / rect.height, y: (rect.right - clientX) * stage.clientHeight / rect.width }
      : { x: (clientX - rect.left) * stage.clientWidth / rect.width, y: (clientY - rect.top) * stage.clientHeight / rect.height };
  };
  // The export hook uses the same inverse for Godot GUI and drawing touches.
  window.tideCanvasPoint = (event, rect, canvas) => [
    (event.clientY - rect.top) * canvas.width / rect.height,
    (rect.right - event.clientX) * canvas.height / rect.width,
  ];
  window.tideEnterLandscape = async () => {
    // Invoke synchronously from Start's click, before downloading resources.
    const host = document.documentElement;
    try {
      if (!document.fullscreenElement && !document.webkitFullscreenElement) {
        const request = host.requestFullscreen || host.webkitRequestFullscreen;
        if (request) await request.call(host);
      }
    } catch { /* Embedded browsers can forbid fullscreen; keep the game playable. */ }
    try { if (screen.orientation?.lock) await screen.orientation.lock('landscape'); }
    catch { /* The rotated layout below also works without orientation locking. */ }
    updateLayout();
  };

  function send(action, payload = {}) {
    if (typeof window.tideMobileCommand === 'function') {
      window.tideMobileCommand(action, JSON.stringify(payload));
    }
  }
  function setToolsOpen(open) {
    toolsOpen = open;
    document.getElementById('touch-tools').hidden = !open;
    topbar.querySelector('[data-action="tools"]').setAttribute('aria-expanded', String(open));
  }
  function releasePointer(id) {
    const pointer = pointers.get(id);
    if (!pointer) return;
    pointers.delete(id);
    if (pointer.type === 'move') {
      movePointer = null;
      stick.style.transform = 'translate(-50%, -50%)';
      send('move', { x: 0, y: 0 });
    }
    if (pointer.type === 'look') lookPointer = null;
    if (pointer.action) {
      const held = [...pointers.values()].some(item => item.action === pointer.action);
      if (!held) {
        pointer.button.classList.remove('pressed');
        if (holdActions.has(pointer.action)) send(pointer.action, { pressed: false });
      }
    }
  }
  function releaseAll() {
    for (const id of [...pointers.keys()]) releasePointer(id);
    movePointer = null;
    lookPointer = null;
    stick.style.transform = 'translate(-50%, -50%)';
    send('release');
  }
  function moveStick(event) {
    const bounds = joystick.getBoundingClientRect();
    const radius = joystick.clientWidth * .34;
    const center = window.tideStagePoint(bounds.left + bounds.width / 2, bounds.top + bounds.height / 2);
    const point = window.tideStagePoint(event.clientX, event.clientY);
    let x = (point.x - center.x) / radius;
    let y = (point.y - center.y) / radius;
    const length = Math.hypot(x, y);
    if (length > 1) { x /= length; y /= length; }
    if (length < .10) { x = 0; y = 0; }
    stick.style.transform = `translate(calc(-50% + ${x * radius}px), calc(-50% + ${y * radius}px))`;
    send('move', { x, y });
  }
  function consume(event) {
    event.preventDefault();
    event.stopPropagation();
  }
  layer.addEventListener('pointerdown', event => {
    consume(event);
    if (!playable || event.pointerType === 'mouse') return;
    layer.setPointerCapture(event.pointerId);
    const button = event.target.closest('button[data-action]');
    if (button) {
      const action = button.dataset.action;
      pointers.set(event.pointerId, { type: 'button', action, button });
      button.classList.add('pressed');
      if (action === 'tools') { releaseAll(); setToolsOpen(!toolsOpen); }
      else if (action === 'help') { setToolsOpen(false); releaseAll(); document.getElementById('help').click(); }
      else if (action === 'fullscreen') { setToolsOpen(false); releaseAll(); document.getElementById('fullscreen').click(); }
      else if (holdActions.has(action)) send(action, { pressed: true });
      else { setToolsOpen(false); send(action); if (['pause','bestiary','sketch','call_boat'].includes(action)) releaseAll(); }
      return;
    }
    if (toolsOpen) { setToolsOpen(false); releaseAll(); return; }
    if (event.target.closest('#touch-joystick') && movePointer === null) {
      movePointer = event.pointerId;
      pointers.set(event.pointerId, { type: 'move' });
      moveStick(event);
    } else if (lookPointer === null && window.tideStagePoint(event.clientX, event.clientY).x >= stage.clientWidth * .35) {
      lookPointer = event.pointerId;
      const point = window.tideStagePoint(event.clientX, event.clientY);
      pointers.set(event.pointerId, { type: 'look', x: point.x, y: point.y });
    }
  }, { passive: false });
  layer.addEventListener('pointermove', event => {
    consume(event);
    const pointer = pointers.get(event.pointerId);
    if (!playable || !pointer) return;
    if (pointer.type === 'move') moveStick(event);
    else if (pointer.type === 'look') {
      const point = window.tideStagePoint(event.clientX, event.clientY);
      send('look', { dx: point.x - pointer.x, dy: point.y - pointer.y });
      pointer.x = point.x; pointer.y = point.y;
    }
  }, { passive: false });
  for (const name of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    layer.addEventListener(name, event => { consume(event); releasePointer(event.pointerId); }, { passive: false });
  }
  // No touch on the overlay should synthesize a mouse shot in the underlying canvas.
  for (const name of ['click', 'dblclick', 'contextmenu', 'touchstart', 'touchmove', 'touchend']) {
    layer.addEventListener(name, consume, { passive: false });
  }
  window.addEventListener('blur', releaseAll);
  document.addEventListener('visibilitychange', () => { if (document.hidden) releaseAll(); });
  document.addEventListener('tide-pause', releaseAll);
  document.addEventListener('fullscreenchange', releaseAll);
  document.addEventListener('fullscreenchange', updateLayout);
  document.addEventListener('webkitfullscreenchange', updateLayout);
  window.addEventListener('resize', updateLayout);
  screen.orientation?.addEventListener('change', updateLayout);
  function sync() {
    updateLayout();
    const state = window.tideMobileState || {};
    const ready = window.tideGameReady === true;
    const diving = ready && state.state === 'dive' && !state.bestiaryOpen && !state.gmOpen && !state.layoutMode && !state.blocked;
    const size = `${innerWidth}:${innerHeight}`;
    if (size !== lastSize) { releaseAll(); lastSize = size; }
    const entry = diving && !!state.entryActive;
    const mode = `${diving}:${entry}`;
    if (mode !== lastMode) { releaseAll(); setToolsOpen(false); lastMode = mode; }
    playable = diving && !entry;
    document.getElementById('touch-call-boat').hidden = !playable || !state.canCallBoat;
    document.getElementById('touch-sketch').hidden = !playable || !state.canSketch;
    layer.hidden = !diving;
    layer.classList.toggle('entering', entry);
    layer.setAttribute('aria-hidden', String(!diving));
    entryNote.hidden = !entry;
    topbar.hidden = entry;
    document.documentElement.classList.toggle('is-diving', diving || !!state.sketchActive);
  }
  document.getElementById('status').textContent = '点击开始进入横屏游戏；左侧摇杆移动，右侧拖动转向。';
  sync();
  setInterval(sync, 50);
})();
