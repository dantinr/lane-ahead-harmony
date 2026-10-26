import { resourceManager } from '@kit.LocalizationKit';
import { UIContext } from '@kit.ArkUI';
import {
  AmapNaviParams, AMapNaviView, AMapPageType, IAMapNavi, IAMapNaviListener, INaviInfoCallback, NaviType
} from '@amap/amap_lbs_navi';
import { CarIconSession } from './CarIconSession';

export interface NativeRouteChoice {
  id: number;
  meters: number;
  seconds: number;
  label: string;
}

export class NativeRoutePageRequest {
  id: number;
  view: AMapNaviView = new AMapNaviView();
  car: CarIconSession;
  listener: IAMapNaviListener = {};
  params: AmapNaviParams;
  callbacks: INaviInfoCallback;
  navi: IAMapNavi;
  ui: UIContext;
  routes: NativeRouteChoice[] = [];
  selected: number = -1;
  message: string = '正在从当前位置规划路线…';
  planning: boolean = false;
  starting: boolean = false;
  started: boolean = false;
  timeout: number = -1;
  onChange: () => void = () => {};
  constructor(id: number, params: AmapNaviParams, callbacks: INaviInfoCallback,
    navi: IAMapNavi, ui: UIContext, resources: resourceManager.ResourceManager) {
    this.params = params; this.callbacks = callbacks; this.navi = navi; this.ui = ui;
    this.id = id; this.car = new CarIconSession(navi, this.view, resources);
  }
}

// An owned SDK view makes dynamic car icons possible. Only a numeric session ID
// enters the router; destinations, SDK objects and keys stay in memory.
export class NativeRoutePageSession {
  private sequence: number = 0;
  private current: NativeRoutePageRequest | undefined = undefined;
  private foreground: boolean = true;

  async show(params: AmapNaviParams, callbacks: INaviInfoCallback, navi: IAMapNavi,
    resources: resourceManager.ResourceManager, ui?: UIContext): Promise<void> {
    if (!ui) { throw new Error('Missing navigation UI context'); }
    this.close();
    const request = new NativeRoutePageRequest(++this.sequence, params, callbacks, navi, ui, resources);
    this.current = request;
    // This component is the navigation view. Route planning and confirmation
    // happen explicitly, before it receives permission to start GPS navigation.
    params.setNeedCalculateRouteWhenPresent(false);
    request.car.setForeground(this.foreground);
    request.car.setVisible(false);
    const active = (): boolean => this.current === request;
    let simulated: boolean = false;
    request.listener = {
      onInitNaviSuccess: () => { if (active()) { this.plan(request.id); } },
      onInitNaviFailure: () => {
        if (active()) { this.fail(request, '导航初始化失败，请返回重试'); callbacks.onInitNaviFailure?.(); }
      },
      onStartNavi: (type: number) => {
        if (!active()) { return; }
        if (request.started && type === NaviType.GPS) { return; }
        if (!request.starting || type !== NaviType.GPS) {
          try { navi.stopNavi(); } catch { /* Ignore unsolicited starts. */ }
          this.fail(request, '未能启动 GPS 导航，请重试'); return;
        }
        request.starting = false; request.started = true; this.clearTimeout(request); request.onChange();
        try { request.view.recoverLockMode(); } catch { /* SDK location may still be pending. */ }
        simulated = type !== NaviType.GPS; callbacks.onStartNavi?.(type);
      },
      onCalculateRouteFailureForResult: (result) => {
        if (active()) {
          this.fail(request, '路线规划失败，请检查网络和定位后重试');
          callbacks.onCalculateRouteFailure?.(result?.errorCode || -1);
        }
      },
      onCalculateRouteSuccess: (result) => {
        if (!active()) { return; }
        if (!request.started) {
          this.clearTimeout(request); request.planning = false;
          const routes: NativeRouteChoice[] = [];
          try {
            const paths = navi.getNaviPaths();
            Array.from(result?.routeId || new Int32Array()).forEach((id: number) => {
              const path = paths?.get(id);
              if (!path) { return; }
              const meters = path.getAllLength(), seconds = path.getAllTime();
              if (!Number.isFinite(meters) || meters <= 0 || !Number.isFinite(seconds) || seconds <= 0) { return; }
              routes.push({ id, meters, seconds, label: path.getLabels() || '路线方案' });
            });
          } catch { /* Missing summaries cannot be confirmed as a route. */ }
          request.routes = routes;
          request.message = routes.length > 0 ? '请选择路线后开始导航' : '未取得有效路线，请重试';
          request.selected = -1;
          if (routes.length > 0) { this.select(request.id, routes[0].id); }
          request.onChange();
        }
        callbacks.onCalculateRouteSuccess?.(result?.routeId || new Int32Array());
      },
      onReCalculateRoute: (type: number) => { if (active()) { callbacks.onReCalculateRoute?.(type); } },
      onArriveDestination: () => { if (active()) { callbacks.onArriveDestination?.(simulated); } }
    };
    params.goBack = (): void => { this.close(request.id); };
    try {
      navi.addAMapNaviListener(request.listener);
      await ui.getRouter().pushUrl({ url: 'pages/NativeRoute', params: { navigationSession: request.id } });
      if (!active()) { this.backIfCurrent(request); }
    } catch {
      if (active()) { this.close(request.id); }
      throw new Error('Navigation page could not be opened');
    }
  }

