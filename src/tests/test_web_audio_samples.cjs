// Exercise the actual exported SampleNode, including the exporter's audio fixes.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../..');
const engine = fs.readFileSync(path.join(root, 'index.js'), 'utf8');
const marker = 'SampleNode:class SampleNode{';
const beginning = engine.indexOf(marker);
const end = engine.indexOf(',deleteSampleNode:', beginning);
assert(beginning >= 0 && end > beginning, 'Export contains the real SampleNode class');
const classSource = engine.slice(beginning + 'SampleNode:'.length, end);
const sources = [];
const endedTasks = [];
const errors = [];
const samples = new Map();
const bus = {};

class FakeSource {
  constructor() {
    this.buffer = null;
    this.loop = false;
    this.playbackRate = { value: 1 };
    this.listeners = new Set();
    this.connections = [];
    this.starts = [];
    this.stops = 0;
    sources.push(this);
  }
  connect(destination) { this.connections.push(destination); return destination; }
  disconnect() { this.connections.length = 0; }
  addEventListener(type, listener) { assert.equal(type, 'ended'); this.listeners.add(listener); }
  removeEventListener(type, listener) { assert.equal(type, 'ended'); this.listeners.delete(listener); }
  start(...arguments_) { this.starts.push(arguments_); }
  stop() {
    this.stops++;
    // Audio completion is asynchronous. Resolve listeners at event-dispatch
    // time, matching a real EventTarget after a rapid pause/resume or cancel.
    endedTasks.push(() => { for (const listener of this.listeners) listener({ type: 'ended' }); });
  }
}

class FakeWorklet {
  constructor() {
    this.port = { onmessage: null, postMessage() {} };
    this.parameters = new Map([['reset', { setValueAtTime() {} }]]);
  }
  disconnect() {}
}

const GodotAudio = {
  ctx: { currentTime: 0, createBufferSource: () => new FakeSource() },
  sampleNodes: new Map(),
  audioPositionWorkletPromise: Promise.resolve(),
  audioPositionWorkletNodes: [],
  MAX_VOLUME_CHANNELS: 6,
  Sample: { getSample: id => samples.get(id) },
  Bus: { getBus: () => bus },
  SampleNodeBus: {
    create: () => ({ getInputNode: () => ({}), setVolume() {}, clear() {} }),
  },
  deleteSampleNode(id) { this.sampleNodes.delete(id); },
};
GodotAudio.SampleNode = vm.runInNewContext(`(${classSource})`, {
  GodotAudio,
  GodotRuntime: { error: error => errors.push(error) },
  AudioWorkletNode: FakeWorklet,
});

let serial = 0;
async function makeSample({ mode = 'forward', begin = 0, duration = 10, offset = 0, rate = 1, pitch = 1 } = {}) {
  const id = String(++serial);
  samples.set(id, {
    loopMode: mode, loopBegin: begin, loopEnd: duration, sampleRate: 48000,
    getAudioBuffer: () => ({ duration }),
  });
  const node = GodotAudio.SampleNode.create({ id, streamObjectId: id, busIndex: 0 }, {
    start: false, offset, playbackRate: rate, pitchScale: pitch, volume: [1, 1, 1, 1, 1, 1],
  });
  await Promise.resolve();
  await Promise.resolve();
  node.start();
  return node;
}

function flushEnded() { while (endedTasks.length) endedTasks.shift()(); }
function close(left, right, message) { assert(Math.abs(left - right) < 1e-9, message); }

(async () => {
  const music = await makeSample({ offset: 2, rate: 1.25, pitch: .8 });
  assert.equal(music.getOutputNode().loop, true, 'Whole-track forward music uses the browser audio loop');
  close(music.getOutputNode().playbackRate.value, 1, 'Initial playback applies rate and pitch');
  GodotAudio.ctx.currentTime = 3;
  const first = music.getOutputNode();
  music.pause(true);
  close(music.pauseTime, 3, 'First pause records elapsed audio, including playback rate and pitch');
  assert.equal(first.listeners.size, 0, 'Pause removes the old ended handler before stopping');
  assert.equal(first.stops, 1);
  const countAtPause = sources.length;
  GodotAudio.ctx.currentTime = 9;
  music.pause(true);
  assert.equal(first.stops, 1, 'Repeated pause does not stop again');
  assert.equal(sources.length, countAtPause, 'Repeated pause does not create a source');
  close(music.pauseTime, 3, 'Time spent muted is not accumulated');
  music.pause(false);
  const second = music.getOutputNode();
  assert.notEqual(second, first, 'Resume creates exactly one replacement source');
  close(second.starts[0][1], 5, 'Resume continues from initial offset plus elapsed audio');
  close(second.playbackRate.value, 1, 'Replacement source restores playback rate and pitch');
  assert.equal(second.loop, true, 'Replacement source retains native looping');
  const countAtResume = sources.length;
  music.pause(false);
  assert.equal(sources.length, countAtResume, 'Repeated unpause does not restart playback');
  flushEnded();
  assert.equal(music.getOutputNode(), second, 'A delayed old ended event cannot restart the resumed music');

  // Change speed, play across several complete loops, and mute again. The
  // second resume must retain earlier played time and normalize to the track.
  music.setPlaybackRate(2);
  music.setPitchScale(.75);
  GodotAudio.ctx.currentTime = 26;
  music.pause(true);
  close(music.pauseTime, 28.5, 'A second pause accumulates prior time plus elapsed audio at the new speed');
  GodotAudio.ctx.currentTime = 50;
  music.pause(false);
  const third = music.getOutputNode();
  close(third.starts[0][1], .5, 'Resume wraps an elapsed offset spanning multiple complete loops');
  close(third.playbackRate.value, 1.5, 'Resume preserves changed playback rate and pitch');
  flushEnded();
  assert.equal(music.getOutputNode(), third, 'Old stopped sources cannot replace the latest playback');

  GodotAudio.ctx.currentTime = 51;
  music.pause(true);
  music.pause(false);
  const immediate = music.getOutputNode();
  flushEnded();
  assert.equal(music.getOutputNode(), immediate, 'Immediate mute cancellation does not race an old ended callback');
  close(immediate.starts[0][1], 2, 'Immediate mute cancellation retains all previous elapsed audio');
  music.pause(true);
  music.stop();
  const sourceCountAtCancel = sources.length;
  flushEnded();
  assert.equal(music.getOutputNode(), null, 'Cancel while muted fully releases playback');
  assert.equal(sources.length, sourceCountAtCancel, 'Ended events cannot resurrect canceled music');
  assert.equal(GodotAudio.sampleNodes.has(music.id), false, 'Canceled playback leaves the sample registry');

  for (const options of [{ mode: 'disabled' }, { mode: 'forward', begin: 1 }, { mode: 'backward' }]) {
    const node = await makeSample(options);
    assert.equal(node.getOutputNode().loop, false, `${options.mode} with begin ${options.begin || 0} does not become a whole-track native loop`);
    node.stop();
  }
  flushEnded();
  assert.deepEqual(errors, [], 'No async position-worklet errors');
  console.log('PASS: exported native music loops, non-looping effects, repeated mute/resume, multi-loop offsets, playback speed, and delayed ended/cancel races.');
})().catch(error => { console.error(error); process.exitCode = 1; });
