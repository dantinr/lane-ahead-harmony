const test=require('node:test');const assert=require('node:assert/strict');const load=require('./load-ets.cjs');
const {DrivingGEngine,GVector}=load('DrivingG');const G=9.80665;
const v=(x=0,y=0,z=0)=>new GVector(x,y,z);const upright=v(0,G,0);
function feed(engine,value,gravity=upright,start=4000,duration=1600,step=20){
  for(let at=start;at<=start+duration;at+=step){engine.updateGravity(gravity,at);engine.sample(value,at);}
}
function setup(gravity=upright,bias=v()){
  const engine=new DrivingGEngine();engine.activate(true);engine.calibrate();feed(engine,bias,gravity,1000,2100);
  return engine;
}
const near=(actual,expected)=>assert.ok(Math.abs(actual-expected)<0.002,`${actual} differs from ${expected}`);

test('未校准时不显示伪造零值，静止校准后去重力值为0g，校准过程不计峰值',()=>{
  const engine=new DrivingGEngine();engine.activate(true);feed(engine,v(),upright,1000,100);
  assert.equal(engine.state.valid,false);assert.equal(engine.state.calibrated,false);
  engine.calibrate();feed(engine,v(),upright,1200,1900);assert.equal(engine.state.calibrating,true);
  feed(engine,v(),upright,3120,100);assert.equal(engine.state.calibrated,true);assert.equal(engine.state.valid,true);
  assert.equal(engine.state.total,0);assert.equal(engine.state.peakTotal,0);
});

test('前后正负与左右正负方向正确，水平合成使用勾股而非三轴绝对值相加',()=>{
  const engine=setup();feed(engine,v(0.3*G,0,-0.4*G));
  near(engine.state.longitudinal,0.4);near(engine.state.lateral,0.3);near(engine.state.total,0.5);
  near(engine.state.peakAcceleration,0.4);near(engine.state.peakLateral,0.3);near(engine.state.peakTotal,0.5);
  feed(engine,v(-0.2*G,0,0.6*G),upright,6000,2000);
  near(engine.state.longitudinal,-0.6);near(engine.state.lateral,-0.2);near(engine.state.peakBraking,0.6);
  near(engine.state.peakAcceleration,0.4);
});

test('倾斜支架和横屏旋转校准后仍映射车身方向，竖直颠簸不混入水平G',()=>{
  for(const [gravity,linear] of [[v(G,0,0),v(2*G,-0.3*G,-0.4*G)],
    [v(0,Math.sqrt(3)/2*G,0.5*G),v(0.3*G,(0.4*0.5+2*Math.sqrt(3)/2)*G,(-0.4*Math.sqrt(3)/2+1)*G)]]){
    const engine=setup(gravity);assert.equal(engine.state.calibrated,true);feed(engine,linear,gravity);
    near(engine.state.longitudinal,0.4);near(engine.state.lateral,0.3);near(engine.state.total,0.5);
  }
});

test('平放无法确定车辆前方，保持未知并要求换安装姿态',()=>{
  const engine=setup(v(0,0,G));assert.equal(engine.state.calibrated,false);assert.equal(engine.state.valid,false);
  assert.match(engine.state.status,/勿平放/);assert.equal(engine.state.peakTotal,0);
});

test('校准期间移动或转动会重计静止窗口，不在运动中直接归零',()=>{
  const engine=new DrivingGEngine();engine.activate(true);engine.calibrate();feed(engine,v(0,0,0.6),upright,1000,2500);
  assert.equal(engine.state.calibrated,false);assert.equal(engine.state.calibrationProgress,0);
  feed(engine,v(),upright,3600,1000);feed(engine,v(),v(0.2*G,Math.sqrt(0.96)*G,0),4620,100);
  assert.equal(engine.state.calibrated,false);assert.ok(engine.state.calibrationProgress<0.1);
  feed(engine,v(),upright,4800,2200);assert.equal(engine.state.calibrated,true);
});

test('稳定残差作为偏置校准，校准后不把静态误差累积为G值',()=>{
  const bias=v(0.08,0.06,0.1);const engine=setup(upright,bias);feed(engine,bias);
  near(engine.state.total,0);feed(engine,v(bias.x+0.3*G,bias.y,bias.z-0.4*G),upright,6000);
  near(engine.state.total,0.5);
});

test('数据过期后清除当前有效性并保留峰值，乱序和非法数据不制造峰值',()=>{
  const engine=setup();feed(engine,v(0,0,-0.3*G));const peak=engine.state.peakTotal;
  engine.tick(6200);assert.equal(engine.state.valid,false);assert.equal(engine.state.peakTotal,peak);
  engine.sample(v(0,0,-50*G),5500);assert.equal(engine.state.peakTotal,peak);
  engine.updateGravity(upright,6300);engine.sample(v(NaN,0,0),6300);
  assert.equal(engine.state.valid,false);assert.equal(engine.state.peakTotal,peak);
  engine.updateGravity(upright,6320);engine.sample(v(),6320);near(engine.state.total,0);
});

test('线性和重力数据必须新鲜，缺少重力或姿态变化较大时不沿用旧轴',()=>{
  const engine=setup();engine.sample(v(0,0,-G),4000);assert.equal(engine.state.valid,false);
  engine.updateGravity(v(G,0,0),4020);engine.sample(v(0,0,-G),4020);
  assert.equal(engine.state.calibrated,false);assert.equal(engine.state.valid,false);
  assert.match(engine.state.status,/姿态变化/);assert.equal(engine.state.peakTotal,0);
});

test('滤波抑制单次短脉冲，暂停后不能更新，重新开始重置峰值且保留内存校准',()=>{
  const engine=setup();engine.updateGravity(upright,4000);engine.sample(v(0,0,-G),4000);
  assert.ok(engine.state.total<0.3);const peak=engine.state.peakTotal;
  engine.pause('后台暂停测量');engine.updateGravity(upright,4100);engine.sample(v(0,0,-5*G),4100);
  assert.equal(engine.state.valid,false);assert.equal(engine.state.peakTotal,peak);
  engine.activate(false);assert.equal(engine.state.calibrated,true);assert.equal(engine.state.peakTotal,peak);
  feed(engine,v(),upright,5000,400);near(engine.state.total,0);
  engine.activate(true);assert.equal(engine.state.peakTotal,0);assert.equal(engine.state.calibrated,true);
  engine.unavailable('传感器不可用');engine.tick(10000);assert.equal(engine.state.status,'传感器不可用');
  assert.equal(engine.state.running,false);assert.equal(engine.state.available,false);
});

test('采样过少不能只靠经过2秒就校准，峰值重置和快照不修改实时状态',()=>{
  const engine=new DrivingGEngine();engine.activate(true);engine.calibrate();feed(engine,v(),upright,1000,2100,100);
  assert.equal(engine.state.calibrated,false);feed(engine,v(),upright,3200,1900,100);
  assert.equal(engine.state.calibrated,true);feed(engine,v(0,0,-0.4*G),upright,6000);
  const copy=engine.snapshot();copy.peakTotal=99;assert.ok(engine.state.peakTotal<1);
  engine.resetPeaks();assert.equal(engine.state.peakTotal,0);assert.equal(engine.state.valid,true);
});
