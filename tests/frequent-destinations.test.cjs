const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { NavigationHistory, NavigationRecord } = load('NavigationHistory');
const { frequentDestinations, frequentDestinationQuery } = load('FrequentDestinations');
const { resolvePlaceSearch } = load('SearchScope');

function trip(id, name, endedAt, city='北京市', address='公共地址', status='arrived') {
  const record = new NavigationRecord(id, name, address, 1000, 100, city);
  record.status = status;
  record.endedAt = ['navigating', 'interrupted'].includes(status) ? 0 : endedAt;
  return record;
}

test('常去地点按到达次数、最近到达排序且最多五个，不修改原始导航历史', () => {
  const records = [trip('a1','常去公园',2000),trip('a2','常去公园',2100),trip('a3','常去公园',2200),
    trip('b1','公共图书馆',3000),trip('b2','公共图书馆',6000),
    ...Array.from({length:6},(_,i)=>trip('one-'+i,'测试地点'+i,7000+i))];
  const before = JSON.stringify(records);
  const places = frequentDestinations(records);
  assert.deepEqual(places.map(p=>[p.name,p.visits]),[
    ['常去公园',3],['公共图书馆',2],['测试地点5',1],['测试地点4',1],['测试地点3',1]]);
  assert.equal(JSON.stringify(records),before);
  assert.deepEqual(frequentDestinations(records.toReversed()),places);
});

test('仅有效已到达记录参与统计，重复历史ID只计一次，取消、中断与失败不算去过', () => {
  const arrived = trip('ok','公共地点',3000);
  const records = [arrived,arrived,...['ended','failed','interrupted','navigating'].map((status,i)=>
    trip('other-'+i,'未到达地点',4000+i,'北京市','公共地址',status)),null,
    {...arrived,id:'broken',endedAt:999}];
  assert.deepEqual(frequentDestinations(records).map(p=>[p.name,p.visits]),[['公共地点',1]]);
});

test('城市与地址区分同名门店，空白和英文大小写变化不重复；旧记录识别明确行政区城市', () => {
  const records = [trip('a','Library',2000,'北京','北京市朝阳区公共地址'),
    trip('b',' library ',3000,'北京市','北京市 朝阳区公共地址'),
    trip('c','Library',4000,'北京市','北京市海淀区公共地址'),
    trip('d','Library',5000,'天津市','天津市和平区公共地址'),
    trip('e','Library',6000,'','北京市朝阳区公共地址')];
  delete records.at(-1).city;
  const places = frequentDestinations(records);
  assert.equal(places.length,3);
  assert.deepEqual(places.map(p=>p.visits),[3,1,1]);
  assert.equal(places[0].city,'北京市');
  assert.equal(places[1].city,'天津市');
  assert.equal(new Set(places.map(p=>p.key)).size,3);
});

test('快捷搜索明确使用目的地城市，当前位置和手动搜索范围不覆盖；城市不明不猜测', () => {
  const [place] = frequentDestinations([trip('a','公共图书馆',2000)]);
  const query = frequentDestinationQuery(place);
  const scope = resolvePlaceSearch(query,'廊坊市');
  assert.deepEqual(scope,{keyword:'公共图书馆',city:'北京市',region:'110000',explicitCity:true});
  const [unknown] = frequentDestinations([trip('b','南京饭店',2000,'','北京路1号')]);
  assert.equal(unknown.city,'');assert.equal(frequentDestinationQuery(unknown),'南京饭店');
  assert.doesNotMatch(JSON.stringify(place),/longitude|latitude|location|Key/);
});

test('删除或清空导航历史后重新计算常去地点，不留独立统计或影响搜索历史', () => {
  const history = new NavigationHistory();
  history.put(trip('a','公共地点',2000));history.put(trip('b','公共地点',3000));
  history.put(trip('c','其他地点',4000));
  assert.equal(frequentDestinations(history.records)[0].visits,2);
  history.remove('a');assert.equal(frequentDestinations(history.records)[0].name,'其他地点');
  history.remove('b');assert.deepEqual(frequentDestinations(history.records).map(p=>p.name),['其他地点']);
  assert.deepEqual(frequentDestinations([]),[]);
});
