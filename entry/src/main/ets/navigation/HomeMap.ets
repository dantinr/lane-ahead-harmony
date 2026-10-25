import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { AMapPrivacyAgreeStatus, AMapPrivacyInfoStatus, AMapPrivacyShowStatus } from '@amap/amap_lbs_common';
import {
  AMap, CameraUpdateFactory, LatLng, MapsInitializer, MapView, MapViewManager,
  Marker, MarkerOptions, MyLocationStyle
} from '@amap/amap_lbs_map3d';
import { Place } from './RoutePlanning';

export class HomeMap {
  private view: MapView | undefined;
  private map: AMap | undefined;
  private marker: Marker | undefined;
  private current: LatLng | undefined;
  private timer: number = -1;
  private active: boolean = true;
  private onStatus: (message: string) => void = () => {};
  private onLocated: (longitude: number, latitude: number) => void = () => {};
  private created = (view?: MapView, name?: string): void => {
    if (!view || name !== 'lane-ahead-home') {
      return;
    }
    this.view = view;
    view.onCreate();
    view.getMapAsync((map: AMap) => {
      if (this.view !== view) {
        return;
      }
      this.map = map;
      map.getUiSettings()?.setZoomControlsEnabled(false);
      map.getUiSettings()?.setScaleControlsEnabled(true);
      map.setOnMyLocationChangeListener((location: geoLocationManager.Location) => {
        if (!this.active || !Number.isFinite(location.latitude) || !Number.isFinite(location.longitude) ||
          Math.abs(location.latitude) > 90 || Math.abs(location.longitude) > 180 ||
          (location.latitude === 0 && location.longitude === 0) ||
          (location.timeStamp > 0 && Date.now() - location.timeStamp > 120000)) {
          return;
        }
        // The map SDK owns the location source and GCJ-02 conversion.
        const firstFix = this.current === undefined;
        this.current = new LatLng(location.latitude, location.longitude);
        if (firstFix) {
          map.moveCamera(CameraUpdateFactory.newLatLngZoom(this.current, 16));
        }
        this.clearTimer();
        this.onStatus(Number.isFinite(location.accuracy) && location.accuracy > 0 ?
          '已定位到当前位置 · 精度约 ' + Math.ceil(location.accuracy) + ' 米' : '已定位到当前位置');
        this.onLocated(location.longitude, location.latitude);
      });
      if (this.active) {
        this.resume();
      }
    });
  };

  async authorize(context: common.UIAbilityContext): Promise<void> {
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
        ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
      if (result.authResults.length !== 2 || result.authResults.some((value: number) => value !== 0)) {
        throw new Error('permission');
      }
    } catch {
      throw new Error('请在系统设置中允许精确位置权限，然后点击重新定位');
    }
    if (!geoLocationManager.isLocationEnabled()) {
      throw new Error('请开启系统位置服务，然后点击重新定位');
    }
  }

  prepare(context: common.UIAbilityContext, key: string,
    onStatus: (message: string) => void, onLocated: (longitude: number, latitude: number) => void): void {
    this.active = true;
    this.onStatus = onStatus;
    this.onLocated = onLocated;
    MapsInitializer.updatePrivacyShow(AMapPrivacyShowStatus.DidShow, AMapPrivacyInfoStatus.DidContain, context);
    MapsInitializer.updatePrivacyAgree(AMapPrivacyAgreeStatus.DidAgree, context);
    MapsInitializer.setApiKey(key);
    MapsInitializer.initialize(context);
    MapViewManager.getInstance().registerMapViewCreatedCallback(this.created);
  }

  resume(): void {
    this.active = true;
    this.view?.onResume();
    if (!this.map) {
      return;
    }
    this.onStatus('正在定位当前位置…');
    this.clearTimer();
    this.timer = setTimeout(() => {
      this.onStatus('暂未获取到当前位置，请到信号良好处点击重新定位');
    }, 15000);
    const style = new MyLocationStyle();
    style.myLocationType(MyLocationStyle.LOCATION_TYPE_LOCATE);
    this.map.setMyLocationStyle(style);
    this.map.setMyLocationEnabled(true);
  }

  locate(): void {
    this.current = undefined;
    this.map?.setMyLocationEnabled(false);
    this.resume();
  }

  select(destination: Place): void {
    if (!this.map) {
      return;
    }
    this.marker?.remove();
    const coords = destination.location.split(',');
    const target = new LatLng(Number(coords[1]), Number(coords[0]));
    const options = new MarkerOptions();
    options.setPosition(target);
    options.setTitle(destination.name);
    this.marker = this.map.addMarker(options);
    this.map.moveCamera(CameraUpdateFactory.newLatLngZoom(target, 15));
  }

  clearSelection(): void {
    this.marker?.remove();
    this.marker = undefined;
  }

  pause(): void {
    this.active = false;
    this.clearTimer();
    this.map?.setMyLocationEnabled(false);
    this.view?.onPause();
  }

  destroy(): void {
    this.pause();
    MapViewManager.getInstance().unregisterMapViewCreatedCallback(this.created);
    this.view?.onDestroy();
    this.view = undefined;
    this.map = undefined;
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }
}
