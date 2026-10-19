// Execute the same pure .ets sources used by the app. Hvigor separately checks ArkTS compatibility.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const assert = require('node:assert/strict');
const sdkHome = process.env.DEVECO_SDK_HOME;
if (!sdkHome) throw new Error('请通过 scripts/build.ps1 运行测试，以定位内置 SDK');
const ts = require(path.join(sdkHome, 'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const sourceDir = path.join(__dirname, '../entry/src/main/ets/navigation');
const cache = new Map();
function load(name) {
  if (cache.has(name)) return cache.get(name);
  const filename = path.join(sourceDir, name + '.ets');
  const js = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const mod = { exports: {} };
  vm.runInThisContext('(function(require, module, exports) {' + js + '\n})', { filename })(
    (ref) => load(ref.replace('./', '')), mod, mod.exports);
  cache.set(name, mod.exports);
  return mod.exports;
}
const { Lane, Junction, RouteSnapshot, RouteProgress, LookAheadEngine, PreviewStatus, Turn } = load('Guidance');
const { createDemoRoute } = load('DemoRoute');
const engine = new LookAheadEngine();
const route = createDemoRoute();
const preview = (meters, count = 3) => engine.preview(route, new RouteProgress(route.id, meters), count);

test('三个物理路口各自保留距离、转向与车道推荐', () => {
  const state = preview(100);
  assert.deepEqual(state.upcoming.map(x => x.remainingMeters), [250, 580, 1060]);
  assert.deepEqual(state.upcoming.map(x => x.junction.turn), [Turn.STRAIGHT, Turn.LEFT, Turn.RIGHT]);
  assert.deepEqual(state.upcoming.map(x => x.junction.laneGuidance.lanes.length), [4, 4, 3]);
  const mixed = state.upcoming[1].junction.laneGuidance.lanes[1];
  assert.deepEqual(mixed.directions, [Turn.LEFT, Turn.STRAIGHT]);
  assert.deepEqual(mixed.recommendedDirections, [Turn.LEFT]);
});
test('驶过路口的边界立即切换为后续三个路口', () => {
  assert.equal(preview(349).upcoming[0].junction.id, 'demo-1');
  assert.deepEqual(preview(350).upcoming.map(x => x.junction.id), ['demo-2', 'demo-3', 'demo-4']);
});
test('缺少车道信息时保留路口，不补造车道', () => {
  const missing = createDemoRoute(true);
  const state = engine.preview(missing, new RouteProgress(missing.id, 0));
  assert.equal(state.upcoming.length, 3);
  assert.equal(state.upcoming[1].junction.laneGuidance, undefined);
});
test('重规划后旧路线的进度不能匹配新路线', () => {
  const state = engine.preview(route, new RouteProgress('stale-route', 100));
  assert.equal(state.status, PreviewStatus.ROUTE_MISMATCH);
  assert.deepEqual(state.upcoming, []);
});
test('可以只显示两个路口，并验证数量范围', () => {
  assert.equal(preview(0, 2).upcoming.length, 2);
  for (const count of [0, 4, 2.5, NaN]) assert.throws(() => preview(0, count));
});
test('最后一个路口后仍有路程，不能提前显示到达', () => {
  const state = preview(2020);
  assert.equal(state.status, PreviewStatus.ACTIVE);
  assert.equal(state.remainingRouteMeters, 280);
  assert.deepEqual(state.upcoming, []);
});
test('到达终点及越过终点时剩余距离归零', () => {
  for (const meters of [2300, 2500]) {
    assert.equal(preview(meters).status, PreviewStatus.ARRIVED);
    assert.equal(preview(meters).remainingRouteMeters, 0);
  }
});
test('拒绝不属于车道允许方向的推荐', () => {
  assert.throws(() => new Lane([Turn.LEFT], [Turn.RIGHT]));
  assert.throws(() => new Lane([]));
});
test('拒绝重复、乱序以及超出路线的路口', () => {
  const a = new Junction('a', 100, 'A', Turn.LEFT, undefined);
  const b = new Junction('b', 200, 'B', Turn.RIGHT, undefined);
  for (const junctions of [[b, a], [a, a], [b]]) {
    assert.throws(() => new RouteSnapshot('r', '终点', 150, junctions));
  }
});
test('拒绝 NaN、无穷以及负数距离', () => {
  for (const meters of [NaN, Infinity, -1]) {
    assert.throws(() => new RouteProgress('r', meters));
    assert.throws(() => new Junction('a', meters, 'A', Turn.LEFT, undefined));
  }
  assert.throws(() => new RouteSnapshot('r', '终点', 0, []));
});
