const test=require('node:test');const assert=require('node:assert/strict');const load=require('./load-ets.cjs');
function setup(failure=''){
  const original={now:Date.now,set:global.setInterval,clear:global.clearInterval,storage:global.AppStorage};
  const s={now:1000,callbacks:[],off:[],timers:[],cleared:[],publications:0};
  Date.now=()=>s.now;global.setInterval=(fn,ms)=>{assert.equal(ms,100);s.timers.push(fn);return s.timers.length;};
  global.clearInterval=id=>s.cleared.push(id);global.AppStorage={setOrCreate(k,v){assert.equal(k,'laneAheadSpiritLevel');s.value=v;s.publications++;}};
  const sensor={SensorId:{GRAVITY:257},getSingleSensorSync(){if(failure==='missing')throw Error('private');},
    on(id,cb,config){assert.equal(id,257);assert.equal(config.interval,50000000);s.callbacks.push(cb);if(failure==='subscribe')throw Error('private');},
    off(id,cb){assert.equal(id,257);s.off.push(cb);if(failure==='off')throw Error('off');}};
  const {SpiritLevelSession}=load('SpiritLevelSession',{'@kit.SensorServiceKit':{sensor}});s.session=new SpiritLevelSession();
  s.emit=(timestamp)=>{s.now+=50;s.callbacks.at(-1)({x:0,y:0,z:9.80665,timestamp:timestamp??s.now*1e6});s.timers.at(-1)?.();};
  s.cleanup=()=>{s.session.stop();Date.now=original.now;global.setInterval=original.set;global.clearInterval=original.clear;global.AppStorage=original.storage;};return s;
}

test('仅独立重力监听，20Hz采样10Hz发布；离页与后台精确清理且旧回调无效',()=>{
  const s=setup();try{
    s.session.start();s.session.start();assert.equal(s.callbacks.length,1);assert.equal(s.timers.length,1);
    s.emit();assert.equal(s.value.valid,true);const old=s.callbacks[0],timer=s.timers[0];
    s.session.setForeground(false);assert.equal(s.value.valid,false);assert.equal(s.off[0],old);assert.equal(s.cleared.length,1);
    const count=s.publications;old({x:0,y:0,z:9.8,timestamp:9e12});timer();assert.equal(s.publications,count);
    s.session.setForeground(true);assert.equal(s.value.valid,false);s.emit();assert.equal(s.value.valid,true);
    s.session.stop();s.session.start();old({x:0,y:0,z:9.8,timestamp:9e12});timer();assert.equal(s.value.valid,false);
    assert.ok(!JSON.stringify(s.value).includes('timestamp'));
  }finally{s.cleanup();}
});

test('后台启动与缺失、部分订阅失败均保持未知，不泄漏详情；停止容忍取消异常',()=>{
  for(const failure of ['missing','subscribe','off']){const s=setup(failure);try{
    s.session.setForeground(false);s.session.start();assert.equal(s.callbacks.length,0);
    s.session.setForeground(true);
    if(failure==='off'){s.emit();assert.equal(s.value.valid,true);s.session.stop();assert.equal(s.value.valid,false);}
    else{assert.equal(s.value.valid,false);assert.equal(s.value.running,false);assert.doesNotMatch(s.value.status,/private/);}
  }finally{s.cleanup();}}
});

test('乱序传感器时间戳不刷新数据有效期，超时撤下读数后恢复',()=>{
  const s=setup();try{
    s.session.start();s.emit();assert.equal(s.value.valid,true);
    s.now+=600;s.emit(1);assert.equal(s.value.valid,false);
    s.emit();assert.equal(s.value.valid,true);
  }finally{s.cleanup();}
});
