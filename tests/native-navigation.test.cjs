const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { Place } = load('RoutePlanning');
const destination = new Place('hospital', '测试终点', '公共地点', '116.277358,39.904898', '北京市');
const key = 'a'.repeat(32);
const context = { filesDir: '/private/files', getApplicationContext: () => 'application-context' };

function setup(options = {}) {
  const calls = [];
  const statuses = [];
  const sdk = { calls, statuses, laneEvents: [], historyEvents: [], historySessions: [], gEvents: [] };
  let gActive=false;
  const params = {
    setNaviMode(mode) { this.mode = mode; },
    setUseInnerVoice(voice) { this.voice = voice; },
    setNeedCalculateRouteWhenPresent(enabled) { this.calculate = enabled; },
    setNeedDestroyDriveManagerInstanceWhenNaviExit(enabled) { this.destroyOnExit = enabled; }
  };
  const page = {
    showRoutePage(config, callback) { sdk.config = config; sdk.callback = callback; calls.push('page'); },
    exitRoutePage() { calls.push('exit'); }
  };
  const { NativeNavigation } = load('NativeNavigation', {
    './DrivingGSession': {drivingGSession:{
      start(){if(!gActive){gActive=true;sdk.gEvents.push('start');}},
      stop(){if(gActive){gActive=false;sdk.gEvents.push('stop');}}
    }},
    './NavigationHistoryStore': { NavigationHistorySession: class {
      constructor(filesDir, name, address, city) { this.name = name; this.city = city; sdk.historySessions.push(this); }
      start(meters) { this.meters = meters; sdk.historyEvents.push('start'); }
      finish(status) { sdk.historyEvents.push(status); }
    } },
    './LaneLookAheadSession': { LaneLookAheadSession: class {
      constructor(_, filesDir, onEnd) { sdk.filesDir = filesDir; this.onEnd = onEnd; sdk.endNavigation = onEnd; }
      start() { this.active = true; sdk.laneEvents.push('start'); }
      stop(_, arrived = false) { sdk.laneEvents.push('stop'); if (this.active) { this.active = false; this.onEnd?.(arrived); } }
      replan() { sdk.laneEvents.push('replan'); }
      dispose() { sdk.laneEvents.push('dispose'); if (this.active) { this.active = false; this.onEnd?.(false); } }
    } },
    '@kit.AbilityKit': { abilityAccessCtrl: { createAtManager: () => ({
      requestPermissionsFromUser: async (_, permissions) => {
        calls.push('permission');
        sdk.permissions = permissions;
        return options.permission ? options.permission() : { authResults: options.grants || [0, 0] };
      }
    }) } },
    '@kit.LocationKit': { geoLocationManager: { isLocationEnabled: () => options.location !== false } },
    '@amap/amap_lbs_common': {
      AMapPrivacyShowStatus: { DidShow: 1 }, AMapPrivacyInfoStatus: { DidContain: 1 },
      AMapPrivacyAgreeStatus: { DidAgree: 1 }
    },
    '@amap/amap_lbs_navi': {
      NaviSetting: {
        updatePrivacyShow() { calls.push('privacy-show'); },
        updatePrivacyAgree() { calls.push('privacy-agree'); }
      },
      AMapNaviFactory: { getAMapNaviInstance(ctx, providedKey) {
        calls.push('instance');
        sdk.context = ctx;
        sdk.key = providedKey;
        if (options.sdkThrows) throw Error('secret SDK error: ' + key);
        return { setUseInnerVoice() {}, stopNavi() { calls.push('stop'); },
          getNaviPath() { return { getAllLength: () => 17500 }; } };
      } },
      NaviLatLng: class { constructor(latitude, longitude) { Object.assign(this, { latitude, longitude }); } },
      NaviPoi: class { constructor(name, coordinate, poiId) { Object.assign(this, { name, coordinate, poiId }); } },
      NaviType: { GPS: 0, EMULATOR: 1 },
      AMapPageType: { NAVI: 1, ROUTE: 0 },
      AmapNaviParams: { buildForEnd(end) { params.end = end; return params; } },
      AmapNaviPage: { getInstance: () => page }
    }
  });
  sdk.navigation = new NativeNavigation();
  sdk.open = () => sdk.navigation.open(context, key, destination, message => statuses.push(message));
  return sdk;
}

test('未授予精确位置权限时不初始化 SDK 或打开地图', async () => {
  const sdk = setup({ grants: [0, -1] });
  await assert.rejects(sdk.open(), /精确位置权限/);
  assert.deepEqual(sdk.calls, ['permission']);
});

test('权限请求期间变更目标后不能打开过时的导航', async () => {
  let resolve;
  const sdk = setup({ permission: () => new Promise(done => { resolve = done; }) });
  const pending = sdk.open();
  sdk.navigation.cancelPending();
  resolve({ authResults: [0, 0] });
  await pending;
  assert.deepEqual(sdk.calls, ['permission']);
});

test('系统定位关闭时不以历史位置或手工起点启动导航', async () => {
  const sdk = setup({ location: false });
  await assert.rejects(sdk.open(), /系统定位尚未开启/);
  assert.deepEqual(sdk.calls, ['permission']);
});

