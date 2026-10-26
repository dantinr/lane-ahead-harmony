const test=require('node:test');const assert=require('node:assert/strict');const load=require('./load-ets.cjs');
function setup(options={}){
  const original={now:Date.now,set:global.setInterval,clear:global.clearInterval,storage:global.AppStorage};
  const state={now:1000,timers:[],cleared:[],callbacks:new Map(),off:[],publications:0,snapshots:new Map()};
  Date.now=()=>state.now;
  global.setInterval=fn=>{state.timers.push(fn);return state.timers.length;};global.clearInterval=id=>state.cleared.push(id);
  global.AppStorage={setOrCreate(key,value){state.publications++;state.snapshots.set(key,value);}};
  const sensor={SensorId:{LINEAR_ACCELEROMETER:258,GRAVITY:257},getSingleSensorSync(type){
    if(options.unsupported)throw Error('secret sensor details');return {sensorId:type};
  },on(type,callback,config){
    assert.equal(config.interval,20000000);
    if(options.failLinear&&type===258)throw Error('secret sensor details');state.callbacks.set(type,callback);
  },off(type,callback){
    state.off.push([type,callback]);
    if(state.callbacks.has(type)){assert.equal(callback,state.callbacks.get(type));state.callbacks.delete(type);}
    if(options.failOff)throw Error('already removed');
  }};
  const {DrivingGSession}=load('DrivingGSession',{'@kit.SensorServiceKit':{sensor}});state.session=new DrivingGSession();
  state.read=()=>state.snapshots.get('laneAheadDrivingG');
  state.emit=(linear={x:0,y:0,z:0},at=state.now+20)=>{
    state.now=at;const timestamp=at*1000000;
    state.callbacks.get(257)?.({x:0,y:9.80665,z:0,timestamp});
    state.callbacks.get(258)?.({...linear,timestamp});state.timers.at(-1)?.();
  };
  state.calibrate=()=>{state.session.calibrate();for(let i=0;i<107;i++)state.emit();assert.equal(state.read().calibrated,true);};
  state.cleanup=()=>{state.session.stop();Date.now=original.now;global.setInterval=original.set;global.clearInterval=original.clear;global.AppStorage=original.storage;};
  return state;
}

test('以50Hz请求两类传感器，10Hz发布，校准可产生真实读数且峰值仅在内存',()=>{
  const s=setup();try{
    s.session.start();s.session.start();assert.equal(s.callbacks.size,2);assert.equal(s.timers.length,1);
    assert.equal(s.read().valid,false);s.calibrate();
    for(let i=0;i<80;i++)s.emit({x:0,y:0,z:-4.903325});
    assert.ok(s.read().longitudinal>0.49);assert.ok(s.read().peakAcceleration>0.49);
    assert.equal(s.snapshots.size,1);assert.ok(!JSON.stringify(s.read()).includes('timestamp'));
    s.session.resetPeaks();assert.equal(s.read().peakTotal,0);
  }finally{s.cleanup();}
});

test('停止后只取消自身监听和定时器，旧回调及旧计时任务不能更新新状态',()=>{
  const s=setup();try{
    s.session.start();const linear=s.callbacks.get(258),gravity=s.callbacks.get(257),timer=s.timers[0];
    s.session.stop();const count=s.publications;
    linear({x:0,y:0,z:99,timestamp:9e12});gravity({x:0,y:9.8,z:0,timestamp:9e12});timer();
    assert.equal(s.publications,count);assert.equal(s.callbacks.size,0);assert.equal(s.off.length,2);
    assert.equal(s.cleared.length,1);assert.equal(s.read().valid,false);
    s.session.start();linear({x:99,y:0,z:0,timestamp:9e12});timer();assert.equal(s.read().valid,false);
  }finally{s.cleanup();}
});

test('后台暂停解除订阅，前台恢复保留本次峰值与校准，新次开始重置峰值',()=>{
  const s=setup();try{
    s.session.start();s.calibrate();for(let i=0;i<60;i++)s.emit({x:2,y:0,z:-3});
    const peak=s.read().peakTotal;s.session.setForeground(false);
    assert.equal(s.callbacks.size,0);assert.equal(s.read().status,'后台暂停测量');assert.equal(s.read().valid,false);
    s.session.setForeground(true);assert.equal(s.callbacks.size,2);s.emit();
    assert.equal(s.read().valid,true);assert.equal(s.read().peakTotal,peak);
    s.session.stop();s.session.start();assert.equal(s.read().peakTotal,0);assert.equal(s.read().calibrated,true);
  }finally{s.cleanup();}
});

test('后台打开不订阅，传感器缺失或半途订阅失败不影响其他功能且清理已成功的订阅',()=>{
  for(const options of [{unsupported:true},{failLinear:true}]){
    const s=setup(options);try{
      s.session.setForeground(false);s.session.start();assert.equal(s.callbacks.size,0);
      s.session.setForeground(true);assert.equal(s.callbacks.size,0);assert.equal(s.read().available,false);
      assert.equal(s.read().valid,false);assert.doesNotMatch(s.read().status,/secret/);
      s.session.calibrate();assert.equal(s.read().calibrating,false);
    }finally{s.cleanup();}
  }
});

test('乱序时间戳与相差超过200毫秒的两类传感器不形成读数，掉帧超过500毫秒撤下当前值',()=>{
  const s=setup();try{
    s.session.start();s.calibrate();const peak=s.read().peakTotal;
    const linear=s.callbacks.get(258);linear({x:99,y:0,z:0,timestamp:1});s.timers.at(-1)();
    assert.equal(s.read().peakTotal,peak);
    s.now+=400;linear({x:99,y:0,z:0,timestamp:s.now*1000000});s.timers.at(-1)();
    assert.equal(s.read().peakTotal,peak);
    s.now+=200;s.timers.at(-1)();assert.equal(s.read().valid,false);
    s.emit();assert.equal(s.read().valid,true);assert.equal(s.read().peakTotal,peak);
  }finally{s.cleanup();}
});

test('平台取消订阅抛错仍使旧回调失效并清理另一类传感器',()=>{
  const s=setup({failOff:true});try{
    s.session.start();const callback=s.callbacks.get(258);s.session.stop();
    assert.equal(s.off.length,2);assert.equal(s.callbacks.size,0);
    callback({x:99,y:0,z:0,timestamp:9e12});assert.equal(s.read().valid,false);
  }finally{s.cleanup();}
});
