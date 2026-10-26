const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { visitedSearchCities } = load('VisitedCities');
const { searchDestinationPlaces } = load('DestinationPlaceSearch');
const { NavigationHistory, NavigationRecord } = load('NavigationHistory');
const { AMapRouteService, Place, decodePlaces } = load('RoutePlanning');
const options = (extra={}) => ({query:'图书馆',city:'廊坊市',visitedCities:['北京市','天津市'],allowFallback:true,...extra});
const place = new Place('B1','公共图书馆','北京市朝阳区','116.48,39.99','北京市');
function record(id, city, endedAt, status='arrived', address='') {
  const item = new NavigationRecord(id,'公共地点',address,1000,100,city);
  item.status=status; item.endedAt=['navigating','interrupted'].includes(status)?0:endedAt;
  return item;
}

test('去过城市只从真实已到达记录提取，按最近到达排序去重，不改动历史顺序', () => {
  const records=[record('old','北京',2000),record('new','天津市',5000),record('dup','北京市',4000),
    record('ended','上海市',6000,'ended'),record('failed','杭州市',7000,'failed'),
    record('active','南京市',0,'navigating'),record('interrupted','深圳市',0,'interrupted')];
  const original=JSON.stringify(records);
  assert.deepEqual(visitedSearchCities(records),['天津市','北京市']);
  assert.equal(JSON.stringify(records),original);
  const history=new NavigationHistory();records.forEach(item=>history.put(item));
  history.remove('new');assert.deepEqual(visitedSearchCities(history.records),['北京市']);
  history.records=[];assert.deepEqual(visitedSearchCities(history.records),[]);
});

test('兼容旧记录的行政区地址前缀，不能从店名、路名或缺失地址猜城市', () => {
  const records=['北京市朝阳区 · 公开地址','河北省廊坊市广阳区','广西壮族自治区南宁市青秀区',
    '某区北京路1号','北京路商场','南京饭店','未知地址',''].map((address,index)=>{
      const item=record('old-'+index,'',2000+index,'arrived',address);delete item.city;return item;
    });
  assert.deepEqual(visitedSearchCities(records),['南宁市','廊坊市','北京市']);
  const history=new NavigationHistory();
  assert.equal(history.restore(JSON.stringify({version:1,records})),true);
  assert.deepEqual(visitedSearchCities(history.records),['南宁市','廊坊市','北京市']);
  for(const city of [null,{},'x'.repeat(81)]) {
    assert.equal(NavigationHistory.valid({...records[0],city}),false);
  }
});

test('当前城市有名称匹配的结果时立即返回，不查询去过的城市', async () => {
  const calls=[];
  const result=await searchDestinationPlaces({async search(query,city){calls.push(city);return [place];}},
    options(),()=>true,()=>assert.fail('should not fall back'));
  assert.deepEqual(calls,['廊坊市']);assert.equal(result.usedVisitedCity,false);
  assert.equal(result.places[0],place);assert.equal(result.checkedVisitedCities,0);
});

test('逐城查找名称匹配，跳过当前城市和重复项，在第一个匹配处停止', async () => {
  const calls=[],progress=[];
  const result=await searchDestinationPlaces({async search(query,city){calls.push([query,city]);return city==='北京市'?[place]:[];}},
    options({visitedCities:['廊坊','天津市','天津','不存在的城市','北京市','上海市']}),()=>true,city=>progress.push(city));
  assert.deepEqual(calls,[['图书馆','廊坊市'],['图书馆','天津市'],['图书馆','北京市']]);
  assert.deepEqual(progress,['天津市','北京市']);
  assert.equal(result.city,'北京市');assert.equal(result.usedVisitedCity,true);
  assert.equal(result.checkedVisitedCities,2);assert.equal(result.explicitCity,false);
});

