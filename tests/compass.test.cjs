const test=require('node:test');const assert=require('node:assert/strict');const load=require('./load-ets.cjs');
const {CompassEngine}=load('Compass');const {GVector}=load('DrivingG');
const g=9.80665;const v=(x,y,z)=>new GVector(x,y,z);
function read(engine,gravity,magnetic,at=1000,accuracy=3){engine.updateGravity(gravity,at);engine.sample(magnetic,accuracy,at);return engine.snapshot();}
function close(actual,expected){assert.ok(Math.abs(actual-expected)<1e-8,`${actual} != ${expected}`);}

test('平放时按手机顶端输出磁北、东、南、西，未收到数据前保持未知',()=>{
  for(const [magnetic,heading,direction] of [[v(0,25,-40),0,'北'],[v(-25,0,-40),90,'东'],
    [v(0,-25,-40),180,'南'],[v(25,0,-40),270,'西']]){
    const e=new CompassEngine();e.start();assert.equal(e.state.valid,false);
    const s=read(e,v(0,0,g),magnetic);assert.equal(s.valid,true);close(s.heading,heading);
    assert.equal(s.direction,direction);assert.match(s.reference,/手机顶端/);close(s.rotation,-heading);
  }
});

test('车载竖放与倾斜安装按屏内方向投影，排除磁场的竖直分量',()=>{
  for(const tilt of [0,Math.PI/6])for(const heading of [0,45,90,180,270]){
    const up=v(0,Math.cos(tilt),Math.sin(tilt));const forward=v(0,Math.sin(tilt),-Math.cos(tilt));
    const a=heading*Math.PI/180;
    const magnetic=v(-25*Math.sin(a),25*Math.cos(a)*forward.y-40*up.y,25*Math.cos(a)*forward.z-40*up.z);
    const e=new CompassEngine();e.start();const s=read(e,v(0,g*up.y,g*up.z),magnetic);
    assert.equal(s.valid,true);close(s.heading,heading);assert.match(s.reference,/车头方向/);
  }
});

test('跨越359/0度使用最短角滤波，指针不绕远路旋转，模式切换重新建立读数',()=>{
  const field=h=>v(-25*Math.sin(h*Math.PI/180),25*Math.cos(h*Math.PI/180),-40);
  const e=new CompassEngine();e.start();let s=read(e,v(0,0,g),field(359));const before=s.rotation;
  s=read(e,v(0,0,g),field(1),1050);assert.ok(Math.abs(s.rotation-before)<2);
  assert.ok(s.heading>359||s.heading<1);
  s=read(e,v(0,g,0),v(-25,-40,0),1100);close(s.heading,90);assert.match(s.reference,/车头/);
});

test('绕竖直轴转向时八方位正确；平竖参考切换带滞回',()=>{
  const e=new CompassEngine();e.start();assert.equal(read(e,v(0,0,g),v(-20,20,-40)).direction,'东北');
  function tilt(z,at){const y=Math.sqrt(1-z*z);return read(e,v(0,g*y,g*z),v(25,-40*y,-40*z),at);}
  assert.match(tilt(0.7,1100).reference,/手机顶端/);
  assert.match(tilt(0.5,1200).reference,/车头/);
  assert.match(tilt(0.7,1300).reference,/车头/);
  assert.match(tilt(0.9,1400).reference,/手机顶端/);
});

test('拒绝不可靠精度、异常磁场和过弱水平磁场；低精度明确提示',()=>{
  const e=new CompassEngine();e.start();let at=1000;
  for(const [field,accuracy]of[[v(0,25,-40),0],[v(0,25,-40),NaN],[v(0,25,-40),4],
    [v(NaN,0,0),3],[v(0,0,0),3],[v(0,0,1000),3],[v(0,0,-40),3]]){
    assert.equal(read(e,v(0,0,g),v(0,25,-40),at+=50).valid,true);
    const s=read(e,v(0,0,g),field,at+=50,accuracy);assert.equal(s.valid,false);
  }
  const f=new CompassEngine();f.start();const s=read(f,v(0,0,g),v(0,25,-40),1000,1);
  assert.equal(s.valid,true);assert.match(s.status,/精度较低/);
});

test('拒绝乱序、姿态无效和过期；恢复、停止与快照隔离不伪造方向',()=>{
  const e=new CompassEngine();e.start();let s=read(e,v(0,0,g),v(0,25,-40));assert.equal(s.valid,true);
  e.sample(v(25,0,-40),3,999);close(e.state.heading,0);
  e.sample(v(25,0,-40),3,1250);assert.equal(e.state.valid,false);
  s=read(e,v(0,0,g),v(25,0,-40),1300);close(s.heading,270);
  e.tick(1900);assert.equal(e.state.valid,false);
  e.updateGravity(v(0,0,0),2000);e.sample(v(0,25,-40),3,2000);assert.equal(e.state.valid,false);
  s=read(e,v(0,0,g),v(0,25,-40),2100);close(s.heading,0);s.heading=180;close(e.state.heading,0);
  e.pause('停止');read(e,v(0,0,g),v(25,0,-40),2200);assert.equal(e.state.valid,false);
  e.start();assert.equal(e.state.valid,false);s=read(e,v(0,0,g),v(-25,0,-40),2300);close(s.heading,90);
  e.unavailable();assert.equal(e.state.available,false);assert.equal(e.state.running,false);
});
