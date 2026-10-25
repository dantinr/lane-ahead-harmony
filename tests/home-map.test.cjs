const test = require('node:test');
const assert = require('node:assert/strict');
const load = require('./load-ets.cjs');
const { Place } = load('RoutePlanning');

function setup(options = {}) {
  const state = { statuses: [], located: 0, permissions: [], enabled: [] };
  const map = {
    getUiSettings: () => ({ setZoomControlsEnabled() {}, setScaleControlsEnabled() {} }),
    setOnMyLocationChangeListener(fn) { state.locationCallback = fn; },
    setMyLocationStyle() {},
    setMyLocationEnabled(enabled) { state.enabled.push(enabled); },
    moveCamera(camera) { state.camera = camera; },
    addMarker(marker) { state.marker = marker; return { remove() { state.removed = true; } }; }
  };
  const view = {
    onCreate() {}, getMapAsync(fn) { state.mapCallback = fn; if (!options.deferMap) fn(map); },
    onResume() {}, onPause() {}, onDestroy() { state.destroyed = true; }
  };
  const { HomeMap } = load('HomeMap', {
    '@kit.AbilityKit': { abilityAccessCtrl: { createAtManager: () => ({
      async requestPermissionsFromUser(_, permissions) {
        state.permissions = permissions;
        return { authResults: options.grants || [0, 0] };
      }
    }) } },
    '@kit.LocationKit': { geoLocationManager: { isLocationEnabled: () => options.location !== false } },
    '@amap/amap_lbs_common': {
      AMapPrivacyShowStatus: { DidShow: 1 }, AMapPrivacyInfoStatus: { DidContain: 1 },
      AMapPrivacyAgreeStatus: { DidAgree: 1 }
    },
    '@amap/amap_lbs_map3d': {
      MapsInitializer: { updatePrivacyShow() {}, updatePrivacyAgree() {}, setApiKey() {}, initialize() {} },
      MapViewManager: { getInstance: () => ({
        registerMapViewCreatedCallback(fn) { state.created = fn; },
        unregisterMapViewCreatedCallback(fn) { state.unregistered = fn === state.created; }
      }) },
      MyLocationStyle: class { myLocationType() {} },
      LatLng: class { constructor(latitude, longitude) { Object.assign(this, { latitude, longitude }); } },
      CameraUpdateFactory: { newLatLngZoom: (position, zoom) => ({ position, zoom }) },
      MarkerOptions: class { setPosition(value) { this.position = value; } setTitle(value) { this.title = value; } }
    }
  });
  state.controller = new HomeMap();
  state.open = () => {
    state.controller.prepare({}, 'a'.repeat(32), status => state.statuses.push(status), (longitude,latitude) => {
      state.located++; state.position = {longitude,latitude};
    });
    state.created(view, 'lane-ahead-home');
  };
  state.map = map;
  return state;
}

test('首页拒绝精确位置权限或关闭系统定位时不进入成功状态', async () => {
  for (const options of [{ grants: [0, -1] }, { location: false }]) {
    const state = setup(options);
    await assert.rejects(state.controller.authorize({}));
    assert.equal(state.located, 0);
    assert.equal(state.created, undefined);
  }
});

test('地图只接受有效且近期的位置，暂停后忽略更新', () => {
  const state = setup();
  state.open();
  try {
    const location = { latitude: 39.9, longitude: 116.3, accuracy: 20, timeStamp: Date.now() };
    state.locationCallback({ ...location, latitude: NaN });
    state.locationCallback({ ...location, timeStamp: Date.now() - 180000 });
    assert.equal(state.located, 0);
    state.locationCallback(location);
    assert.equal(state.located, 1);
    assert.deepEqual(state.position, {longitude:116.3,latitude:39.9});
    state.controller.pause();
    state.locationCallback(location);
    assert.equal(state.located, 1);
    assert.equal(state.enabled.at(-1), false);
  } finally { state.controller.destroy(); }
});

test('重新定位等待新位置后重新居中，不停留在上次缓存的地图中心', () => {
  const state = setup(); state.open();
  try {
    const fix = {latitude:39.9,longitude:116.3,accuracy:20,timeStamp:Date.now()};
    state.locationCallback(fix);
    state.controller.locate();
    state.locationCallback({...fix,longitude:117.2,latitude:39.1});
    assert.deepEqual({...state.camera.position}, {longitude:117.2,latitude:39.1});
  } finally { state.controller.destroy(); }
});

test('选中终点保持 GCJ-02 经纬度顺序，修改终点时移除旧标记', () => {
  const state = setup();
  state.open();
  try {
    state.controller.select(new Place('test', '测试终点', '公共地点', '116.277358,39.904898'));
    assert.deepEqual({ ...state.marker.position }, { latitude: 39.904898, longitude: 116.277358 });
    assert.equal(state.marker.title, '测试终点');
    state.controller.clearSelection();
    assert.equal(state.removed, true);
  } finally { state.controller.destroy(); }
});

test('销毁首页后注销回调并忽略异步地图初始化结果', () => {
  const state = setup({ deferMap: true });
  state.open();
  state.controller.destroy();
  state.mapCallback(state.map);
  assert.equal(state.destroyed, true);
  assert.equal(state.unregistered, true);
  assert.deepEqual(state.enabled, []);
});
