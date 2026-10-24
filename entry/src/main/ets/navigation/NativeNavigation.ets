import { abilityAccessCtrl, common, PermissionRequestResult } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { AMapPrivacyAgreeStatus, AMapPrivacyInfoStatus, AMapPrivacyShowStatus } from '@amap/amap_lbs_common';
import {
  AMapNaviFactory, AmapNaviPage, AmapNaviParams, NaviLatLng, NaviPoi, NaviSetting, NaviType
} from '@amap/amap_lbs_navi';
import { Place } from './RoutePlanning';

// The SDK obtains and map-matches the current position in GCJ-02. Do not pass
// raw system GPS coordinates or a Web-service route ID into this navigation session.
export class NativeNavigation {
  private generation: number = 0;

  cancelPending(): void {
    this.generation += 1;
  }

  async open(context: common.UIAbilityContext, key: string, destination: Place,
    onStatus: (message: string) => void): Promise<void> {
    if (!/^[a-fA-F0-9]{32}$/.test(key.trim())) {
      throw new Error('请填写 32 位高德鸿蒙导航 Key');
    }
    const generation: number = ++this.generation;
    let permission: PermissionRequestResult;
    try {
      permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
        ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
    } catch {
      throw new Error('无法申请位置权限，请检查系统权限设置后重试');
    }
    if (generation !== this.generation) {
      return;
    }
    if (permission.authResults.length !== 2 || permission.authResults.some((result: number) => result !== 0)) {
      throw new Error('实时导航需要精确位置权限，请在系统设置中允许后重试');
    }
    let locationEnabled: boolean = false;
    try {
      locationEnabled = geoLocationManager.isLocationEnabled();
    } catch {
      throw new Error('无法读取系统定位状态，请检查设备的位置服务');
    }
    if (!locationEnabled) {
      throw new Error('系统定位尚未开启，请开启位置服务后重试');
    }

    try {
      // Called only after the app has shown its SDK privacy explanation and the
      // user has agreed. No SDK instance is created before consent and permission.
      NaviSetting.updatePrivacyShow(AMapPrivacyShowStatus.DidShow, AMapPrivacyInfoStatus.DidContain, context);
      NaviSetting.updatePrivacyAgree(AMapPrivacyAgreeStatus.DidAgree, context);
      const navi = AMapNaviFactory.getAMapNaviInstance(context.getApplicationContext(), key.trim());
      navi.setUseInnerVoice(true);
      const coordinates: string[] = destination.location.split(',');
      const end = new NaviPoi(destination.name,
        new NaviLatLng(Number(coordinates[1]), Number(coordinates[0])), destination.id || null);
      // Omitting start makes the SDK use the current position. The native page
      // lets the user select a route before starting actual GPS navigation.
      const params = AmapNaviParams.buildForEnd(end);
      params.setNaviMode(NaviType.GPS);
      params.setUseInnerVoice(true);
      params.setNeedCalculateRouteWhenPresent(true);
      params.setNeedDestroyDriveManagerInstanceWhenNaviExit(true);
      AmapNaviPage.getInstance().showRoutePage(params, {
        onInitNaviFailure: () => {
          onStatus('导航初始化失败，请检查鸿蒙 Key 是否绑定当前签名的 AppID');
        },
        onCalculateRouteFailure: (code: number) => {
          onStatus('导航路线规划失败（' + code + '），请检查网络、定位和导航服务权限');
        },
        onStartNavi: (type: NaviType) => {
          if (type !== NaviType.GPS) {
            navi.stopNavi();
            AmapNaviPage.getInstance().exitRoutePage();
            onStatus('未能启动 GPS 导航，请重试');
            return;
          }
          onStatus('实时导航已开始');
        },
        onArriveDestination: (simulated: boolean) => {
          if (!simulated) {
            onStatus('已到达目的地');
          }
        },
        onExitPage: () => { onStatus('已退出导航地图，可重新选择终点'); }
      });
    } catch {
      throw new Error('无法打开导航，请检查鸿蒙导航 Key 或稍后重试');
    }
  }
}
