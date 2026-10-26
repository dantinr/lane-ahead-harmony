const test=require('node:test');const assert=require('node:assert/strict');const load=require('./load-ets.cjs');
function setup(options={}){
  const original={now:Date.now,set:global.setInterval,clear:global.clearInterval,storage:global.AppStorage};
  const s={now:1000,callbacks:new Map(),off:[],timers:[],cleared:[],publications:0,snapshots:new Map()};
  Date.now=()=>s.now;global.setInterval=(fn,ms)=>{assert.equal(ms,100);s.timers.push(fn);return s.timers.length;};
  global.clearInterval=id=>s.cleared.push(id);global.AppStorage={setOrCreate(k,v){s.publications++;s.snapshots.set(k,v);}};
  const sensor={SensorId:{MAGNETIC_FIELD:6,GRAVITY:257},getSingleSensorSync(){if(options.unsupported)throw Error('private detail');},
    on(type,callback,config){assert.equal(config.interval,50000000);if(options.partial&&type===6)throw Error('private detail');s.callbacks.set(type,callback);},
    off(type,callback){s.off.push([type,callback]);if(s.callbacks.has(type)){assert.equal(s.callbacks.get(type),callback);s.callbacks.delete(type);}if(options.offThrows)throw Error('off');}};
  const {CompassSession}=load('CompassSession',{'@kit.SensorServiceKit':{sensor}});s.session=new CompassSession();
  s.read=()=>s.snapshots.get('laneAheadCompass');s.emit=()=>{s.now+=50;const timestamp=s.now*1e6;
    s.callbacks.get(257)?.({x:0,y:0,z:9.80665,timestamp});s.callbacks.get(6)?.({x:-25,y:0,z:-40,timestamp,accuracy:3});s.timers.at(-1)?.();};
  s.cleanup=()=>{s.session.stop();Date.now=original.now;global.setInterval=original.set;global.clearInterval=original.clear;global.AppStorage=original.storage;};return s;
}

test('指南针独立订阅20Hz传感器并10Hz发布，不需要G值校准，无持久化样本',()=>{
  const s=setup();try{s.session.start();s.session.start();assert.equal(s.callbacks.size,2);assert.equal(s.timers.length,1);
    assert.equal(s.read().valid,false);s.emit();assert.equal(s.read().valid,true);assert.equal(s.read().heading,90);
    assert.equal(s.snapshots.size,1);assert.ok(!JSON.stringify(s.read()).includes('timestamp'));
  }finally{s.cleanup();}
});

test('后台与离页只释放自身精确回调，旧传感器和计时任务不能影响重启',()=>{
  const s=setup();try{s.session.start();s.emit();const mag=s.callbacks.get(6),grav=s.callbacks.get(257),timer=s.timers[0];
    s.session.setForeground(false);assert.equal(s.callbacks.size,0);assert.equal(s.read().valid,false);
    const count=s.publications;mag({timestamp:9e12,x:25,y:0,z:-40,accuracy:3});grav({timestamp:9e12,x:0,y:0,z:9.8});timer();assert.equal(s.publications,count);
    s.session.setForeground(true);assert.equal(s.callbacks.size,2);assert.equal(s.read().valid,false);s.emit();assert.equal(s.read().valid,true);
    s.session.stop();s.session.start();mag({timestamp:9e12,x:25,y:0,z:-40,accuracy:3});timer();assert.equal(s.read().valid,false);
    assert.ok(s.off.every(([,cb])=>typeof cb==='function'));assert.ok(s.cleared.length>=2);
  }finally{s.cleanup();}
});

test('后台启动不订阅；传感器缺失与部分订阅失败清理且不泄漏错误',()=>{
  for(const options of [{unsupported:true},{partial:true}]){const s=setup(options);try{
    s.session.setForeground(false);s.session.start();assert.equal(s.callbacks.size,0);
    s.session.setForeground(true);assert.equal(s.callbacks.size,0);assert.equal(s.read().available,false);
    assert.equal(s.read().valid,false);assert.doesNotMatch(s.read().status,/private/);
  }finally{s.cleanup();}}
});

test('乱序与时间差过大的传感器配对被忽略，失联撤下读数后可恢复',()=>{
  const s=setup();try{s.session.start();s.emit();const mag=s.callbacks.get(6);
    mag({timestamp:1,x:25,y:0,z:-40,accuracy:3});s.timers[0]();assert.equal(s.read().heading,90);
    s.now+=600;mag({timestamp:s.now*1e6,x:25,y:0,z:-40,accuracy:3});s.timers[0]();assert.equal(s.read().valid,false);
    s.emit();assert.equal(s.read().valid,true);
  }finally{s.cleanup();}
});

test('取消订阅抛错仍清理另一监听，停止后过时回调无效',()=>{
  const s=setup({offThrows:true});try{s.session.start();const callback=s.callbacks.get(6);s.session.stop();
    assert.equal(s.off.length,2);assert.equal(s.callbacks.size,0);callback({timestamp:9e12,x:0,y:25,z:-40,accuracy:3});
    assert.equal(s.read().valid,false);
  }finally{s.cleanup();}
});