test('真实导航使用当前位置和正确的经纬度顺序，开启语音与退出清理', async () => {
  const sdk = setup();
  await sdk.open();
  assert.deepEqual(sdk.calls, ['permission', 'privacy-show', 'privacy-agree', 'instance', 'page']);
  assert.deepEqual(sdk.permissions, ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
  assert.equal(sdk.context, 'application-context');
  assert.equal(sdk.config.start, undefined);
  assert.equal(sdk.config.end.coordinate.latitude, 39.904898);
  assert.equal(sdk.config.end.coordinate.longitude, 116.277358);
  assert.equal(sdk.config.end.poiId, 'hospital');
  assert.equal(sdk.config.mode, 0);
  assert.equal(sdk.config.voice, true);
  assert.equal(sdk.config.calculate, true);
  assert.equal(sdk.config.destroyOnExit, true);
  assert.deepEqual(sdk.statuses, []);
  sdk.callback.onStartNavi(0);
  assert.equal(sdk.historySessions[0].city,'北京市');
  assert.deepEqual(sdk.statuses, ['实时导航已开始']);
  assert.equal(sdk.filesDir, '/private/files');
  assert.deepEqual(sdk.laneEvents, ['start']);
});

test('误进入模拟导航时停止并退出，不能显示实时导航成功', async () => {
  const sdk = setup();
  await sdk.open();
  sdk.callback.onStartNavi(1);
  assert.deepEqual(sdk.calls.slice(-2), ['stop', 'exit']);
  assert.ok(!sdk.statuses.includes('实时导航已开始'));
  assert.deepEqual(sdk.laneEvents, []);
  assert.deepEqual(sdk.gEvents, []);
});

test('驾驶G值仅在GPS开始时采集，到达或停止立即结束，退出及新会话无旧监听',async()=>{
  const sdk=setup();await sdk.open();assert.deepEqual(sdk.gEvents,[]);
  sdk.callback.onStartNavi(0);sdk.callback.onStartNavi(0);assert.deepEqual(sdk.gEvents,['start']);
  sdk.endNavigation(false);assert.deepEqual(sdk.gEvents,['start','stop']);
  const old=sdk.callback;await sdk.open();sdk.callback.onStartNavi(0);
  old.onArriveDestination(false);assert.deepEqual(sdk.gEvents,['start','stop','start']);
  sdk.callback.onArriveDestination(false);assert.deepEqual(sdk.gEvents,['start','stop','start','stop']);
  await sdk.open();sdk.callback.onStartNavi(0);sdk.navigation.cancelPending();
  assert.deepEqual(sdk.gEvents.slice(-2),['start','stop']);
});

test('退出导航关闭整组地图页面，旧回调不能重启；首页重新进入创建新会话', async () => {
  const sdk = setup();
  const panelEvents = [];
  const panel = { show() { panelEvents.push('show'); }, hide() { panelEvents.push('hide'); } };
  await sdk.navigation.open(context, key, destination, () => {}, panel);
  assert.deepEqual(panelEvents, []);
  sdk.callback.onStartNavi(0);
  assert.deepEqual(panelEvents, ['show']);
  sdk.callback.onExitPage(1);
  assert.deepEqual(panelEvents, ['show','hide']);
  assert.deepEqual(sdk.laneEvents, ['start','dispose']);
  assert.equal(sdk.calls.filter(call => call === 'exit').length,1);
  assert.deepEqual(panelEvents, ['show','hide']);
  const oldCallback = sdk.callback;
  oldCallback.onStartNavi(0);
  oldCallback.onExitPage(0);
  assert.deepEqual(sdk.laneEvents, ['start','dispose']);
  assert.equal(sdk.calls.filter(call => call === 'exit').length,1);
  await sdk.open();
  sdk.callback.onStartNavi(0);
  sdk.callback.onExitPage(0);
  assert.deepEqual(sdk.laneEvents, ['start','dispose','start','dispose']);
});

test('SDK 异常不能将原始内容或 Key 带入界面错误', async () => {
  const sdk = setup({ sdkThrows: true });
  await assert.rejects(sdk.open(), error => /无法打开导航/.test(error.message) && !error.message.includes(key));
});

test('无效 Key 不触发权限或 SDK 调用', async () => {
  const sdk = setup();
  await assert.rejects(sdk.navigation.open(context, '', destination, () => {}), /鸿蒙导航 Key/);
  assert.deepEqual(sdk.calls, []);
});

test('仅真正开始GPS时创建历史，取消选路和模拟均不记录，重复开始不多记', async () => {
  const sdk = setup();
  await sdk.open();
  assert.equal(sdk.historySessions.length, 0);
  sdk.callback.onExitPage(0);
  assert.equal(sdk.historySessions.length, 0);
  await sdk.open(); sdk.callback.onStartNavi(1);
  assert.equal(sdk.historySessions.length, 0);
  await sdk.open(); sdk.callback.onStartNavi(0); sdk.callback.onStartNavi(0);
  assert.equal(sdk.historySessions.length, 1);
  assert.equal(sdk.historySessions[0].name, destination.name);
  assert.equal(sdk.historySessions[0].meters, 17500);
  assert.deepEqual(sdk.historyEvents, ['start']);
});

test('SDK停止、实际到达、选路页退出和取消均结束历史，旧会话不能改写新记录', async () => {
  const sdk = setup();
  await sdk.open(); sdk.callback.onStartNavi(0);
  sdk.endNavigation(false);
  assert.ok(sdk.historyEvents.includes('ended'));
  sdk.callback.onArriveDestination(false);
  assert.ok(sdk.historyEvents.includes('arrived'));
  const old = sdk.callback;
  await sdk.open(); sdk.callback.onStartNavi(0);
  const before = sdk.historyEvents.length;
  old.onArriveDestination(false); old.onStartNavi(0); old.onCalculateRouteFailure(1); old.onExitPage(1);
  assert.equal(sdk.historyEvents.length, before);
  sdk.callback.onCalculateRouteFailure(1);
  assert.ok(sdk.historyEvents.includes('failed'));
  sdk.navigation.cancelPending();
  assert.equal(sdk.historySessions.length, 2);
});
