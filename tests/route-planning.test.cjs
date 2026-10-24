const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { Place, decodePlaces, decodeRoutes, AMapRouteService } = load('RoutePlanning');

const origin = new Place('B0001', '起点', '起点地址', '121.4567891,31.200000');
const destination = new Place('B0002', '终点', '终点地址', '121.49,31.23');
const path = (overrides = {}) => ({
  distance: '2300', cost: { duration: '620' },
  steps: [
    { instruction: '沿示例道路向北行驶', road_name: '示例道路', step_distance: '350' },
    { instruction: '向左前方行驶', road_name: '', step_distance: '1950' }
  ], ...overrides
});
const driving = (paths = [path()]) => JSON.stringify({ status: '1', route: { paths } });

test('搜索结果保留地址，过滤不可路由地点和重复结果', () => {
  const poi = { id: 'B001', name: '同名地点', address: '一号路', location: '121.5,31.2' };
  const places = decodePlaces(JSON.stringify({ status: '1', pois: [
    poi, poi, { ...poi, id: 'B002', address: '二号路' },
    { ...poi, location: '' }, { ...poi, location: '181,0' },
    { ...poi, location: ',31.2' }, { ...poi, location: [] }, null
  ] }));
  assert.deepEqual(places.map(x => x.address), ['一号路', '二号路']);
  assert.equal(places[0].location, '121.500000,31.200000');
});

test('路线分段原样保留为规划指引，不推断物理路口或推荐车道', () => {
  const [route] = decodeRoutes(driving(), '终点', 'request-1');
  assert.equal(route.distanceMeters, 2300);
  assert.equal(route.durationSeconds, 620);
  assert.deepEqual(route.steps.map(x => x.distanceMeters), [350, 1950]);
  assert.equal(route.steps[1].instruction, '向左前方行驶');
  assert.equal(route.junctions, undefined);
  assert.ok(route.steps.every(x => x.laneGuidance === undefined));
});

test('每次算路及各备选路线具有独立标识', () => {
  const a = decodeRoutes(driving([path(), path({ distance: '2600' })]), '终点', 'a');
  const b = decodeRoutes(driving(), '终点', 'b');
  assert.equal(new Set([...a, ...b].map(x => x.id)).size, 3);
});

test('缺少耗时不能误报为零分钟', () => {
  const [route] = decodeRoutes(driving([path({ cost: {} })]), '终点', 'a');
  assert.equal(route.durationSeconds, undefined);
});

test('拒绝无效距离和残缺路线，不展示部分解析的错误路线', () => {
  for (const distance of ['', 'NaN', 'Infinity', '-1', null, [], {}, '0']) {
    assert.throws(() => decodeRoutes(driving([path({ distance })]), '终点', 'a'));
  }
  for (const invalid of [null, path({ steps: null }), path({ steps: [null] }),
    path({ steps: [{ instruction: '行驶', step_distance: '-1' }] })]) {
    assert.throws(() => decodeRoutes(driving([invalid]), '终点', 'a'));
  }
  assert.throws(() => decodeRoutes('{"status":"1"}', '终点', 'a'));
  assert.throws(() => decodeRoutes('null', '终点', 'a'));
  assert.deepEqual(decodeRoutes(driving([]), '终点', 'a'), []);
});

test('服务失败说明不回显服务端任意文本或密钥', () => {
  for (const decode of [decodePlaces, body => decodeRoutes(body, '终点', 'a')]) {
    assert.throws(() => decode('secret not json'),
      error => !error.message.includes('secret'));
    assert.throws(() => decode('{"status":"0","infocode":"10001","info":"secret"}'),
      error => /密钥/.test(error.message) && !error.message.includes('secret'));
    assert.throws(() => decode('{"status":"0","infocode":"10003"}'), /次数受限/);
    assert.throws(() => decode('{"status":"0","info":"secret"}'),
      error => !error.message.includes('secret'));
  }
});

test('搜索请求编码中文与特殊字符，限制到所选城市', async () => {
  let requested;
  const service = new AMapRouteService({ get: async url => {
    requested = new URL(url);
    return '{"status":"1","pois":[]}';
  } }, 'a'.repeat(32));
  await service.search(' A&B 大厦 ', ' 上海市 ');
  assert.equal(requested.origin, 'https://restapi.amap.com');
  assert.equal(requested.pathname, '/v5/place/text');
  assert.equal(requested.searchParams.get('keywords'), 'A&B 大厦');
  assert.equal(requested.searchParams.get('region'), '上海市');
  assert.equal(requested.searchParams.get('city_limit'), 'true');
});

test('所选起终点和多路线策略被传给真实驾车接口', async () => {
  let requested;
  const service = new AMapRouteService({ get: async url => {
    requested = new URL(url);
    return driving();
  } }, 'a'.repeat(32));
  const routes = await service.plan(origin, destination);
  assert.equal(requested.pathname, '/v5/direction/driving');
  assert.equal(requested.searchParams.get('origin'), origin.location);
  assert.equal(requested.searchParams.get('destination_id'), destination.id);
  assert.equal(requested.searchParams.get('strategy'), '32');
  assert.equal(requested.searchParams.get('show_fields'), 'cost');
  assert.equal(routes[0].destination, '终点');
});

test('输入无效时不发网络请求', async () => {
  let calls = 0;
  const transport = { get: async () => { calls++; return driving(); } };
  assert.throws(() => new AMapRouteService(transport, ''), /Web 服务 Key/);
  const service = new AMapRouteService(transport, 'a'.repeat(32));
  await assert.rejects(service.search('', '上海市'));
  await assert.rejects(service.search('终点', ''));
  await assert.rejects(service.plan(origin, origin), /相同/);
  assert.equal(calls, 0);
});
