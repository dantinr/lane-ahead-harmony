import { abilityAccessCtrl, common, PermissionRequestResult } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { AMapPrivacyAgreeStatus, AMapPrivacyInfoStatus, AMapPrivacyShowStatus } from '@amap/amap_lbs_common';
import {
  AMapNaviFactory, AmapNaviPage, AmapNaviParams, AMapPageType, NaviLatLng, NaviPoi, NaviSetting, NaviType
} from '@amap/amap_lbs_navi';
import { Place } from './RoutePlanning';
import { LaneLookAheadSession } from './LaneLookAheadSession';
import { NavigationHistorySession } from './NavigationHistoryStore';

export interface NavigationPanel {
  show(): void;
  hide(): void;
}

// The SDK obtains and map-matches the current position in GCJ-02. Do not pass
// raw system GPS coordinates or a Web-service route ID into this navigation session.
export class NativeNavigation {
  private generation: number = 0;
  private laneSession: LaneLookAheadSession | undefined = undefined;
  private lanePanel: NavigationPanel | undefined = undefined;
  private historySession: NavigationHistorySession | undefined = undefined;

  cancelPending(): void {
    this.generation += 1;
    this.laneSession?.dispose();
    this.laneSession = undefined;
    this.historySession?.finish('ended');
    this.historySession = undefined;
    this.lanePanel?.hide();
    this.lanePanel = undefined;
  }

  async open(context: common.UIAbilityContext, key: string, destination: Place,
    onStatus: (message: string) => void, lanePanel?: NavigationPanel): Promise<void> {
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
      this.laneSession?.dispose();
      this.laneSession = undefined;
      this.historySession?.finish('ended');
      this.historySession = undefined;
      this.lanePanel?.hide();
      this.lanePanel = undefined;
      let laneSession: LaneLookAheadSession | undefined = undefined;
      let historySession: NavigationHistorySession | undefined = undefined;
      let exited: boolean = false;
      const closeLaneSession = (): void => {
        laneSession?.dispose();
        historySession?.finish('ended');
        if (this.historySession === historySession) { this.historySession = undefined; }
        if (this.laneSession === laneSession) {
          this.laneSession = undefined;
          this.lanePanel?.hide();
          this.lanePanel = undefined;
        }
        laneSession = undefined;
      };
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
          if (exited || generation !== this.generation) { return; }
          historySession?.finish('failed');
          closeLaneSession();
          onStatus('导航初始化失败，请检查鸿蒙 Key 是否绑定当前签名的 AppID');
        },
        onCalculateRouteFailure: (code: number) => {
          if (exited || generation !== this.generation) { return; }
          historySession?.finish('failed');
          laneSession?.stop('路线规划失败，暂停车道提示');
          onStatus('导航路线规划失败（' + code + '），请检查网络、定位和导航服务权限');
        },
        onStartNavi: (type: NaviType) => {
          if (exited || generation !== this.generation || historySession) { return; }
          if (type !== NaviType.GPS) {
            exited = true;
            closeLaneSession();
            navi.stopNavi();
            AmapNaviPage.getInstance().exitRoutePage();
            onStatus('未能启动 GPS 导航，请重试');
            return;
          }
          closeLaneSession();
          historySession = new NavigationHistorySession(context.filesDir, destination.name, destination.address,
            destination.city);
          this.historySession = historySession;
          let plannedMeters: number = 0;
          try { plannedMeters = navi.getNaviPath()?.getAllLength() || 0; } catch { /* Optional route summary. */ }
          historySession.start(plannedMeters);
          laneSession = new LaneLookAheadSession(navi, context.filesDir, (arrived: boolean) => {
            if (generation === this.generation && !exited) { historySession?.finish(arrived ? 'arrived' : 'ended'); }
          });
          this.laneSession = laneSession;
          laneSession.start();
          this.lanePanel = lanePanel;
          try { lanePanel?.show(); } catch {
            onStatus('实时导航已开始，前方车道面板暂不可用');
            return;
          }
          onStatus('实时导航已开始');
        },
        onArriveDestination: (simulated: boolean) => {
          if (!simulated && !exited && generation === this.generation) {
            historySession?.finish('arrived');
            laneSession?.stop('已到达目的地', true);
            onStatus('已到达目的地');
          }
        },
        onReCalculateRoute: () => { if (!exited && generation === this.generation) { laneSession?.replan(); } },
        onExitPage: (pageType: AMapPageType) => {
          if (exited || generation !== this.generation) { return; }
          exited = true;
          closeLaneSession();
          // The SDK can retain its route page after navigation exits, without
          // repeating this page callback on the next start. Return to Home so a
          // new navigation always obtains a fresh SDK instance and listeners.
          if (pageType === AMapPageType.NAVI) { AmapNaviPage.getInstance().exitRoutePage(); }
          onStatus('已退出导航地图，可重新选择终点');
        }
      });
    } catch {
      this.historySession?.finish('failed');
      this.historySession = undefined;
      this.laneSession?.dispose();
      this.laneSession = undefined;
      this.lanePanel?.hide();
      this.lanePanel = undefined;
      throw new Error('无法打开导航，请检查鸿蒙导航 Key 或稍后重试');
    }
  }
}
