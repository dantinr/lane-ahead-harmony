import { IAMapNavi, IAMapNaviListener, IAMapLaneInfo, INaviInfo } from '@amap/amap_lbs_navi';
import { LaneHistoryStore } from './LaneHistoryStore';
import { LanePreviewEngine, LanePreviewState } from './LanePreview';
import { decodeLanes, routePoints } from './LaneSdkData';
import { LaneCollectionStore } from './LaneCollectionStore';
import { exactRouteId } from './LaneRouteIdentity';

export class LaneLookAheadSession {
  private navi: IAMapNavi;
  private store: LaneHistoryStore;
  private engine: LanePreviewEngine;
  private listener: IAMapNaviListener;
  private route: string = '';
  private routeMatch: string = '';
  private active: boolean = false;
  private recalculating: boolean = false;
  private weakGps: boolean = false;
  private gpsEnabled: boolean = true;
  private disposed: boolean = false;
  private savedRevision: number = 0;
  private diagnostics: LaneCollectionStore;
  private savedDiagnosticsRevision: number = -1;
  private diagnosticAttemptAt: number = 0;
  private timer: number = -1;
  private onEnd: ((arrived: boolean) => void) | undefined;

  constructor(navi: IAMapNavi, filesDir: string, onEnd?: (arrived: boolean) => void) {
    this.navi = navi;
    this.store = new LaneHistoryStore(filesDir);
    this.engine = new LanePreviewEngine(this.store.load());
    this.diagnostics = new LaneCollectionStore(filesDir);
    this.onEnd = onEnd;
    this.listener = {
      onNaviInfoUpdate: (info: INaviInfo) => { this.update(info); },
      showLaneInfo: (info: IAMapLaneInfo | null) => {
        if (this.disposed || !this.active) { return; }
        if (this.active && !this.recalculating && !this.weakGps && this.gpsEnabled) {
          this.engine.lanes(decodeLanes(info), Date.now());
        } else {
          this.engine.collection.receive(Date.now());
          this.engine.collection.report('callback_blocked', '暂停采集', this.recalculating ? '重算期间收到车道，暂不采集' :
            !this.gpsEnabled ? '定位已关闭，收到的车道不采集' : '定位信号弱，收到的车道不采集', Date.now(), true);
        }
        this.publish();
      },
      hideLaneInfo: () => {
        if (!this.active || this.disposed) { return; }
        this.engine.hideLanes(); this.publish();
      },
      showLaneInfoWithBytes: () => {
        if (!this.active || this.disposed) { return; }
        this.engine.collection.receive(Date.now());
        this.engine.collection.state.alternate += 1;
        this.engine.collection.report('alternate_lanes', '未保存',
          '收到多组车道回调，当前无法确认与路口的对应关系', Date.now(), true);
        this.publish();
      },
      onUpdateNaviPath: () => { this.reloadRoute(); },
      onCalculateRouteSuccess: () => { this.reloadRoute(); },
      onReCalculateRoute: () => { this.replan(); },
      onReCalculateRouteForYaw: () => { this.replan(); },
      onReCalculateRouteForTrafficJam: () => { this.replan(); },
      onGpsSignalWeak: (weak: boolean) => {
        if (!this.active || this.disposed) { return; }
        this.weakGps = weak;
        if (weak) { this.engine.suspend('定位信号弱，暂停车道提示'); }
        this.publish();
      },
      onGpsOpenStatus: (enabled: boolean) => {
        if (!this.active || this.disposed) { return; }
        this.gpsEnabled = enabled;
        if (!enabled) { this.engine.suspend('系统定位已关闭'); }
        this.publish();
      },
      onStopNavi: () => { this.stop('导航已结束'); },
      onArriveDestination: () => { this.stop('已到达目的地', true); }
    };
    navi.addAMapNaviListener(this.listener);
  }

  start(): void {
    if (this.disposed || this.active) { return; }
    this.active = true;
    this.weakGps = false;
    this.gpsEnabled = true;
    this.engine.collection.begin(Date.now(), this.engine.history.count(Date.now()));
    AppStorage.setOrCreate('laneAheadPanelExpanded', true);
    this.reloadRoute();
    this.publish(true);
    this.timer = setInterval(() => { this.publish(); }, 1000);
  }

