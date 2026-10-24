const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { PreviewLane, PreviewPoint, LaneHistory, LanePreviewEngine } = load('LanePreview');
const lanes = [new PreviewLane(['↑', '←'], ['←']), new PreviewLane(['↑'], [])];
const now = 100000;
function setup(history = new LaneHistory()) {
  const engine = new LanePreviewEngine(history);
  engine.setRoute('selected', [
    new PreviewPoint(0, 400, '甲 → 乙', '左转', 'east-left', true),
    new PreviewPoint(1, 900, '乙 → 丙', '右转', 'south-right', true),
    new PreviewPoint(2, 1300, '丙 → 丁', '继续行驶', 'west-straight', true),
    new PreviewPoint(3, 1800, '丁', '到达终点', 'end', false)
  ]);
  engine.progress('selected', 0, 100, now, true);
  return engine;
}
test('前方 2/3 个引导点距离沿路线累计，不给未知路口编造车道', () => {
  const engine = setup();
  const state = engine.preview(3, now);
  assert.deepEqual(state.rows.map(r => r.distance), [100, 600, 1000]);
  assert.ok(state.rows.every(r => r.lanes.length === 0 && r.source === '暂无车道数据'));
  assert.equal(engine.preview(2, now).rows.length, 2);
  assert.match(state.status, /部分直行路口可能缺失/);
});
test('实时车道只绑定当前合格引导点，未通过前不保存，连续通过后复用历史', () => {
  const engine = setup();
  engine.progress('selected', 0, 50, now + 100, true);
  engine.lanes(lanes, now + 200);
  assert.equal(engine.preview(3, now + 200).rows[0].source, '实时');
  assert.equal(engine.history.find('east-left', now + 200), undefined);
  engine.progress('selected', 1, 490, now + 1000, true);
  assert.ok(engine.history.find('east-left', now + 1000));
  const secondTrip = setup(engine.history);
  const row = secondTrip.preview(3, now + 2000).rows[0];
  assert.equal(row.source, '历史参考');
  assert.deepEqual(row.lanes[0].recommended, ['←']);
});
test('历史数据支持多个未来点，7天过期、不同方向和转向不复用', () => {
  const history = new LaneHistory();
  history.remember('east-left', lanes, now - LaneHistory.MAX_AGE);
  history.remember('west-straight', lanes, now - 2000);
  history.remember('south-right', lanes, now - 1000);
  history.remember('west-left', lanes, now);
  const engine = setup(history);
  assert.deepEqual(engine.preview(3, now).rows.map(r => r.source), ['暂无车道数据', '历史参考', '历史参考']);
});
test('多灯或未绑定回调仅显示当前车道，禁止写入其他引导点', () => {
  const engine = new LanePreviewEngine();
  engine.setRoute('a', [new PreviewPoint(0, 400, '多灯道路', '右转', 'ambiguous', false)]);
  engine.progress('a', 0, 30, now, true);
  engine.lanes(lanes, now + 100);
  const state = engine.preview(3, now + 100);
  assert.equal(state.rows[0].source, '暂无车道数据');
  assert.equal(state.liveLanes.length, 2);
  assert.equal(engine.history.find('ambiguous', now + 100), undefined);
});
test('偏航、弱定位、隐藏车道、跳段或模拟不能提交待保存观测', () => {
  for (const action of ['replan', 'hide', 'skip', 'stale', 'simulate']) {
    const engine = setup();
    engine.progress('selected', 0, 20, now + 100, true);
    engine.lanes(lanes, now + 200);
    if (action === 'replan') engine.suspend('偏航重算');
    if (action === 'hide') engine.hideLanes();
    engine.progress('selected', action === 'skip' ? 2 : 1, 300,
      now + (action === 'stale' ? 20000 : 1000), action !== 'simulate');
    assert.equal(engine.history.find('east-left', now + 21000), undefined, action);
  }
});
test('错误路线、旧位置和非法距离立即清空提示；延迟车道回调不能污染历史', () => {
  const engine = setup();
  engine.lanes(lanes, now + 4000);
  assert.equal(engine.preview(3, now + 4000).rows[0].lanes.length, 0);
  assert.equal(engine.preview(3, now + 16000).rows.length, 0);
  engine.progress('other', 0, 20, now + 17000, true);
  assert.equal(engine.preview(3, now + 17000).rows.length, 0);
  engine.progress('selected', 0, 10000, now + 18000, true);
  assert.equal(engine.preview(3, now + 18000).rows.length, 0);
});
test('同一导航段回调多个车道组时撤销关联和旧历史，保留未关联实时展示', () => {
  const engine = setup();
  engine.history.remember('east-left', lanes, now - 1000);
  engine.progress('selected', 0, 20, now + 100, true);
  engine.lanes(lanes, now + 200);
  engine.lanes([new PreviewLane(['→'], ['→'])], now + 300);
  assert.equal(engine.preview(3, now + 300).rows[0].lanes.length, 0);
  assert.equal(engine.preview(3, now + 300).liveLanes.length, 1);
  engine.progress('selected', 1, 490, now + 1000, true);
  assert.equal(engine.history.find('east-left', now + 1000), undefined);
});
test('历史文件防损坏、非法箭头、未来日期；最多保留500条', () => {
  const history = new LaneHistory();
  for (const bad of ['{', 'null', '{"version":2,"records":[]}',
    JSON.stringify({version: 1, records: [{key:'bad', recordedAt:now, lanes:[{directions:['↑'],recommended:['←'],special:''}]}]})]) {
    history.restore(bad, now);
    assert.equal(JSON.parse(history.serialize()).records.length, 0);
  }
  for (let i = 0; i < 510; i++) history.remember('key' + i, lanes, now);
  assert.equal(JSON.parse(history.serialize()).records.length, 500);
  const restored = new LaneHistory();
  restored.restore(history.serialize(), now + 100);
  assert.ok(restored.find('key509', now + 100));
  restored.restore(history.serialize(), now - 100);
  assert.equal(JSON.parse(restored.serialize()).records.length, 0);
});

test('等红灯时持续匹配的位置使当前车道保持有效，定位中断后撤下', () => {
  const engine = setup();
  engine.lanes(lanes, now + 100);
  for (let i = 1; i <= 20; i++) engine.progress('selected',0,50,now + i * 1000,true);
  assert.equal(engine.preview(3,now + 20000).rows[0].source,'实时');
  assert.equal(engine.preview(3,now + 36000).rows.length,0);
  engine.progress('selected',1,490,now + 37000,true);
  assert.equal(engine.history.find('east-left',now + 37000),undefined);
});

test('同段隐藏后出现另一组车道仍视为歧义，不能误存为同一个路口', () => {
  const engine = setup();
  engine.lanes(lanes,now + 100);
  engine.hideLanes();
  engine.progress('selected',0,30,now + 1000,true);
  engine.lanes([new PreviewLane(['→'],['→'])],now + 1100);
  assert.equal(engine.preview(3,now + 1100).rows[0].source,'暂无车道数据');
  engine.progress('selected',1,490,now + 2000,true);
  assert.equal(engine.history.find('east-left',now + 2000),undefined);
});
