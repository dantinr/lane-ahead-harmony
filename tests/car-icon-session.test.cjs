const test=require('node:test');const assert=require('node:assert/strict');const load=require('./load-ets.cjs');
function setup(options={}){
  const old={now:Date.now,set:global.setInterval,clear:global.clearInterval};
  const s={now:1000,listeners:new Set(),timers:[],cleared:[],frames:[],applied:[],released:[],removed:[]};
  Date.now=()=>s.now;global.setInterval=(fn,ms)=>{assert.equal(ms,50);s.timers.push(fn);return s.timers.length;};global.clearInterval=id=>s.cleared.push(id);
  const atlas={getImageInfoSync:()=>({size:{width:112,height:8064}}),readPixelsToBufferSync(){},release(){s.released.push('atlas');}};
  const image={PixelMapFormat:{RGBA_8888:3},AlphaType:{PREMUL:2},createImageSource(){if(options.decodeFail)throw Error('decode');return {createPixelMapSync:()=>atlas,release(){s.released.push('source');}};},
    createPixelMapSync(buffer,config){assert.equal(buffer.byteLength,112*112*4);assert.deepEqual(config.size,{width:112,height:112});assert.equal(config.srcPixelFormat,image.PixelMapFormat.RGBA_8888,'RGBA source bytes must not be interpreted as default BGRA');const frame={id:s.frames.length,release(){s.released.push(frame.id);}};s.frames.push(frame);return frame;}};
  const resources={getRawFileContentSync:file=>{assert.equal(file,'volkswagen-car-frames.png');return new Uint8Array(1);}};
  const config={otherSetting:'keep',setCarPixelMap(frame){this.car=frame;}};
  const view={getMapAsync(fn){s.mapReady=fn;},getViewOptions:()=>config,setViewOptions(value){assert.equal(value.otherSetting,'keep');s.applied.push(value.car?.id??null);}};
  const navi={addAMapNaviListener:fn=>s.listeners.add(fn),removeAMapNaviListener(fn){s.removed.push(fn);s.listeners.delete(fn);}};
  const {CarIconSession}=load('CarIconSession',{'@kit.ImageKit':{image},'@kit.PerformanceAnalysisKit':{hilog:{info(){},warn(){}}},'@amap/amap_lbs_navi':{NaviType:{GPS:0,EMULATOR:1}}});
  s.session=new CarIconSession(navi,view,resources);s.listener=[...s.listeners][0];s.config=config;
  s.location=(speed=60,extra={})=>s.listener.onLocationChange({time:s.now,locationType:0,accuracy:8,getSpeed:()=>speed,...extra});
  s.advance=(ms=1000)=>{const end=s.now+ms;while(s.now<end){s.now+=50;s.timers.at(-1)?.();}};
  s.cleanup=()=>{s.session.dispose();Date.now=old.now;global.setInterval=old.set;global.clearInterval=old.clear;};return s;
}
test('地图车标使用72个已解码帧，只在真实GPS导航时随速度更新并保留其他视图设置',()=>{
  const s=setup();try{assert.equal(s.frames.length,72);assert.deepEqual(s.applied,[0]);assert.equal(s.timers.length,0);
    s.listener.onStartNavi(1);s.location();s.advance();assert.deepEqual(s.applied,[0]);
    s.listener.onStartNavi(0);s.location();s.advance();assert.equal(s.applied.at(-1),18);
    const last=s.applied.length;s.location(0);s.advance();assert.equal(s.applied.length,last);
  }finally{s.cleanup();}
});
test('后台、离页和弱GPS立即暂停，恢复必须等新速度；停止及到达均取消计时',()=>{
  const s=setup();try{s.listener.onStartNavi(0);s.location();s.advance();
    for(const [pause,resume] of [[()=>s.session.setForeground(false),()=>s.session.setForeground(true)],
      [()=>s.session.setVisible(false),()=>s.session.setVisible(true)],
      [()=>s.listener.onGpsSignalWeak(true),()=>s.listener.onGpsSignalWeak(false)],
      [()=>s.listener.onGpsOpenStatus(false),()=>s.listener.onGpsOpenStatus(true)]]){
      pause();const before=s.applied.length;s.advance();assert.equal(s.applied.length,before);resume();s.advance();assert.equal(s.applied.length,before);
      s.location();s.advance();assert.ok(s.applied.length>before);
    }
    s.listener.onStopNavi();const last=s.applied.length;s.advance();assert.equal(s.applied.length,last);
    s.listener.onStartNavi(0);s.location();s.advance();s.listener.onArriveDestination();const arrived=s.applied.length;s.advance();assert.equal(s.applied.length,arrived);
  }finally{s.cleanup();}
});
test('不可靠定位与缺少速度冻结，旧位置和重复时间不覆盖；五秒掉帧停止旋转',()=>{
  const s=setup();try{s.listener.onStartNavi(0);s.location();s.advance();const count=s.applied.length;
    s.location(200,{time:1});s.location(200,{time:1000});s.location(60,{accuracy:200});s.advance();assert.equal(s.applied.length,count);
    s.location(60,{locationType:1});s.advance();assert.equal(s.applied.length,count);
    s.location(60,{getSpeed:undefined});s.advance();assert.equal(s.applied.length,count);
    s.location();s.advance(6000);const stale=s.applied.length;s.advance();assert.equal(s.applied.length,stale);
  }finally{s.cleanup();}
});
test('退出释放全部帧并仅移除自身监听，旧回调与定时器不能再操作视图',()=>{
  const s=setup();try{s.listener.onStartNavi(0);s.location();const timer=s.timers[0];s.session.dispose();
    const count=s.applied.length;timer();s.listener.onStartNavi(0);s.location();assert.equal(s.applied.length,count);
    assert.equal(s.applied.at(-1),null);assert.equal(s.removed.length,1);assert.equal(s.removed[0],s.listener);
    assert.equal(s.released.filter(x=>typeof x==='number').length,72);
    s.session.dispose();assert.equal(s.removed.length,1);
  }finally{s.cleanup();}
});
test('图片解码失败保留默认车标且不开动画，不影响导航事件订阅',()=>{
  const s=setup({decodeFail:true});try{assert.deepEqual(s.applied,[null]);s.listener.onStartNavi(0);s.location();assert.equal(s.timers.length,0);assert.equal(s.listeners.size,1);
  }finally{s.cleanup();}
});

test('SDK地图初始化和导航开始后重新应用静态Logo，弱定位也可显示，退出后忽略延迟地图回调',()=>{
  const s=setup();try{
    s.config.car=null;s.mapReady();assert.equal(s.config.car.id,0);
    s.listener.onGpsSignalWeak(true);s.config.car=null;s.listener.onStartNavi(0);assert.equal(s.config.car.id,0);
    assert.equal(s.timers.length,0);s.session.dispose();const count=s.applied.length;s.mapReady();assert.equal(s.applied.length,count);
  }finally{s.cleanup();}
});