  request(id: number): NativeRoutePageRequest | undefined { return this.current?.id === id ? this.current : undefined; }

  setVisible(id: number, value: boolean): void { this.request(id)?.car.setVisible(value); }
  setForeground(value: boolean): void { this.foreground = value; this.current?.car.setForeground(value); }

  plan(id: number): void {
    const request = this.request(id);
    if (!request || request.planning || request.started || request.starting || !request.params.end) { return; }
    request.planning = true; request.routes = []; request.selected = -1;
    request.message = '正在从当前位置规划路线…'; request.onChange();
    this.clearTimeout(request);
    request.timeout = setTimeout(() => {
      if (this.current === request && request.planning) { this.fail(request, '规划超时，请检查网络和定位后重试'); }
    }, 25000);
    try {
      const strategy = request.navi.strategyConvert(false, false, false, false, true);
      if (!request.navi.calculateDriveRouteForPoi(null, request.params.end, request.params.wayPoints || null, strategy)) {
        this.fail(request, '暂时无法规划路线，请检查定位后重试');
      }
    } catch { this.fail(request, '暂时无法规划路线，请稍后重试'); }
  }

  select(id: number, route: number): boolean {
    const request = this.request(id);
    if (!request || request.planning || request.started || request.starting || !request.routes.some(
      (choice: NativeRouteChoice) => choice.id === route)) { return false; }
    try {
      if (!request.navi.selectRouteId(route)) { return false; }
      request.selected = route;
    } catch { return false; }
    try { request.view.displayOverview(); } catch { /* A late map cannot undo SDK route selection. */ }
    request.onChange(); return true;
  }

  start(id: number): void {
    const request = this.request(id);
    if (!request || !this.foreground || request.planning || request.started || request.starting ||
      !request.routes.some((choice: NativeRouteChoice) => choice.id === request.selected)) { return; }
    request.starting = true; request.message = '正在启动 GPS 导航…'; request.onChange();
    try {
      if (!request.navi.selectRouteId(request.selected) || !request.navi.startNavi(NaviType.GPS)) {
        this.fail(request, '未能启动 GPS 导航，请重试'); return;
      }
      if (this.current === request && request.starting) {
        request.timeout = setTimeout(() => {
          if (this.current === request && request.starting) {
            try { request.navi.stopNavi(); } catch { /* SDK unavailable. */ }
            this.fail(request, '启动超时，请返回重试');
          }
        }, 15000);
      }
    } catch { this.fail(request, '未能启动 GPS 导航，请重试'); }
  }

  private clearTimeout(request: NativeRoutePageRequest): void {
    if (request.timeout !== -1) { clearTimeout(request.timeout); request.timeout = -1; }
  }

  private fail(request: NativeRoutePageRequest, message: string): void {
    this.clearTimeout(request); request.planning = false; request.starting = false;
    request.message = message; request.onChange();
  }

  close(id?: number, navigateBack: boolean = true): void {
    const request = this.current;
    if (!request || (id !== undefined && id !== request.id)) { return; }
    this.current = undefined;
    this.clearTimeout(request); request.onChange = () => {};
    try { request.navi.removeAMapNaviListener(request.listener); } catch { /* SDK already stopped. */ }
    request.car.dispose();
    try { request.navi.stopNavi(); } catch { /* Component may already have stopped. */ }
    request.callbacks.onExitPage?.(AMapPageType.NAVI);
    if (navigateBack) { this.backIfCurrent(request); }
  }

  private backIfCurrent(request: NativeRoutePageRequest): void {
    try {
      const params = request.ui.getRouter().getParams() as Record<string, number>;
      if (params?.['navigationSession'] === request.id) { request.ui.getRouter().back(); }
    } catch { /* Router page already removed. */ }
  }
}

export const nativeRoutePage: NativeRoutePageSession = new NativeRoutePageSession();
