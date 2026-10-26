const test=require('node:test');const assert=require('node:assert/strict');const load=require('./load-ets.cjs');
function setup(){
  const s={listeners:new Set(),removed:[],cars:[],pushes:[],events:[],backs:0,params:{},stops:0,plans:[],starts:[],selected:[],locks:0,paths:new Map([[12,{getAllLength:()=>10000,getAllTime:()=>600,getLabels:()=>'推荐'}],[13,{getAllLength:()=>12000,getAllTime:()=>720,getLabels:()=>'备选'}]])};
  const navi={addAMapNaviListener(fn){s.listeners.add(fn);},removeAMapNaviListener(fn){s.listeners.delete(fn);s.removed.push(fn);},stopNavi(){s.stops++;},strategyConvert(){return 10;},calculateDriveRouteForPoi(...args){s.plans.push(args);return s.planAccepted!==false;},getNaviPaths(){return s.paths;},selectRouteId(id){s.selected.push(id);return s.selectAccepted!==false;},startNavi(type){s.starts.push(type);return s.startAccepted!==false;}};
  const router={async pushUrl(config){s.pushes.push(config);s.params=config.params;if(s.fail)throw Error('secret key');if(s.pending)await s.pending;},getParams:()=>s.params,back(){s.backs++;s.params={};}};
  const {NativeRoutePageSession}=load('NativeRoutePageSession',{'@amap/amap_lbs_navi':{AMapNaviView:class{displayOverview(){if(s.overviewFail)throw Error('map pending');}recoverLockMode(){s.locks++;}},AMapPageType:{NAVI:1},NaviType:{GPS:0}},
    './CarIconSession':{CarIconSession:class{constructor(){s.cars.push(this);}setForeground(v){this.foreground=v;}setVisible(v){this.visible=v;}dispose(){this.disposed=true;}}}});
  s.session=new NativeRoutePageSession();s.navi=navi;s.config={goBack:()=>{},end:{coordinate:{}},setNeedCalculateRouteWhenPresent(value){s.automaticCalculation=value;}};
  s.callbacks={onStartNavi:v=>s.events.push(['start',v]),onExitPage:v=>s.events.push(['exit',v]),onArriveDestination:v=>s.events.push(['arrive',v]),
    onCalculateRouteFailure:v=>s.events.push(['fail',v]),onCalculateRouteSuccess:v=>s.events.push(['routes',Array.from(v)]),onReCalculateRoute:v=>s.events.push(['replan',v]),onInitNaviFailure:()=>s.events.push(['init-fail'])};
  s.show=()=>s.session.show(s.config,s.callbacks,navi,{}, {getRouter:()=>router});return s;
}
test('导航页交接只传数字ID，配置和视图在内存，退出结束导航且清理自身订阅',async()=>{
  const s=setup();await s.show();assert.deepEqual(s.pushes[0],{url:'pages/NativeRoute',params:{navigationSession:1}});
  const request=s.session.request(1);assert.equal(request.params,s.config);assert.equal(s.cars[0].visible,false);
  s.session.setVisible(1,true);assert.equal(s.cars[0].visible,true);s.session.setForeground(false);assert.equal(s.cars[0].foreground,false);
  s.session.setForeground(true);
  const listener=[...s.listeners][0];listener.onCalculateRouteSuccess({routeId:new Int32Array([12,13])});s.session.start(1);listener.onStartNavi(0);listener.onReCalculateRoute(1);listener.onArriveDestination();
  assert.deepEqual(s.events,[['routes',[12,13]],['start',0],['replan',1],['arrive',false]]);
  s.config.goBack();assert.equal(s.session.request(1),undefined);assert.equal(s.cars[0].disposed,true);assert.equal(s.listeners.size,0);assert.equal(s.backs,1);assert.equal(s.stops,1);
  const count=s.events.length;listener.onStartNavi(0);listener.onArriveDestination();assert.equal(s.events.length,count);s.session.close();assert.equal(s.backs,1);
});
test('旧页面退出及旧回调不影响新会话，未经确认及模拟导航不能开始真实历史',async()=>{
  const s=setup();await s.show();const old=[...s.listeners][0];await s.show();const current=[...s.listeners][0];
  s.session.close(1);assert.ok(s.session.request(2));const count=s.events.length;old.onCalculateRouteFailureForResult({errorCode:123});assert.equal(s.events.length,count);
  current.onStartNavi(1);assert.equal(s.events.some(e=>e[0]==='start'),false);assert.equal(s.stops,2);
  s.session.close(2,false);assert.equal(s.backs,1);assert.equal(s.cars[1].disposed,true);
});
test('路由失败不泄漏原始错误，释放已创建的车标与监听',async()=>{
  const s=setup();s.fail=true;await assert.rejects(s.show(),e=>!/secret/.test(e.message));
  assert.equal(s.listeners.size,0);assert.equal(s.cars[0].disposed,true);assert.equal(s.session.request(1),undefined);
});
test('异步页面打开期间取消不保留会话或监听，完成后退回过时页面',async()=>{
  const s=setup();let finish;s.pending=new Promise(resolve=>{finish=resolve;});const opening=s.show();s.session.close(1,false);finish();await opening;
  assert.equal(s.listeners.size,0);assert.equal(s.session.request(1),undefined);assert.equal(s.backs,1);
});

test('从SDK当前位置规划，多路线摘要仅来自SDK，确认前不开始GPS，按选中的路线启动',async()=>{
  const s=setup();await s.show();assert.equal(s.automaticCalculation,false);
  const listener=[...s.listeners][0];const r=s.session.request(1);
  s.session.start(1);assert.equal(s.starts.length,0);
  s.session.plan(1);listener.onInitNaviSuccess();assert.equal(s.plans.length,1);assert.equal(s.plans[0][0],null);
  assert.equal(s.plans[0][1],s.config.end);assert.equal(s.plans[0][3],10);
  listener.onCalculateRouteSuccess({routeId:new Int32Array([12,13,999])});assert.deepEqual(r.routes.map(v=>v.id),[12,13]);
  assert.equal(r.selected,12);assert.equal(s.starts.length,0);assert.equal(s.session.select(1,999),false);
  s.overviewFail=true;assert.equal(s.session.select(1,13),true);s.session.setForeground(false);s.session.start(1);assert.equal(s.starts.length,0);
  s.session.setForeground(true);s.session.start(1);assert.deepEqual(s.starts,[0]);assert.equal(s.selected.at(-1),13);
  listener.onStartNavi(0);assert.equal(r.started,true);assert.equal(s.locks,1);listener.onStartNavi(0);assert.equal(s.events.filter(e=>e[0]==='start').length,1);
  s.session.close();
});

test('规划及开始失败可以重试，失败与取消不产生开始事件或可确认的虚构路线',async()=>{
  const s=setup();await s.show();const listener=[...s.listeners][0];const r=s.session.request(1);
  s.planAccepted=false;s.session.plan(1);assert.equal(r.planning,false);assert.equal(r.selected,-1);
  s.planAccepted=true;s.session.plan(1);listener.onCalculateRouteFailureForResult({errorCode:2});
  assert.equal(r.planning,false);assert.deepEqual(r.routes,[]);assert.equal(s.starts.length,0);
  s.session.plan(1);listener.onCalculateRouteSuccess({routeId:new Int32Array([12])});
  s.startAccepted=false;s.session.start(1);assert.equal(r.starting,false);assert.equal(r.started,false);
  assert.equal(s.events.some(e=>e[0]==='start'),false);s.session.close();
});
