import { IAMapNavi, IAMapNaviListener, IAMapLaneInfo, INaviInfo } from '@amap/amap_lbs_navi';
import { LaneHistoryStore } from './LaneHistoryStore';
import { LanePreviewEngine, LanePreviewState } from './LanePreview';
import { decodeLanes, routePoints } from './LaneSdkData';

export class LaneLookAheadSession {
  private navi: IAMapNavi;
  private store: LaneHistoryStore;
  private engine: LanePreviewEngine;
  private listener: IAMapNaviListener;
  private route: string = '';
  private active: boolean = false;
  private recalculating: boolean = false;
  private weakGps: boolean = false;
  private gpsEnabled: boolean = true;
  private disposed: boolean = false;
  private savedRevision: number = 0;
  private timer: number = -1;

  constructor(navi: IAMapNavi, filesDir: string) {
    this.navi = navi;
    this.store = new LaneHistoryStore(filesDir);
    this.engine = new LanePreviewEngine(this.store.load());
    this.listener = {
      onNaviInfoUpdate: (info: INaviInfo) => { this.update(info); },
      showLaneInfo: (info: IAMapLaneInfo | null) => {
        if (this.active && !this.recalculating && !this.weakGps && this.gpsEnabled) {
          this.engine.lanes(decodeLanes(info), Date.now());
        }
        this.publish();
      },
      hideLaneInfo: () => { this.engine.hideLanes(); this.publish(); },
      onUpdateNaviPath: () => { this.reloadRoute(); },
      onCalculateRouteSuccess: () => { this.reloadRoute(); },
      onReCalculateRoute: () => { this.replan(); },
      onReCalculateRouteForYaw: () => { this.replan(); },
      onReCalculateRouteForTrafficJam: () => { this.replan(); },
      onGpsSignalWeak: (weak: boolean) => {
        this.weakGps = weak;
        if (weak) { this.engine.suspend('定位信号弱，暂停车道提示'); }
        this.publish();
      },
      onGpsOpenStatus: (enabled: boolean) => {
        this.gpsEnabled = enabled;
        if (!enabled) { this.engine.suspend('系统定位已关闭'); }
        this.publish();
      },
      onStopNavi: () => { this.stop('导航已结束'); },
      onArriveDestination: () => { this.stop('已到达目的地'); }
    };
    navi.addAMapNaviListener(this.listener);
  }

  start(): void {
    if (this.disposed || this.active) { return; }
    this.active = true;
    this.weakGps = false;
    this.gpsEnabled = true;
    AppStorage.setOrCreate('laneAheadPanelExpanded', true);
    this.reloadRoute();
    this.timer = setInterval(() => { this.publish(); }, 1000);
  }

  replan(): void {
    this.recalculating = true;
    this.engine.suspend('路线重新规划中');
    this.publish();
  }

  private reloadRoute(): void {
    if (!this.active || this.disposed) { return; }
    try {
      const path = this.navi.getNaviPath();
      if (!path) { this.engine.suspend('正在读取前方引导点'); return; }
      this.route = path.getPathid().toString();
      this.engine.setRoute(this.route, routePoints(path));
      this.recalculating = false;
    } catch { this.engine.suspend('暂时无法读取前方引导点'); }
    this.publish();
  }

  private update(info: INaviInfo): void {
    if (this.disposed || !this.active || this.weakGps || !this.gpsEnabled || this.recalculating) { return; }
    try {
      const path = this.navi.getNaviPath();
      if (!path) { this.engine.suspend('等待当前路线'); this.publish(); return; }
      if (path.getPathid().toString() !== this.route) { this.reloadRoute(); }
      // pathID may be a route-selection key, whereas getPathid() is a native ID.
      // Compare IDs only after resolving the selection key through the public map.
      const reportedPath = this.navi.getNaviPaths()?.get(info.pathID);
      const matches = reportedPath ? reportedPath.getPathid().toString() === this.route :
        Number.isSafeInteger(info.pathID) && info.pathID.toString() === this.route;
      if (!matches) {
        this.engine.suspend('等待当前路线位置');
      } else {
        this.engine.progress(this.route, info.mCurSegIndex, info.mSegRemainDis, Date.now(), info.mType === 1);
      }
    } catch { this.engine.suspend('等待导航位置更新'); }
    this.publish();
  }

  private publish(): void {
    if (this.disposed) { return; }
    const count = AppStorage.get<number>('laneAheadPreviewCount') || 3;
    AppStorage.setOrCreate<LanePreviewState>('laneAheadLanePreview', this.engine.preview(count, Date.now()));
    if (this.savedRevision !== this.engine.history.revision && this.store.save(this.engine.history)) {
      this.savedRevision = this.engine.history.revision;
    }
  }

  stop(reason: string): void {
    this.active = false;
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
    this.engine.suspend(reason);
    this.publish();
  }

  dispose(): void {
    if (this.disposed) { return; }
    this.stop('等待实时导航');
    this.disposed = true;
    try { this.navi.removeAMapNaviListener(this.listener); } catch { /* SDK may already be destroyed. */ }
  }
}
