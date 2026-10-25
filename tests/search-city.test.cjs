const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { SearchCity } = load('SearchCity');
const { decodeCity, AMapRouteService } = load('RoutePlanning');
const reverse = component => JSON.stringify({status:'1',regeocode:{addressComponent:component}});
const deferred = () => { let resolve; const promise = new Promise(r => {resolve = r;}); return {promise,resolve}; };

test('城市解析支持普通城市和四个直辖市的空 city 字段，不将省份当作当前城市', () => {
  assert.equal(decodeCity(reverse({city:' 廊坊市 ', province:'河北省'})), '廊坊市');
  for (const province of ['北京市','上海市','天津市','重庆市']) {
    assert.equal(decodeCity(reverse({city:[],province})), province);
    assert.equal(decodeCity(reverse({city:'',province})), province);
  }
  for (const body of ['null', '{broken', reverse({city:[],province:'河北省'}), reverse({}),
    JSON.stringify({status:'1'}), JSON.stringify({status:'0',info:'secret'})]) {
    assert.throws(() => decodeCity(body), error => !error.message.includes('secret'));
  }
});

test('当前位置查询经度在前并限制小数位，不接受无效位置；后续搜索限制到识别城市', async () => {
  const requests = [];
  const service = new AMapRouteService({get: async url => {
    const request = new URL(url); requests.push(request);
    return request.pathname.endsWith('/regeo') ? reverse({city:[],province:'北京市'}) : '{"status":"1","pois":[]}';
  }}, 'a'.repeat(32));
  const city = await service.cityAt(116.48088123, 39.98941056);
  assert.equal(requests[0].pathname, '/v3/geocode/regeo');
  assert.equal(requests[0].searchParams.get('location'), '116.480881,39.989411');
  assert.equal(requests[0].searchParams.get('extensions'), 'base');
  await service.search('图书馆', city);
  assert.equal(requests[1].searchParams.get('region'), '北京市');
  assert.equal(requests[1].searchParams.get('city_limit'), 'true');
  for (const args of [[0,0],[181,39],[116,91],[NaN,39],[116,Infinity]]) await assert.rejects(service.cityAt(...args));
  assert.equal(requests.length, 2);
});

test('每轮定位只识别一次城市，重新定位清除手填城市并使用新位置', async () => {
  const model = new SearchCity(); const points = [];
  const lookup = async (...coords) => {points.push(coords); return points.length === 1 ? '北京市' : '廊坊市';};
  assert.equal(model.city, '');
  model.begin(); assert.equal(await model.located(116.4,39.9,lookup), true);
  assert.equal(model.city, '北京市');
  assert.equal(await model.located(116.41,39.91,lookup), false);
  model.manual('上海市'); assert.equal(model.city, '上海市');
  model.begin(); assert.equal(model.city, '');
  await model.located(116.9,39.9,lookup);
  assert.equal(model.city, '廊坊市');
  assert.deepEqual(points, [[116.4,39.9],[116.9,39.9]]);
});

test('手动改城市、重新定位和离页取消均忽略过期城市响应', async () => {
  const model = new SearchCity();
  let old = deferred(); model.begin(); let pending = model.located(116,39,() => old.promise);
  model.manual('上海市'); old.resolve('北京市');
  assert.equal(await pending, false); assert.equal(model.city, '上海市');
  old = deferred(); model.begin(); pending = model.located(116,39,() => old.promise);
  model.begin(); await model.located(117,40,async () => '天津市'); old.resolve('北京市');
  assert.equal(await pending, false); assert.equal(model.city, '天津市');
  old = deferred(); model.begin(); pending = model.located(116,39,() => old.promise);
  model.cancel(); old.resolve('北京市');
  assert.equal(await pending, false); assert.equal(model.city, '');
});

test('识别失败明确提示且不保留旧城市，手填后可继续搜索，再定位可恢复', async () => {
  const model = new SearchCity(); model.manual('北京市'); model.begin();
  assert.equal(await model.located(116,39,async () => {throw Error('secret');}), true);
  assert.equal(model.city, ''); assert.match(model.status, /手动填写/);
  assert.equal(model.status.includes('secret'), false);
  model.manual('天津市'); assert.equal(model.city, '天津市');
  model.begin(); await model.located(116,39,async () => '北京市'); assert.equal(model.city, '北京市');
});
