const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { LaneCollection, restoreCollection } = load('LaneCollection');
const { LanePreviewEngine, PreviewPoint, PreviewLane } = load('LanePreview');
const now = 100000;
const lanes = [new PreviewLane(['↑', '←'], ['←'])];
function engine(eligible = true, reason = '') {
  const result = new LanePreviewEngine();
  result.collection.begin(now, 0);
  result.setRoute('private-route-id', [
    new PreviewPoint(0, 400, '不可写入诊断的道路名称', '左转', '39.91,116.31', eligible, reason),
    new PreviewPoint(1, 900, '下一路段', '右转', 'private-key', true)
  ]);
  result.progress('private-route-id', 0, 50, now, true);
  return result;
}

test('明确区分未收到、空数据与立即关联采集，内存采集不冒充写入且诊断脱敏', () => {
  const e = engine();
  assert.match(e.collection.state.reason, /尚未返回/);
  e.lanes([], now + 10);
  assert.match(e.collection.state.lastNotSaved, /为空或不完整/);
  e.progress('private-route-id', 0, 100, now + 20, true);
  e.lanes(lanes, now + 30);
  assert.equal(e.collection.state.status, '正在保存');
  assert.equal(e.collection.state.accepted, 1);
  e.progress('private-route-id', 0, 50, now + 40, true);
  assert.equal(e.collection.state.accepted, 1);
  e.progress('private-route-id', 1, 490, now + 100, true);
  assert.equal(e.collection.state.accepted, 1);
  assert.equal(e.collection.state.writes, 0);
  assert.equal(e.collection.state.received, 2);
  assert.equal(e.collection.state.decoded, 1);
  assert.doesNotMatch(JSON.stringify(e.collection.state), /private-|39\.91|116\.31|道路名称/);
});

test('多灯与失效位置不采集；已采集后隐藏和位置间隔不删除，冲突会撤销', () => {
  const ambiguous = engine(false, '本路段包含多个信号灯，无法确定车道对应路口');
  ambiguous.lanes(lanes, now + 10);
  assert.match(ambiguous.collection.state.lastNotSaved, /多个信号灯/);
  for (const kind of ['hide', 'conflict', 'stale', 'delayed-lanes']) {
    const e = engine();
    if (kind === 'delayed-lanes') {
      e.lanes(lanes, now + 3000);
      assert.match(e.collection.state.lastNotSaved, /2.5 秒/);
    } else {
      e.lanes(lanes, now + 10);
      if (kind === 'hide') {
        e.hideLanes(now + 20);
        assert.match(e.collection.state.reason, /高德已.*隐藏/);
      } else if (kind === 'conflict') {
        e.lanes([new PreviewLane(['→'], ['→'])], now + 20);
        assert.match(e.collection.state.lastNotSaved, /不同车道组/);
      } else {
        e.progress('private-route-id', 1, 490, now + 6000, true);
      }
    }
    assert.equal(e.collection.state.accepted, kind === 'delayed-lanes' ? 0 : 1, kind);
    assert.equal(e.history.count(now + 6000), ['hide','stale'].includes(kind) ? 1 : 0, kind);
  }
});

test('导航结束无需越点且保留已采集历史，定位超时仍可诊断', () => {
  const e = engine();
  e.lanes(lanes, now + 10);
  e.finish('导航已结束', now + 20);
  assert.ok(!e.collection.state.events.some(event=>event.code==='ended_before_crossing'));
  assert.equal(e.collection.state.status, '采集已结束');
  assert.equal(e.history.count(now + 20), 1);
  const stale = engine();
  stale.lanes(lanes, now + 10);
  stale.preview(3, now + 16000);
  assert.match(stale.collection.state.lastNotSaved, /定位超过 15 秒/);
});

test('连续相同原因不刷屏，事件与原因有界，快照和恢复不共享内存', () => {
  const collection = new LaneCollection();
  collection.begin(now, 4);
  for (let i = 0; i < 100; i++) collection.report('empty', '等待车道', '未收到车道', now + i, true);
  assert.equal(collection.state.reasons[0].count, 1);
  for (let i = 0; i < 100; i++) collection.report('reason-' + i, '未保存', '原因' + i, now + i, true);
  assert.equal(collection.state.events.length, 60);
  assert.equal(collection.state.reasons.length, 40);
  const snapshot = collection.snapshot();
  collection.end('已结束', now + 1000);
  assert.equal(snapshot.endedAt, 0);
  assert.deepEqual(restoreCollection(JSON.stringify(snapshot)), snapshot);
  for (const text of ['{', 'null', '{}', '{"version":3}',
    JSON.stringify({...snapshot, writes: -1}), JSON.stringify({...snapshot, events: [null]}),
    JSON.stringify({...snapshot, accepted: -1}),JSON.stringify({...snapshot, accepted: undefined}),
    JSON.stringify({...snapshot, reasons: [{message:'a',count:0}]}), 'x'.repeat(100001)]) {
    assert.equal(restoreCollection(text).startedAt, 0);
  }
});

test('兼容旧版通过确认摘要但不将其伪装为新版即时采集次数', () => {
  const collection=new LaneCollection();collection.begin(now,1);
  const old={...collection.snapshot(),version:1,confirmed:3,writes:2};delete old.accepted;
  const restored=restoreCollection(JSON.stringify(old));
  assert.equal(restored.version,1);assert.equal(restored.confirmed,3);assert.equal(restored.accepted,0);
  collection.accepted(now+10);collection.persisted(now+20,2);
  const current=restoreCollection(JSON.stringify(collection.snapshot()));
  assert.equal(current.version,2);assert.equal(current.accepted,1);assert.equal(current.confirmed,0);
  assert.match(current.events.find(e=>e.code==='saved').message,/已关联/);
});

test('诊断原子写入，失败不替换原摘要，诊断文件独立于车道历史', () => {
  let original = ''; let temporary = ''; let closed = 0; let fail = false;
  const { LaneCollectionStore } = load('LaneCollectionStore', { '@kit.CoreFileKit': { fileIo: {
    OpenMode: {CREATE:1, TRUNC:2, READ_WRITE:4},
    openSync(path) { assert.match(path, /lane-collection-v1\.json\.tmp$/); return {fd:1}; },
    writeSync(_, text) { if (fail) throw Error('full'); temporary = text; },
    closeSync() { closed++; }, renameSync() { original = temporary; },
    statSync() { return {size: original.length}; }, readTextSync() { return original; }
  } } });
  const store = new LaneCollectionStore('/private/files');
  const collection = new LaneCollection(); collection.begin(now, 0);
  assert.equal(store.save(collection.snapshot()), true);
  const before = original;
  fail = true; collection.end('结束', now + 1);
  assert.equal(store.save(collection.snapshot()), false);
  assert.equal(original, before);
  assert.equal(closed, 2);
  assert.equal(store.load().startedAt, now);
});
