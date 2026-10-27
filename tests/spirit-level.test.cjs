const test=require('node:test');const assert=require('node:assert/strict');const load=require('./load-ets.cjs');
const {SpiritLevelEngine}=load('SpiritLevel');const {GVector}=load('DrivingG');
const g=9.80665;const rad=a=>a*Math.PI/180;const close=(a,b)=>assert.ok(Math.abs(a-b)<1e-7,`${a} != ${b}`);
function read(x,y,z){const e=new SpiritLevelEngine();e.start();e.sample(new GVector(x*g,y*g,z*g),1000);return e.snapshot();}

test('水平与四向倾斜具有正确角度、气泡方向及一度水平阈值',()=>{
  const flat=read(0,0,1);assert.equal(flat.valid,true);assert.equal(flat.level,true);close(flat.tilt,0);
  for(const angle of [-90,-30,-15,-1,-0.5,0.5,1,15,30,90]){
    for(const axis of ['x','y']){
      const v=Math.sin(rad(angle)),z=Math.cos(rad(angle));const s=read(axis==='x'?v:0,axis==='y'?v:0,z);
      close(s[axis==='x'?'roll':'pitch'],angle);close(s.tilt,Math.abs(angle));
      assert.equal(s.level,Math.abs(angle)<=1);
      assert.equal(Math.sign(s[axis==='x'?'bubbleX':'bubbleY']),Math.sign(angle)*(axis==='x'?1:-1));
      close(Math.hypot(s.bubbleX,s.bubbleY),Math.min(1,Math.abs(angle)/15));
    }
  }
});

test('复合倾斜以屏幕平面求总倾角，气泡不越界，重力幅值不改变角度',()=>{
  for(const tilt of [10,45,89])for(const direction of [0,45,135,225,315]){
    const x=Math.sin(rad(tilt))*Math.cos(rad(direction)),y=Math.sin(rad(tilt))*Math.sin(rad(direction)),z=Math.cos(rad(tilt));
    for(const factor of [0.8,1,1.2]){
      const s=read(x*factor,y*factor,z*factor);assert.equal(s.valid,true);close(s.tilt,tilt);
      assert.ok(Math.hypot(s.bubbleX,s.bubbleY)<=1+1e-9);close(s.bubbleX*y+s.bubbleY*x,0);
    }
  }
});

test('失效、屏幕朝下和超时撤下气泡，恢复不混入旧滤波值，快照隔离',()=>{
  const e=new SpiritLevelEngine();e.start();assert.equal(e.snapshot().valid,false);let at=1000;
  for(const v of [new GVector(NaN,0,g),new GVector(0,0,0),new GVector(0,0,13),new GVector(0,0,-g)]){
    e.sample(new GVector(0,0,g),at+=50);assert.equal(e.snapshot().valid,true);
    e.sample(v,at+=50);assert.equal(e.snapshot().valid,false);
  }
  e.sample(new GVector(0,0,g),at+=50);close(e.snapshot().tilt,0);
  e.sample(new GVector(g,0,0),at-1);e.sample(new GVector(g,0,0),NaN);close(e.snapshot().tilt,0);
  e.tick(at+501);assert.equal(e.snapshot().valid,false);
  e.sample(new GVector(g,0,0),at+=600);close(e.snapshot().tilt,90);
  const s=e.snapshot();s.tilt=0;close(e.snapshot().tilt,90);
  e.pause('暂停');e.sample(new GVector(0,0,g),at+=50);assert.equal(e.snapshot().valid,false);
  e.start();assert.equal(e.snapshot().valid,false);e.unavailable();assert.equal(e.snapshot().running,false);
});

test('低通滤波抑制抖动并逐步收敛，失联后首个样本直接恢复',()=>{
  const e=new SpiritLevelEngine();e.start();e.sample(new GVector(0,0,g),1000);
  const v=new GVector(g*0.5,0,g*Math.sqrt(0.75));e.sample(v,1050);
  assert.ok(e.snapshot().roll>0&&e.snapshot().roll<30);
  for(let at=1100;at<=3000;at+=50)e.sample(v,at);
  assert.ok(Math.abs(e.snapshot().roll-30)<0.001);
  e.sample(new GVector(0,0,g),4000);close(e.snapshot().tilt,0);
});
