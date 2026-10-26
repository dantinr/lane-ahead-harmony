const test=require('node:test');const assert=require('node:assert/strict');const load=require('./load-ets.cjs');
const {CarIconSpin}=load('CarIconSpin');
function run(speed){const e=new CarIconSpin();e.start();e.update(speed,1000);for(let t=1050;t<=2000;t+=50)e.tick(t);return e;}
test('车速km/h映射装饰转速，30/60/120公里每小时对应45/90/180度每秒，转速封顶',()=>{
  assert.equal(run(30).angle,45);assert.equal(run(60).angle,90);assert.equal(run(120).angle,180);assert.equal(run(200).angle,180);
});
test('停车和低速漂移不转，缺失、负数或异常车速立即冻结',()=>{
  assert.equal(run(0).angle,0);assert.equal(run(1.9).angle,0);
  for(const speed of [NaN,Infinity,-1,301]){const e=run(60),before=e.angle;e.update(speed,2050);e.tick(2100);assert.equal(e.angle,before);}
});
test('五秒无速度、暂停和恢复均不沿用旧速度；数据恢复后继续转动',()=>{
  const e=run(60);for(let t=2050;t<=6100;t+=50)e.tick(t);const frozen=e.angle;e.tick(6150);assert.equal(e.angle,frozen);
  e.update(60,6200);e.tick(6250);assert.notEqual(e.angle,frozen);e.pause();const paused=e.angle;
  e.update(200,6300);e.tick(6400);assert.equal(e.angle,paused);e.start();e.tick(6500);assert.equal(e.angle,paused);
});
test('拒绝时间倒退和重复数据，计时大间隔不追赶旋转',()=>{
  const e=run(60);const before=e.angle;e.update(120,999);e.tick(2000);assert.equal(e.angle,before);
  e.tick(1500);assert.equal(e.angle,before);e.tick(5000);assert.equal(e.angle,before);
  e.tick(5050);assert.equal(e.angle,before);e.update(60,5100);e.tick(5150);assert.equal(e.angle,(before+4.5)%360);
});
test('多圈角度有界并选择72帧，不积累无限角度',()=>{
  const e=new CarIconSpin();e.start();for(let t=1000;t<=30000;t+=50){e.update(120,t);const frame=e.tick(t);assert.ok(frame>=0&&frame<72);assert.ok(e.angle>=0&&e.angle<360);}
});
