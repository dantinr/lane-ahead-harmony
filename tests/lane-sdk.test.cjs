const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const codes = ['NULL','AHEAD','LEFT','AHEAD_LEFT','RIGHT','AHEAD_RIGHT','LU_TURN','LEFT_RIGHT',
  'AHEAD_LEFT_RIGHT','RU_TURN','AHEAD_LU_TURN','AHEAD_RU_TURN','LEFT_LU_TURN','RIGHT_RU_TURN',
  'LEFT_IN_AHEAD','LEFT_IN_LEFT_LU_TURN','RESERVED','AHEAD_LEFT_LU_TURN','RIGHT_RU_TURN_EX',
  'LEFT_RU_TURN','AHEAD_RIGHT_RU_TURN','LEFT_LU_TURN_EX','BUS','EMPTY','VARIABLE','DEDICATED','TIDAL'];
const LaneAction = Object.fromEntries(codes.map((name, index) => ['LANE_ACTION_' + name, index]));
const code = name => LaneAction['LANE_ACTION_' + name];
const { decodeLanes, routePoints } = load('LaneSdkData', { '@amap/amap_lbs_navi': { LaneAction } });
const list = values => values;
const coord = (latitude, longitude) => ({ latitude, longitude });
const a = coord(39.1, 116.1), b = coord(39.2, 116.1), c = coord(39.2, 116.2);
function step(coords, name, icon, lights = 1) {
  return {
    getLength: () => 500, getIconType: () => icon, getTrafficLightCount: () => lights,
    getCoords: () => list(coords),
    getLinks: () => list([{ getRoadName: () => name, getTrafficLights: () => lights > 0, getCoords: () => list(coords) }])
  };
}
test('按左到右解析车道；混合车道仅突出推荐分支，公交/可变/未知类型不猜测', () => {
  const lanes = decodeLanes({ laneCount: 4,
    backgroundLane: Int32Array.from([code('AHEAD_LEFT'),code('BUS'),code('VARIABLE'),250]),
    frontLane: Int32Array.from([code('LEFT'),code('NULL'),code('NULL'),code('AHEAD')]) });
  assert.deepEqual(lanes[0].directions, ['↑','←']);
  assert.deepEqual(lanes[0].recommended, ['←']);
  assert.equal(lanes[1].special, '公交');
  assert.equal(lanes[2].special, '可变');
  assert.equal(lanes[3].special, '未识别');
  assert.deepEqual(lanes[3].recommended, []);
});
test('截断或不合理车道数组不能形成伪造车道', () => {
  assert.deepEqual(decodeLanes(null), []);
  assert.deepEqual(decodeLanes({laneCount: 2, backgroundLane: new Int32Array(1), frontLane: new Int32Array(2)}), []);
  assert.deepEqual(decodeLanes({laneCount: 30, backgroundLane: new Int32Array(30), frontLane: new Int32Array(30)}), []);
});
test('历史匹配包括进口/出口方向和转向，多灯步骤不能学习端点车道', () => {
  const path = (first, next) => ({ getSteps: () => list([first, next]) });
  const original = routePoints(path(step([a,b],'甲',2),step([b,c],'乙',3)));
  assert.equal(original[0].learnable, true);
  assert.deepEqual(original.map(p => p.endMeters), [500,1000]);
  const reverse = routePoints(path(step([c,b],'甲',2),step([b,a],'乙',3)));
  const otherTurn = routePoints(path(step([a,b],'甲',3),step([b,c],'乙',3)));
  assert.notEqual(original[0].key, reverse[0].key);
  assert.notEqual(original[0].key, otherTurn[0].key);
  assert.equal(routePoints(path(step([a,b],'甲',2,2),step([b,c],'乙',3)))[0].learnable, false);
});

