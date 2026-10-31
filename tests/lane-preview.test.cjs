const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { PreviewLane, PreviewPoint, LaneHistory, LanePreviewEngine } = load('LanePreview');
const lanes = [new PreviewLane(['↑', '←'], ['←']), new PreviewLane(['↑'], [])];
const now = new Date(2026, 10, 1, 12).getTime();
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
test('有效车道出现即保存，未通过或未靠近80米也可在下次导航复用', () => {
  const engine = setup();
  engine.progress('selected', 0, 300, now + 100, true);
  engine.lanes(lanes, now + 200);
  assert.ok(engine.history.find('east-left', now + 200));
  assert.equal(engine.collection.state.accepted, 1);
  engine.progress('selected', 0, 100, now + 300, true);
  assert.equal(engine.preview(3, now + 300).rows[0].source, '实时');
  engine.progress('selected', 1, 490, now + 1000, true);
  assert.ok(engine.history.find('east-left', now + 1000));
  const secondTrip = setup(engine.history);
  const row = secondTrip.preview(3, now + 2000).rows[0];
  assert.equal(row.source, '历史参考');
  assert.deepEqual(row.lanes[0].recommended, ['←']);
});
test('多年历史仍可预览多个未来点，满三个月标记待更新且不跨方向复用', () => {
  const history = new LaneHistory();
  const old = new Date(2020, 0, 1).getTime();
  history.remember('east-left', lanes, old);
  history.remember('west-straight', lanes, now - 2000);
  history.remember('south-right', lanes, now - 1000);
  history.remember('west-left', lanes, now);
  const engine = setup(history);
  const rows = engine.preview(3, now).rows;
  assert.deepEqual(rows.map(r => r.source), ['历史参考', '历史参考', '历史参考']);
  assert.deepEqual(rows.map(r => r.needsRefresh), [true, false, false]);
  assert.equal(rows[0].recordedAt, old);
  assert.equal(history.count(now), 4);
  assert.equal(history.refreshDueCount(now), 1);
  const otherDirection = new LanePreviewEngine(history);
  otherDirection.setRoute('other', [new PreviewPoint(0, 400, '乙 → 甲', '右转', 'reverse-right', true)]);
  otherDirection.progress('other', 0, 100, now, true);
  assert.equal(otherDirection.preview(3, now).rows[0].source, '暂无车道数据');
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
test('采到后偏航、弱定位、隐藏、跳段、模拟或结束不抹掉已保存历史', () => {
  for (const action of ['replan', 'hide', 'skip', 'stale', 'simulate', 'finish']) {
    const engine = setup();
    engine.progress('selected', 0, 20, now + 100, true);
    engine.lanes(lanes, now + 200);
    if (action === 'replan') engine.suspend('偏航重算');
    if (action === 'hide') engine.hideLanes();
    if (action === 'finish') engine.finish('导航已结束', now + 300);
    engine.progress('selected', action === 'skip' ? 2 : 1, 300,
      now + (action === 'stale' ? 20000 : 1000), action !== 'simulate');
    assert.ok(engine.history.find('east-left', now + 21000), action);
    assert.equal(engine.history.count(now + 21000), 1, action);
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
test('历史文件拒绝损坏、非法箭头、未来日期，超过500条不挤掉旧记录', () => {
  const history = new LaneHistory();
  for (const bad of ['{', 'null', '{"version":2,"records":[]}',
    JSON.stringify({version: 1, records: [{key:'bad', recordedAt:now, lanes:[{directions:['↑'],recommended:['←'],special:''}]}]})]) {
    assert.equal(history.restore(bad, now), false);
    assert.equal(JSON.parse(history.serialize()).records.length, 0);
  }
  for (let i = 0; i < 510; i++) history.remember('key' + i, lanes, now);
  assert.equal(JSON.parse(history.serialize()).records.length, 510);
  const restored = new LaneHistory();
  assert.equal(restored.restore(history.serialize(), now + 100), true);
  assert.ok(restored.find('key0', now + 100));
  assert.ok(restored.find('key509', now + 100));
  assert.equal(restored.restore(history.serialize(), now - 100), false);
  assert.equal(JSON.parse(restored.serialize()).records.length, 0);
});

test('三个月按日历月计算，跨年、月底和闰年不提前或溢出到下一月', () => {
  for (const [observed, due] of [
    [new Date(2026, 0, 31, 10, 30), new Date(2026, 3, 30, 10, 30)],
    [new Date(2026, 9, 31, 10, 30), new Date(2027, 0, 31, 10, 30)],
    [new Date(2026, 10, 30, 10, 30), new Date(2027, 1, 28, 10, 30)],
    [new Date(2023, 10, 30, 10, 30), new Date(2024, 1, 29, 10, 30)]
  ]) {
    assert.equal(LaneHistory.needsRefresh(observed.getTime(), due.getTime() - 1), false);
    assert.equal(LaneHistory.needsRefresh(observed.getTime(), due.getTime()), true);
    assert.equal(LaneHistory.needsRefresh(observed.getTime(), due.getTime() + 1), true);
  }
});

test('旧版文件中的多年记录完整保留，新增记录不会清理它；重启后仍可使用', () => {
  const old = new Date(2020, 0, 1).getTime();
  const history = new LaneHistory();
  const legacy = JSON.stringify({version: 1, records: [{key: 'old', recordedAt: old, lanes}]});
  assert.equal(history.restore(legacy, now), true);
  history.remember('new', lanes, now);
  const restored = new LaneHistory();
  const later = new Date(2056, 0, 1).getTime();
  assert.equal(restored.restore(history.serialize(), later), true);
  assert.equal(restored.count(later), 2);
  assert.equal(restored.find('old', later).recordedAt, old);
  assert.equal(restored.refreshDueCount(later), 2);
  assert.equal(history.refreshDueCount(now), 1);
});

test('再次导航收到相同的有效车道也会更新观测日期，待更新标记随之清除', () => {
  const history = new LaneHistory();
  history.remember('east-left', lanes, new Date(2020, 0, 1).getTime());
  const engine = setup(history);
  assert.equal(engine.preview(3, now).rows[0].needsRefresh, true);
  engine.lanes(lanes, now + 100);
  assert.equal(history.find('east-left', now + 100).recordedAt, now + 100);
  assert.equal(history.count(now + 100), 1);
  assert.equal(history.refreshDueCount(now + 100), 0);
  const secondTrip = setup(history);
  secondTrip.progress('selected', 0, 100, now + 200, true);
  const row = secondTrip.preview(3, now + 200).rows[0];
  assert.equal(row.source, '历史参考');
  assert.equal(row.needsRefresh, false);
});

test('等红灯时持续匹配的位置使当前车道保持有效，定位中断后撤下', () => {
  const engine = setup();
  engine.lanes(lanes, now + 100);
  for (let i = 1; i <= 20; i++) engine.progress('selected',0,50,now + i * 1000,true);
  assert.equal(engine.preview(3,now + 20000).rows[0].source,'实时');
  assert.equal(engine.preview(3,now + 36000).rows.length,0);
  engine.progress('selected',1,490,now + 37000,true);
  assert.ok(engine.history.find('east-left',now + 37000));
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

test('同一车道结构的推荐位置变化立即更新历史，不等待通过', () => {
  const engine = setup();
  engine.progress('selected',0,50,now+100,true);
  engine.lanes([new PreviewLane(['↑','←'],['←']),new PreviewLane(['↑','←'],[])],now+200);
  const updated = [new PreviewLane(['↑','←'], []),new PreviewLane(['↑','←'],['←'])];
  engine.lanes(updated,now+300);
  assert.equal(engine.preview(3,now+300).rows[0].source,'实时');
  assert.equal(engine.history.revision,2);
  assert.deepEqual(engine.history.find('east-left',now+300).lanes,updated);
  assert.ok(engine.collection.state.events.some(e=>e.code==='recommendation_update'));
  assert.ok(!engine.collection.state.events.some(e=>e.code==='lane_conflict'));
  engine.progress('selected',1,490,now+1000,true);
  assert.deepEqual(engine.history.find('east-left',now+1000).lanes,updated);
  assert.equal(engine.collection.state.accepted,2);
});

test('车道结构相同但推荐转向改变仍有歧义，不能将下一路口的推荐写到当前路口', () => {
  const engine=setup();
  engine.progress('selected',0,30,now+100,true);engine.lanes(lanes,now+200);
  engine.lanes([new PreviewLane(['↑','←'],['↑']),lanes[1]],now+300);
  assert.match(engine.collection.state.lastNotSaved,/推荐转向发生变化/);
  engine.progress('selected',1,490,now+1000,true);
  assert.equal(engine.history.count(now+1000),0);
});

test('同一混合车道的箭头顺序变化不改变结构；车道左右顺序变化仍拒绝学习', () => {
  for (const reorderLanes of [false,true]) {
    const engine=setup();
    engine.progress('selected',0,30,now+100,true);
    engine.lanes(lanes,now+200);
    const updated=[new PreviewLane(['←','↑'],['←']),new PreviewLane(['↑'],[])];
    if(reorderLanes)updated.reverse();
    engine.lanes(updated,now+300);
    engine.progress('selected',1,490,now+1000,true);
    assert.equal(Boolean(engine.history.find('east-left',now+1000)),!reorderLanes);
  }
});

test('车道数量或特殊类型改变仍判冲突，后续推荐刷新不能解除真实冲突', () => {
  for(const changed of [[...lanes,new PreviewLane(['↑'],[])],
    [new PreviewLane(['↑','←'],['←'],'可变'),lanes[1]]]) {
    const engine=setup();
    engine.progress('selected',0,30,now+100,true);engine.lanes(lanes,now+200);
    engine.lanes(changed,now+300);engine.lanes(lanes,now+400);
    engine.progress('selected',1,490,now+1000,true);
    assert.equal(engine.history.count(now+1000),0);
    assert.equal(engine.collection.state.accepted,1);
  }
});

test('推荐更新已保存后不因偏航、隐藏、过期或跳段而丢失', () => {
  for(const kind of ['replan','hide','expired','skip']) {
    const engine=setup();
    engine.progress('selected',0,30,now+100,true);
    engine.lanes([new PreviewLane(['↑','←'],['←']),new PreviewLane(['↑','←'],[])],now+200);
    engine.lanes([new PreviewLane(['↑','←'],[]),new PreviewLane(['↑','←'],['←'])],now+300);
    assert.equal(engine.collection.state.status,'正在保存');
    if(kind==='replan')engine.suspend('偏航重算',now+400);
    if(kind==='hide')engine.hideLanes(now+400);
    engine.progress('selected',kind==='skip'?2:1,300,now+(kind==='expired'?20000:1000),true);
    assert.equal(engine.history.count(now+21000),1,kind);
  }
});

test('重复车道回调和持续位置更新不反复写入或延长历史时间，换路段不误存旧车道', () => {
  const engine=setup();engine.lanes(lanes,now+100);
  const saved=engine.history.find('east-left',now+100).recordedAt;
  for(let i=1;i<=30;i++){
    engine.progress('selected',0,100,now+100+i*50,true);
    engine.lanes(lanes,now+101+i*50);
  }
  assert.equal(engine.history.revision,1);assert.equal(engine.collection.state.accepted,1);
  assert.equal(engine.history.find('east-left',now+2000).recordedAt,saved);
  engine.progress('selected',1,490,now+2100,true);
  assert.equal(engine.history.find('south-right',now+2100),undefined);
  engine.lanes(lanes,now+2200);assert.ok(engine.history.find('south-right',now+2200));
  assert.equal(engine.history.count(now+2200),2);
});

test('无有效路线位置、模拟导航与暂停时收到的车道不会被立即保存', () => {
  for(const kind of ['unmatched','simulated','suspended','stale','backward']){
    const engine=setup();let at=now+200;
    if(kind==='unmatched')engine.progress('other',0,50,now+100,true);
    if(kind==='simulated')engine.progress('selected',0,50,now+100,false);
    if(kind==='suspended')engine.suspend('定位信号弱',now+100);
    if(kind==='stale')at=now+3000;
    if(kind==='backward')at=now-1;
    engine.lanes(lanes,at);assert.equal(engine.history.count(now+3000),0,kind);
    assert.equal(engine.collection.state.accepted,0,kind);
  }
});

test('撤销不存在的历史不改变版本；实际撤销才触发一次文件更新', () => {
  const history=new LaneHistory();
  history.forget('missing');assert.equal(history.revision,0);
  history.remember('a',lanes,now);assert.equal(history.lastChangeWasRemoval,false);
  history.forget('a');assert.equal(history.revision,2);assert.equal(history.lastChangeWasRemoval,true);
  history.forget('a');assert.equal(history.revision,2);
  history.remember('b',lanes,now+1);assert.equal(history.lastChangeWasRemoval,false);
});
