const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { resolvePlaceSearch } = load('SearchScope');
const { SEARCH_CITIES } = load('SearchCities');
const { AMapRouteService, decodePlaces } = load('RoutePlanning');
const { SearchHistory } = load('SearchHistory');

test('城市前缀覆盖定位城市，支持空格、全角空格和完整市名连写', () => {
  for (const query of ['北京 望京花园', '  北京　 望京花园  ', '北京市 望京花园', '北京市望京花园']) {
    assert.deepEqual(resolvePlaceSearch(query, '廊坊市'), {
      keyword: '望京花园', city: '北京市', region: '110000', explicitCity: true
    });
  }
  assert.equal(resolvePlaceSearch('上海 人民广场', '北京市').city, '上海市');
  assert.equal(resolvePlaceSearch('石家庄 河北博物院', '北京市').region, '130100');
  assert.equal(resolvePlaceSearch('深圳市深圳北站', '').region, '440300');
});

test('普通名称保留当前城市，不把包含城市字样的道路或商店当作跨城搜索', () => {
  for (const query of ['北京路', '北京路 万达广场', '南京饭店', '北京大学', '望京花园', 'A&B 大厦', '未知城 图书馆']) {
    assert.deepEqual(resolvePlaceSearch(query, ' 廊坊市 '), {
      keyword: query, city: '廊坊市', region: '廊坊市', explicitCity: false
    });
  }
  assert.equal(resolvePlaceSearch('  万达　 广场  ', '北京市').keyword, '万达 广场');
});

test('没有定位城市时可用明确城市搜索；没有任何城市信息则提示补充，绝不回退全国', () => {
  assert.equal(resolvePlaceSearch('北京 望京花园', '').region, '110000');
  assert.equal(resolvePlaceSearch('北京', '').keyword, '北京市');
  assert.throws(() => resolvePlaceSearch('望京花园', ''), /城市/);
  assert.throws(() => resolvePlaceSearch(' ', '北京市'), /地点/);
});

test('城市索引无重名或无效编码，四个直辖市及普通地级市可用', () => {
  const names = SEARCH_CITIES.map(entry => entry.split(':')[0]);
  assert.equal(names.length, new Set(names).size);
  assert.ok(names.length > 300);
  for (const entry of SEARCH_CITIES) {
    const [name, code] = entry.split(':');
    assert.match(code, /^\d{6}$/);
    assert.notEqual(name, '市辖区');
    assert.notEqual(name, '县');
    const scope = resolvePlaceSearch(name + ' 图书馆', '其他城市');
    assert.equal(scope.city, name);
    assert.equal(scope.region, code);
    assert.equal(scope.keyword, '图书馆');
  }
  for (const city of ['北京', '上海', '天津', '重庆', '成都', '杭州', '乌鲁木齐']) {
    assert.equal(resolvePlaceSearch(city + ' 图书馆', '').city, city + '市');
  }
});

test('实际地点请求按明确城市编码严格搜索，只发一次地点请求且之后仍以定位城市为默认', async () => {
  const requests = [];
  const service = new AMapRouteService({ get: async url => {
    requests.push(new URL(url));
    return '{"status":"1","pois":[]}';
  } }, 'a'.repeat(32));
  await service.search('北京 望京花园', '廊坊市');
  await service.search('上海市人民广场', '');
  await service.search('望京花园', '廊坊市');
  assert.equal(requests.length, 3);
  assert.deepEqual(requests.map(url => [url.pathname, url.searchParams.get('keywords'),
    url.searchParams.get('region'), url.searchParams.get('city_limit')]), [
    ['/v5/place/text', '望京花园', '110000', 'true'],
    ['/v5/place/text', '人民广场', '310000', 'true'],
    ['/v5/place/text', '望京花园', '廊坊市', 'true']
  ]);
});

test('跨城结果显示真实城市和区县，兼容直辖市、空地址及旧接口字段', () => {
  const base = { id:'B1', name:'测试地点', location:'116.48,39.99' };
  const address = poi => decodePlaces(JSON.stringify({ status:'1', pois:[{...base,...poi}] }))[0].address;
  assert.equal(address({pname:'北京市',cityname:'北京市',adname:'朝阳区',address:'望京街'}), '北京市朝阳区 · 望京街');
  assert.equal(address({pname:'北京市',cityname:[],adname:'朝阳区',address:[]}), '北京市朝阳区');
  assert.equal(address({pname:'河北省',cityname:'廊坊市',adname:'广阳区',address:'测试路'}), '廊坊市广阳区 · 测试路');
  assert.equal(address({cityname:'北京市',adname:'朝阳区',address:'北京市朝阳区望京街'}), '北京市朝阳区望京街');
  assert.equal(address({address:'旧地址'}), '旧地址');
});

test('历史保留完整城市关键词，换定位城市重搜也能还原明确城市', () => {
  const history = new SearchHistory();
  history.remember('北京 望京花园');
  const query = history.records[0].query;
  assert.equal(query, '北京 望京花园');
  assert.equal(resolvePlaceSearch(query, '上海市').city, '北京市');
});
