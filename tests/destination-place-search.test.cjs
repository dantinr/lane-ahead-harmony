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

test('当前城市有结果时立即返回，不查询去过的城市', async () => {
  const calls=[];
  const result=await searchDestinationPlaces({async search(query,city){calls.push(city);return [place];}},
    options(),()=>true,()=>assert.fail('should not fall back'));
  assert.deepEqual(calls,['廊坊市']);assert.equal(result.usedVisitedCity,false);
  assert.equal(result.places[0],place);assert.equal(result.checkedVisitedCities,0);
});

test('当前城市确认为空才逐城回退，跳过当前城市和重复项，在第一个有效结果处停止', async () => {
  const calls=[],progress=[];
  const result=await searchDestinationPlaces({async search(query,city){calls.push([query,city]);return city==='北京市'?[place]:[];}},
    options({visitedCities:['廊坊','天津市','天津','不存在的城市','北京市','上海市']}),()=>true,city=>progress.push(city));
  assert.deepEqual(calls,[['图书馆','廊坊市'],['图书馆','天津市'],['图书馆','北京市']]);
  assert.deepEqual(progress,['天津市','北京市']);
  assert.equal(result.city,'北京市');assert.equal(result.usedVisitedCity,true);
  assert.equal(result.checkedVisitedCities,2);assert.equal(result.explicitCity,false);
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