  replan(): void {
    if (!this.active || this.disposed) { return; }
    this.recalculating = true;
    this.engine.suspend('路线重新规划中');
    this.publish();
  }

  private reloadRoute(): void {
    if (!this.active || this.disposed) { return; }
    try {
      const path = this.navi.getNaviPath();
      if (!path) {
        this.engine.suspend('尚未取得路线，等待前方引导点');
      } else {
        this.route = path.getPathid().toString();
        this.routeMatch = '';
        this.engine.setRoute(this.route, routePoints(path));
        this.recalculating = false;
      }
    } catch { this.engine.suspend('暂时无法读取前方引导点'); }
    this.publish();
  }

  private update(info: INaviInfo): void {
    if (this.disposed || !this.active || this.weakGps || !this.gpsEnabled || this.recalculating) { return; }
    try {
      const path = this.navi.getNaviPath();
      if (!path) { this.engine.suspend('等待当前路线'); this.publish(); return; }
      if (path.getPathid().toString() !== this.route) { this.reloadRoute(); }
      // The bridge may pass bigint/string even though INaviInfo declares number.
      // Resolve selection keys first; compare native IDs as exact decimal strings.
      const callbackId = exactRouteId(info.pathID);
      const selectionKey = callbackId ? Number(callbackId) : NaN;
      const reportedPath = Number.isSafeInteger(selectionKey) ? this.navi.getNaviPaths()?.get(selectionKey) : undefined;
      const matches = callbackId !== '' && (reportedPath ? reportedPath.getPathid().toString() : callbackId) === this.route;
      const kind = typeof info.pathID;
      if (!matches) {
        this.routeMatch = '';
        const reason = !callbackId ? '标识无效或数值精度不足' : reportedPath ? '选路映射不属于当前路线' : '原生标识不属于当前路线';
        this.engine.suspend('路线位置尚未匹配（' + kind + '：' + reason + '），暂停采集');
      } else {
        const method = reportedPath ? '选路映射' : '原生标识精确比较';
        const signature = kind + ':' + method;
        if (signature !== this.routeMatch) {
          this.routeMatch = signature;
          this.engine.collection.report('route_match', '路线位置已匹配',
            '路线位置已匹配（' + kind + '，' + method + '）', Date.now());
        }
        this.engine.progress(this.route, info.mCurSegIndex, info.mSegRemainDis, Date.now(), info.mType === 1);
      }
    } catch { this.engine.suspend('等待导航位置更新'); }
    this.publish();
  }

  private publish(force: boolean = false): void {
    if (this.disposed) { return; }
    const now = Date.now();
    const count = AppStorage.get<number>('laneAheadPreviewCount') || 3;
    AppStorage.setOrCreate<LanePreviewState>('laneAheadLanePreview', this.engine.preview(count, now));
    if (this.savedRevision !== this.engine.history.revision) {
      if (this.store.save(this.engine.history)) {
        this.savedRevision = this.engine.history.revision;
        this.engine.collection.persisted(now, this.engine.history.count(now));
        force = true;
      } else {
        this.engine.collection.writeFailed(this.store.lastSaveError || '车道历史写入本机失败', now);
      }
    }
    const snapshot = this.engine.collection.snapshot();
    AppStorage.setOrCreate('laneAheadCollection', snapshot);
    if (this.engine.collection.state.startedAt > 0 && this.savedDiagnosticsRevision !== this.engine.collection.revision &&
      (force || now - this.diagnosticAttemptAt >= 5000)) {
      this.diagnosticAttemptAt = now;
      const saved = this.diagnostics.save(snapshot);
      AppStorage.setOrCreate('laneAheadCollectionPersistenceError', saved ? '' : '采集诊断写入失败，当前状态仅在内存中可见');
      if (saved) { this.savedDiagnosticsRevision = this.engine.collection.revision; }
    }
  }

  stop(reason: string, arrived: boolean = false): void {
    if (!this.active || this.disposed) { return; }
    this.active = false;
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
    this.engine.finish(reason, Date.now());
    this.publish(true);
    this.onEnd?.(arrived);
  }

  dispose(): void {
    if (this.disposed) { return; }
    this.stop('已退出导航');
    this.disposed = true;
    try { this.navi.removeAMapNaviListener(this.listener); } catch { /* SDK may already be destroyed. */ }
  }
}