test('廊坊的乐谷模糊结果不能阻止查找北京的中国乐谷，曾到达的同等匹配优先', async () => {
  const poi=(id,name,city)=>new Place(id,name,city,'116.48,39.99',city);
  const local=[poi('L1','乐谷众创空间','廊坊市'),poi('L2','幽乐谷用品店','廊坊市')];
  const target=poi('B1','中国乐谷·村播学院总部基地','北京市');
  const beijing=[poi('B2','中国乐谷音乐休闲公园','北京市'),poi('B3','北京欢乐谷','北京市'),target];
  const calls=[];
  const result=await searchDestinationPlaces({async search(query,city){calls.push(city);return city==='廊坊市'?local:beijing;}},
    options({query:'中国乐谷',previousDestinations:[target.name]}),()=>true,()=>{});
  assert.deepEqual(calls,['廊坊市','北京市']);
  assert.equal(result.city,'北京市');assert.equal(result.usedVisitedCity,true);assert.equal(result.matchedByName,true);
  assert.deepEqual(result.places.map(p=>p.name),[target.name,'中国乐谷音乐休闲公园','北京欢乐谷']);
  assert.equal(result.warning,'');
  assert.deepEqual(beijing.map(p=>p.id),['B2','B3','B1']);
});

test('名称全等排在包含完整关键词之前，当前城市名称匹配仍优先；忽略空白与英文大小写', async () => {
  for(const [query,names,previous,expected] of [
    ['中国乐谷',['中国乐谷音乐公园','中国乐谷','乐谷空间'],['中国乐谷音乐公园'],['中国乐谷','中国乐谷音乐公园','乐谷空间']],
    [' lane AHEAD ',['LaneAhead商店','LANEAHEAD','Ahead'],[],['LANEAHEAD','LaneAhead商店','Ahead']]
  ]) {
    let calls=0;
    const result=await searchDestinationPlaces({async search(){calls++;return names.map((name,i)=>new Place(String(i),name,'','116.48,39.99'));}},
      options({query,previousDestinations:previous}),()=>true,()=>assert.fail('unexpected fallback'));
    assert.equal(calls,1);assert.equal(result.usedVisitedCity,false);assert.equal(result.matchedByName,true);
    assert.deepEqual(result.places.map(p=>p.name),expected);
  }
});

test('历史城市仅有模糊结果时继续查下一城，不把拆散或地址中的关键词当成名称匹配', async () => {
  const weak=new Place('W','中国某乐谷','中国乐谷','116.48,39.99');
  const exact=new Place('E','中国乐谷','北京市','116.48,39.99');
  const calls=[];
  const result=await searchDestinationPlaces({async search(query,city){calls.push(city);return city==='北京市'?[exact]:[weak];}},
    options({query:'中国乐谷',visitedCities:['天津市','北京市']}),()=>true,()=>{});
  assert.deepEqual(calls,['廊坊市','天津市','北京市']);
  assert.equal(result.places[0],exact);assert.equal(result.checkedVisitedCities,2);
});

test('各城均无名称匹配时保留当前城市相关结果；当前城市为空才保留首个历史城市相关结果', async () => {
  const weak=new Place('W','乐谷空间','','116.48,39.99');
  for(const localEmpty of [false,true]) {
    const calls=[];
    const result=await searchDestinationPlaces({async search(query,city){calls.push(city);return localEmpty&&city==='廊坊市'?[]:[weak];}},
      options({query:'中国乐谷'}),()=>true,()=>{});
    assert.deepEqual(calls,['廊坊市','北京市','天津市']);
    assert.equal(result.places[0],weak);assert.equal(result.matchedByName,false);
    assert.equal(result.city,localEmpty?'北京市':'廊坊市');assert.equal(result.usedVisitedCity,localEmpty);
    assert.equal(result.checkedVisitedCities,2);
  }
});

test('明确城市和手动范围即使只返回模糊相关地点，也不能跨城', async () => {
  for(const config of [options({query:'北京 中国乐谷'}),options({query:'中国乐谷',allowFallback:false})]) {
    let calls=0;
    const result=await searchDestinationPlaces({async search(){calls++;return [place];}},config,()=>true,()=>assert.fail('unexpected fallback'));
    assert.equal(calls,1);assert.equal(result.matchedByName,false);assert.equal(result.usedVisitedCity,false);
  }
});

test('补查历史城市失败时保留已有相关结果并明确报告未完成，不能伪报无匹配或查询成功', async () => {
  let calls=0;
  const result=await searchDestinationPlaces({async search(){if(++calls===2)throw Error('地图服务调用次数受限');return [place];}},
    options({query:'中国乐谷'}),()=>true,()=>{});
  assert.equal(result.places[0],place);assert.equal(result.matchedByName,false);assert.equal(result.usedVisitedCity,false);
  assert.match(result.warning,/未完成.*次数受限/);assert.equal(calls,2);
});

