const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { PreviewLane, PreviewPoint, LaneHistory } = load('LanePreview');
const stored = new Map();
global.AppStorage = { get: key => stored.get(key), setOrCreate: (key,value) => stored.set(key,value) };
const lanes = [new PreviewLane(['←'], ['←'])];
function setup() {
  stored.clear();
  const state = { added: 0, removed: 0, saves: 0, diagnosticSaves: 0, failHistory: false, failDiagnostics: false };
  const path = id => ({ getPathid: () => BigInt(id) });
  state.path = path(123);
  state.paths = new Map([[12,state.path]]);
  const navi = {
    getNaviPath: () => state.path, getNaviPaths: () => state.paths,
    addAMapNaviListener(listener) { state.listener = listener; state.added++; },
    removeAMapNaviListener(listener) { assert.equal(listener,state.listener); state.removed++; }
  };
  const { LaneLookAheadSession } = load('LaneLookAheadSession', {
    './LaneHistoryStore': { LaneHistoryStore: class {
      load() { return new LaneHistory(); }
      save(history) {
        state.saves++;
        if (state.failHistory) return false;
        state.history = history.serialize(); return true;
      }
    } },
    './LaneCollectionStore': { LaneCollectionStore: class {
      save(summary) {
        state.diagnosticSaves++;
        if (state.failDiagnostics) return false;
        state.diagnostic = structuredClone(summary); return true;
      }
    } },
    './LaneSdkData': {
      decodeLanes: info => info ? lanes : [],
      routePoints: () => [new PreviewPoint(0,400,'甲 → 乙','左转','point-a',true),
        new PreviewPoint(1,900,'乙 → 丙','右转','point-b',true)]
    }
  });
  state.ends = [];
  state.session = new LaneLookAheadSession(navi, '/private/files', arrived => state.ends.push(arrived));
  state.info = (overrides = {}) => state.listener.onNaviInfoUpdate({
    pathID: 12, mType: 1, mCurSegIndex: 0, mSegRemainDis: 50, ...overrides
  });
  state.preview = () => stored.get('laneAheadLanePreview');
  state.collection = () => stored.get('laneAheadCollection');
  state.pathFactory = path;
  return state;
}
test('只采集选定路线 GPS 导航；连续通过后持久化；退出移除监听和定时器', () => {
  const state = setup();
  try {
    state.info();
    assert.equal(state.saves, 0);
    state.session.start();
    state.info();
    assert.equal(state.preview().rows.length, 2);
    state.listener.showLaneInfo({});
    assert.equal(state.preview().rows[0].source, '实时');
    state.info({mCurSegIndex:1,mSegRemainDis:490});
    assert.equal(state.saves, 1);
    assert.equal(JSON.parse(state.history).records[0].key, 'point-a');
  } finally { state.session.dispose(); }
  assert.equal(state.added, 1);
  assert.equal(state.removed, 1);
  assert.equal(state.preview().rows.length, 0);
  state.session.dispose();
  assert.equal(state.removed, 1);
});

test('导航期间显示采集流程并在结束后保留计数与原因，忽略晚到回调', () => {
  const state = setup();
  try {
    state.session.start(); state.info();
    assert.equal(state.collection().received, 0);
    assert.match(state.collection().reason, /尚未返回/);
    state.listener.showLaneInfo({});
    assert.equal(state.collection().received, 1);
    assert.equal(state.collection().decoded, 1);
    assert.equal(state.collection().status, '待通过确认');
    assert.equal(state.collection().writes, 0);
    state.info({mCurSegIndex:1,mSegRemainDis:490});
    assert.equal(state.collection().confirmed, 1);
    assert.equal(state.collection().writes, 1);
    assert.equal(state.collection().storedCount, 1);
    assert.equal(state.collection().status, '保存成功');
    state.info({mCurSegIndex:1,mSegRemainDis:50});
    state.listener.showLaneInfo({}); state.listener.hideLaneInfo();
    state.session.stop('已到达目的地');
    assert.match(state.diagnostic.reasons.map(r => r.message).join(), /高德已.*隐藏/);
    assert.match(state.diagnostic.lastNotSaved, /高德已.*隐藏/);
    assert.equal(state.diagnostic.status, '采集已结束');
    const final = JSON.stringify(state.diagnostic);
    state.listener.showLaneInfo({}); state.listener.hideLaneInfo(); state.listener.onGpsSignalWeak(true);
    assert.equal(JSON.stringify(state.diagnostic), final);
    assert.ok(state.diagnostic.endedAt > 0);
  } finally { state.session.dispose(); }
});

test('另一类多组车道回调单独计数，不能被误报为从未收到或历史写入成功', () => {
  const state = setup();
  try {
    state.session.start(); state.info();
    state.listener.showLaneInfoWithBytes([], null, null);
    assert.equal(state.collection().received, 1);
    assert.equal(state.collection().alternate, 1);
    assert.equal(state.collection().decoded, 0);
    assert.match(state.collection().lastNotSaved, /多组车道回调/);
    assert.equal(state.collection().writes, 0);
    state.session.stop('导航已结束');
    assert.equal(state.diagnostic.alternate, 1);
  } finally { state.session.dispose(); }
});

