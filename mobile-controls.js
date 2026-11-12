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
      <button type="button" data-action="pause" aria-label="暂停潜水">暂停</button>
      <button type="button" data-action="bestiary" aria-label="查看海洋图鉴">图鉴</button>
      <button type="button" data-action="help" aria-label="触屏操作说明">帮助</button>
      <button type="button" data-action="fullscreen" aria-label="切换全屏">全屏</button>
    </div>
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
  const rotation = document.createElement('section');
  rotation.id = 'touch-rotate';
  rotation.hidden = true;
  rotation.setAttribute('aria-label', '横屏游玩建议');
  rotation.innerHTML = '<div><span aria-hidden="true" class="rotate-icon">↻</span><h2>横过手机，潜得更自在</h2><p>横屏可获得更宽的视野，也方便双手同时游动与转向。</p><button type="button">继续使用竖屏</button></div>';
  stage.appendChild(rotation);
  const stick = document.getElementById('touch-stick');
  const joystick = document.getElementById('touch-joystick');
  const topbar = document.getElementById('touch-topbar');
  const entryNote = document.getElementById('touch-entry-note');
  const pointers = new Map();
  const holdActions = new Set(['ascend', 'descend', 'boost', 'stealth']);
  let movePointer = null;
  let lookPointer = null;
  let playable = false;
  let lastMode = '';
  let portraitDismissed = false;
  let portraitPauseRequested = false;
  let lastPortrait = innerHeight > innerWidth;
  let lastSize = `${innerWidth}:${innerHeight}`;

  function send(action, payload = {}) {
    if (typeof window.tideMobileCommand === 'function') {
      window.tideMobileCommand(action, JSON.stringify(payload));
    }
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
    const radius = bounds.width * .34;
    let x = (event.clientX - bounds.left - bounds.width / 2) / radius;
    let y = (event.clientY - bounds.top - bounds.height / 2) / radius;
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
      if (action === 'help') { releaseAll(); document.getElementById('help').click(); }
      else if (action === 'fullscreen') { releaseAll(); document.getElementById('fullscreen').click(); }
      else if (holdActions.has(action)) send(action, { pressed: true });
      else { send(action); if (action === 'pause' || action === 'bestiary' || action === 'sketch') releaseAll(); }
      return;
    }
    if (event.target.closest('#touch-joystick') && movePointer === null) {
      movePointer = event.pointerId;
      pointers.set(event.pointerId, { type: 'move' });
      moveStick(event);
    } else if (lookPointer === null && event.clientX >= stage.getBoundingClientRect().left + stage.clientWidth * .35) {
      lookPointer = event.pointerId;
      pointers.set(event.pointerId, { type: 'look', x: event.clientX, y: event.clientY });
    }
  }, { passive: false });
  layer.addEventListener('pointermove', event => {
    consume(event);
    const pointer = pointers.get(event.pointerId);
    if (!playable || !pointer) return;
    if (pointer.type === 'move') moveStick(event);
    else if (pointer.type === 'look') {
      send('look', { dx: event.clientX - pointer.x, dy: event.clientY - pointer.y });
      pointer.x = event.clientX; pointer.y = event.clientY;
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
  rotation.querySelector('button').addEventListener('click', () => { portraitDismissed = true; sync(); });
  function sync() {
    const state = window.tideMobileState || {};
    const ready = window.tideGameReady === true;
    const diving = ready && state.state === 'dive' && !state.bestiaryOpen && !state.gmOpen && !state.layoutMode && !state.blocked;
    const portrait = innerHeight > innerWidth;
    const size = `${innerWidth}:${innerHeight}`;
    if (size !== lastSize) { releaseAll(); lastSize = size; }
    if (portrait !== lastPortrait) { releaseAll(); portraitDismissed = false; lastPortrait = portrait; }
    rotation.hidden = !portrait || portraitDismissed;
    if (rotation.hidden) portraitPauseRequested = false;
    else if (diving && !portraitPauseRequested) {
      // Request once before crossing the bridge: it may publish the paused state
      // synchronously or on the next engine frame. Never toggle it back on a poll.
      portraitPauseRequested = true;
      releaseAll();
      send('pause');
    }
    const entry = diving && !!state.entryActive;
    const mode = `${diving}:${entry}:${rotation.hidden}`;
    if (mode !== lastMode) { releaseAll(); lastMode = mode; }
    playable = diving && !entry && rotation.hidden;
    document.getElementById('touch-sketch').hidden = !playable || !state.canSketch;
    layer.hidden = !diving;
    layer.classList.toggle('entering', entry);
    layer.setAttribute('aria-hidden', String(!diving));
    entryNote.hidden = !entry;
    topbar.hidden = entry;
    document.documentElement.classList.toggle('is-diving', diving || !!state.sketchActive);
  }
  document.getElementById('status').textContent = '手机支持触屏游玩，建议横屏；左侧摇杆移动，右侧拖动转向。';
  sync();
  setInterval(sync, 50);
})();