test('当前城市只有模糊结果时，取消后仍忽略历史城市响应，不回填旧结果或继续查询', async () => {
  let active=true,calls=0,resolve;
  const pending=searchDestinationPlaces({async search(){if(++calls===1)return [place];return await new Promise(done=>{resolve=done;});}},
    options({query:'中国乐谷'}),()=>active,()=>{});
  await new Promise(done=>setImmediate(done));assert.equal(calls,2);
  active=false;resolve([new Place('E','中国乐谷','','116.48,39.99')]);
  assert.equal(await pending,undefined);assert.equal(calls,2);
});

test('明确城市和手动范围均不自动扩大；无法识别当前城市时先要求补充', async () => {
  for(const extra of [{query:'上海 人民广场'},{query:'上海 人民广场',city:''},{allowFallback:false},{visitedCities:[]}]) {
    const calls=[];
    const result=await searchDestinationPlaces({async search(query,city){calls.push([query,city]);return [];}},
      options(extra),()=>true,()=>assert.fail('unexpected fallback'));
    assert.equal(calls.length,1);assert.equal(result.checkedVisitedCities,0);
    if(extra.query) {assert.equal(result.city,'上海市');assert.equal(result.explicitCity,true);}
  }
  await assert.rejects(searchDestinationPlaces({async search(){assert.fail('unexpected request');}},
    options({city:''}),()=>true,()=>{}),/城市/);
});

test('全部城市为空时返回实际搜索范围，不把无数据当作网络错误', async () => {
  const result=await searchDestinationPlaces({async search(){return [];}},options(),()=>true,()=>{});
  assert.deepEqual(result.places,[]);assert.equal(result.checkedVisitedCities,2);
  assert.equal(result.usedVisitedCity,false);assert.equal(result.city,'廊坊市');
});

test('连接、密钥或配额错误不触发扩大搜索，回退过程的错误也不能伪报无结果', async () => {
  for(const failAt of [1,2]) {
    let calls=0;
    await assert.rejects(searchDestinationPlaces({async search(){if(++calls===failAt)throw Error('地图服务连接失败');return [];}},
      options(),()=>true,()=>{}),/连接失败/);
    assert.equal(calls,failAt);
  }
});

test('修改输入、换城市或离页使搜索过期后，忽略返回值且不继续发起后续城市请求', async () => {
  for(const cancelAt of [0,1,2]) {
    let active=cancelAt!==0,calls=0,resolve;
    const pending=searchDestinationPlaces({search(){calls++;return new Promise(done=>{resolve=done;});}},
      options(),()=>active,()=>{});
    if(cancelAt===0) {assert.equal(await pending,undefined);assert.equal(calls,0);continue;}
    if(cancelAt===2) {
      resolve([]);await new Promise(done=>setImmediate(done));assert.equal(calls,2);
    }
    active=false;resolve([place]);assert.equal(await pending,undefined);assert.equal(calls,cancelAt);
  }
});

test('真实请求保持逐城限定且保留返回城市，不修改默认当前城市', async () => {
  const calls=[];const config=options();
  const service=new AMapRouteService({async get(url){
    const request=new URL(url);calls.push(request);
    return JSON.stringify({status:'1',pois:calls.length===1?[]:[{id:'B1',name:'公共图书馆',
      location:'116.48,39.99',cityname:'北京市',adname:'朝阳区',address:'公开地址'}]});
  }},'a'.repeat(32));
  const result=await searchDestinationPlaces(service,config,()=>true,()=>{});
  assert.deepEqual(calls.map(url=>[url.searchParams.get('region'),url.searchParams.get('city_limit')]),
    [['廊坊市','true'],['北京市','true']]);
  assert.equal(config.city,'廊坊市');assert.equal(result.places[0].city,'北京市');
  assert.match(result.places[0].address,/北京市朝阳区/);
  assert.equal(decodePlaces(JSON.stringify({status:'1',pois:[{name:'旧地点',location:'116.4,39.9'}]}))[0].city,'');
});