test('写入失败不能报告保存成功，重试成功后清除错误并落盘诊断', () => {
  const state = setup();
  try {
    state.session.start(); state.info(); state.listener.showLaneInfo({});
    state.failHistory = true;
    state.info({mCurSegIndex:1,mSegRemainDis:490});
    assert.equal(state.collection().confirmed, 1);
    assert.equal(state.collection().writes, 0);
    assert.equal(state.collection().status, '保存失败');
    assert.match(state.collection().historyWriteError, /写入本机失败/);
    state.failHistory = false;
    state.info({mCurSegIndex:1,mSegRemainDis:480});
    assert.equal(state.collection().writes, 1);
    assert.equal(state.collection().historyWriteError, '');
    assert.equal(state.diagnostic.writes, 1);
  } finally { state.session.dispose(); }
});

test('诊断写入节流，退出强制保存，诊断失败不影响导航及历史写入', () => {
  const state = setup();
  try {
    state.failDiagnostics = true;
    state.session.start();
    assert.match(stored.get('laneAheadCollectionPersistenceError'), /诊断写入失败/);
    const initial = state.diagnosticSaves;
    state.info(); state.listener.showLaneInfo({});
    assert.equal(state.diagnosticSaves, initial);
    state.info({mCurSegIndex:1,mSegRemainDis:490});
    assert.equal(state.collection().writes, 1);
    assert.equal(JSON.parse(state.history).records.length, 1);
    state.failDiagnostics = false;
    state.session.stop('导航已结束');
    assert.equal(stored.get('laneAheadCollectionPersistenceError'), '');
    assert.equal(state.diagnostic.confirmed, 1);
    assert.equal(state.diagnostic.status, '采集已结束');
  } finally { state.session.dispose(); }
});
test('偏航重算、弱信号和模拟信息清空车道，等待新路线或定位后再恢复', () => {
  const state = setup();
  try {
    state.session.start(); state.info(); state.listener.showLaneInfo({});
    state.listener.onReCalculateRouteForYaw();
    state.info(); state.listener.showLaneInfo({});
    assert.equal(state.preview().rows.length, 0);
    state.listener.onUpdateNaviPath(); state.info();
    assert.equal(state.preview().rows[0].source, '暂无车道数据');
    state.listener.onGpsSignalWeak(true); state.info();
    assert.equal(state.preview().rows.length, 0);
    state.listener.onGpsOpenStatus(true); state.info();
    assert.equal(state.preview().rows.length, 0);
    state.listener.onGpsSignalWeak(false); state.info({mType:2});
    assert.equal(state.preview().rows.length, 0);
    state.info();
    assert.equal(state.preview().rows.length, 2);
    assert.equal(state.saves, 0);
  } finally { state.session.dispose(); }
});
test('路线选择键与原生 ID 分别解析，另一条路线延迟回调不能显示或存档', () => {
  const state = setup();
  try {
    state.session.start(); state.info();
    assert.equal(state.preview().rows.length, 2);
    state.paths.set(13,state.pathFactory(999));
    state.info({pathID:13});
    state.listener.showLaneInfo({});
    assert.equal(state.preview().rows.length, 0);
    assert.equal(state.saves, 0);
    state.info({pathID:9999});
    assert.equal(state.preview().rows.length,0);
  } finally { state.session.dispose(); }
});
test('本机历史原子替换写入，写入失败保留原文件且关闭文件', () => {
  let original = 'previous'; let temporary = ''; let closed = 0; let fail = false;
  const { LaneHistoryStore } = load('LaneHistoryStore', { '@kit.CoreFileKit': { fileIo: {
    OpenMode: {CREATE:1, TRUNC:2, READ_WRITE:4},
    openSync(path) { assert.match(path,/\.tmp$/); return {fd:1}; },
    writeSync(_,text) { if (fail) throw Error('storage full'); temporary = text; },
    closeSync() { closed++; },
    renameSync() { original = temporary; },
    statSync() { return {size:original.length}; },
    readTextSync() { return original; }
  } } });
  const store = new LaneHistoryStore('/private/files');
  const history = new LaneHistory();
  history.remember('a',lanes,Date.now());
  assert.equal(store.save(history),true);
  const saved = original;
  fail = true;
  assert.equal(store.clear(),false);
  assert.equal(original,saved);
  assert.equal(closed,2);
  assert.ok(store.load().find('a',Date.now()));
});

test('实际SDK到达/停止事件一次性通知导航历史，退出清理不能覆盖到达', () => {
  for (const arrived of [true, false]) {
    const state = setup();
    state.session.start();
    if (arrived) state.listener.onArriveDestination(); else state.listener.onStopNavi();
    state.listener.onStopNavi(); state.session.dispose();
    assert.deepEqual(state.ends, [arrived]);
  }
});