test('无红绿灯、标注缺失或相互矛盾时，即使收到车道并连续通过也不保存或复用历史', () => {
  const {LaneHistory,LanePreviewEngine}=load('LanePreview');
  const lanes=decodeLanes({laneCount:1,backgroundLane:Int32Array.from([code('LEFT')]),frontLane:Int32Array.from([code('LEFT')])});
  const cases=[
    {name:'无红绿灯',count:0,signal:false},
    {name:'段计数为零但link有灯',count:0,signal:true},
    {name:'段计数有灯但link无灯',count:1,signal:false},
    {name:'未提供段计数',count:undefined,signal:true},
    {name:'段计数无效',count:NaN,signal:true},
    {name:'段计数为负数',count:-1,signal:true},
    {name:'未提供link标注',count:1,signal:undefined}
  ];
  for(const item of cases) {
    const first=step([a,b],'甲',2);
    const links=first.getLinks();
    const points=routePoints({getSteps:()=>[
      {...first,getTrafficLightCount:()=>item.count,
        getLinks:()=>links.map(link=>({...link,getTrafficLights:()=>item.signal}))},
      step([b,c],'乙',3)
    ]});
    assert.equal(points[0].learnable,false,item.name);
    for(const seeded of [false,true]) {
      const history=new LaneHistory();
      if(seeded)history.remember(points[0].key,lanes,9000);
      const revision=history.revision;
      const engine=new LanePreviewEngine(history);
      engine.setRoute('selected',points);engine.collection.begin(10000,history.count(10000));
      engine.progress('selected',0,50,10000,true);engine.lanes(lanes,10100);
      const state=engine.preview(3,10100);
      assert.equal(state.rows[0].source,'暂无车道数据',item.name);
      assert.equal(state.liveLanes.length,1,item.name);
      assert.equal(engine.collection.state.status,'未保存',item.name);
      assert.equal(engine.collection.state.reason,points[0].unlearnableReason,item.name);
      engine.progress('selected',1,490,12000,true);
      assert.equal(engine.collection.state.confirmed,0,item.name);
      assert.equal(history.revision,revision,item.name);
      assert.equal(history.count(12000),seeded?1:0,item.name);
    }
  }
});

function internalPath(options={}) {
  const junctionEnd=coord(39.2001,116.1002);
  const middle=coord(39.2,116.1002);
  const link=(coords,signal,length,type)=>({getCoords:()=>coords,getTrafficLights:()=>signal,
    getLength:()=>length,getRoadType:()=>type,getRoadName:()=>type===2?'路口内部':'进口道路'});
  const links=[link([a,b],true,460,1),link([b,middle],false,20,2),link([middle,junctionEnd],false,20,2)];
  if(options.ordinary)links[2]=link([middle,junctionEnd],false,20,1);
  if(options.long)links[2]=link([middle,junctionEnd],false,41,2);
  if(options.disconnected)links[2]=link([c,junctionEnd],false,20,2);
  if(options.secondSignal)links[2]=link([middle,junctionEnd],true,20,2);
  if(options.missingGeometry)links[2]=link(null,false,20,2);
  const first={...step([a,b,middle,junctionEnd],'甲',2,options.multi?2:1),getLinks:()=>links};
  const next=step([options.wrongExit?c:junctionEnd,c],'乙',3);
  return {getSteps:()=>[first,next]};
}

test('唯一信号灯后有短且连续的路口内部道路时，允许关联引导点', () => {
  const points=routePoints(internalPath());
  assert.equal(points[0].learnable,true);
  assert.match(points[0].key,/39\.200100,116\.100200/);
});

test('普通道路、超过60米、断开的几何、多灯或缺少出口不能使用内部道路关联', () => {
  for(const option of ['ordinary','long','disconnected','secondSignal','missingGeometry','wrongExit','multi']) {
    assert.equal(routePoints(internalPath({[option]:true}))[0].learnable,false,option);
  }
});

test('直接位于末端的信号灯仍需进出口相连，非法端点不能产生可学习记录', () => {
  for(const nextCoords of [[c,a],[coord(NaN,116.1),c]]) {
    assert.equal(routePoints({getSteps:()=>[step([a,b],'甲',2),step(nextCoords,'乙',3)]})[0].learnable,false);
  }
});

test('短路口内部道路关联仍须进入80米并连续通过，确认后才成为历史', () => {
  const {LanePreviewEngine}=load('LanePreview');
  const points=routePoints(internalPath());const engine=new LanePreviewEngine();
  engine.setRoute('selected',points);engine.collection.begin(10000,0);
  engine.progress('selected',0,100,10000,true);
  const lanes=decodeLanes({laneCount:1,backgroundLane:Int32Array.from([code('LEFT')]),frontLane:Int32Array.from([code('LEFT')])});
  engine.lanes(lanes,10100);assert.equal(engine.collection.state.status,'等待靠近');
  engine.progress('selected',0,50,11000,true);assert.equal(engine.collection.state.status,'待通过确认');
  assert.equal(engine.history.count(11000),0);
  engine.progress('selected',1,490,14000,true);
  assert.equal(engine.collection.state.confirmed,1);
  assert.ok(engine.history.find(points[0].key,14000));
});
