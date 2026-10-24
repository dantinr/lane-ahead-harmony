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
