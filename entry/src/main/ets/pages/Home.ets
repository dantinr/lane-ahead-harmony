import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { MapViewComponent } from '@amap/amap_lbs_map3d';
import { HomeMap } from '../navigation/HomeMap';
import { loadMapConfiguration } from '../navigation/MapConfiguration';
import { AMapRouteService, Place } from '../navigation/RoutePlanning';
import { HttpRouteTransport } from '../navigation/HttpRouteTransport';
import { NativeNavigation } from '../navigation/NativeNavigation';
import { LanePanelOverlay } from '../components/LaneLookAheadPanel';
import { LaneHistoryStore } from '../navigation/LaneHistoryStore';
import { SearchCity } from '../navigation/SearchCity';
import { destinationSearchSession, SearchOrigin } from '../navigation/DestinationSearchSession';

PersistentStorage.persistProp('laneAheadLocationConsent', false);

@Entry
@Component
struct Home {
  @StorageLink('laneAheadLocationConsent') consent: boolean = false;
  @StorageLink('laneAheadForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State webKey: string = '';
  @State harmonyKey: string = '';
  @State mapReady: boolean = false;
  @State locating: boolean = false;
  @State located: boolean = false;
  @State locationStatus: string = '等待定位授权';
  @State city: string = '';
  @State destination: Place | undefined = undefined;
  @State starting: boolean = false;
  @State settings: boolean = false;
  @State message: string = '';
  private homeMap: HomeMap = new HomeMap();
  private cityTransport: HttpRouteTransport = new HttpRouteTransport();
  private searchCity: SearchCity = new SearchCity();
  private navigation: NativeNavigation = new NativeNavigation();
  private searchSession: number = 0;
  private searchOrigin: SearchOrigin | undefined = undefined;
  private visible: boolean = true;
  private alive: boolean = true;
  private previousKeyboardMode: KeyboardAvoidMode | undefined = undefined;

  aboutToAppear(): void {
    const config = loadMapConfiguration(this.context());
    this.webKey = config.webKey;
    this.harmonyKey = config.harmonyKey;
    if (this.consent) {
      this.initializeLocation();
    }
  }

  onPageShow(): void {
    this.visible = true;
    if (this.previousKeyboardMode === undefined) {
      this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
    }
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    if (this.consent && !this.mapReady) { this.initializeLocation(); }
    if (this.mapReady && this.consent) {
      this.beginCityLocation();
      this.located = false;
      this.homeMap.resume();
    }
    if (this.searchSession > 0) {
      const selected = destinationSearchSession.finish(this.searchSession);
      this.searchSession = 0;
      if (selected) {
        this.destination = selected;
        this.message = '';
        this.homeMap.select(selected);
      }
    }
  }

  onPageHide(): void {
    this.visible = false;
    this.restoreKeyboardMode();
    this.cancelCityLocation();
    this.homeMap.pause();
  }

  aboutToDisappear(): void {
    this.alive = false;
    destinationSearchSession.finish(this.searchSession);
    this.restoreKeyboardMode();
    this.cancelCityLocation();
    this.navigation.cancelPending();
    this.homeMap.destroy();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private restoreKeyboardMode(): void {
    if (this.previousKeyboardMode !== undefined) {
      this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode);
      this.previousKeyboardMode = undefined;
    }
  }

  private foregroundChanged(): void {
    if (!this.foreground) {
      this.cancelCityLocation();
      this.homeMap.pause();
    } else if (this.visible && this.mapReady) {
      this.beginCityLocation();
      this.located = false;
      this.homeMap.resume();
    }
  }

  private async initializeLocation(): Promise<void> {
    if (this.locating || !this.consent) {
      return;
    }
    if (!/^[a-f0-9]{32}$/i.test(this.harmonyKey)) {
      this.locationStatus = '请在设置中配置高德鸿蒙 Key';
      this.settings = true;
      return;
    }
    this.locating = true;
    this.located = false;
    this.beginCityLocation();
    this.locationStatus = '正在获取位置权限…';
    try {
      await this.homeMap.authorize(this.context());
      if (!this.alive || !this.visible) {
        return;
      }
      if (!this.mapReady) {
        this.homeMap.prepare(this.context(), this.harmonyKey,
          (status: string) => { this.locationStatus = status; },
          (longitude: number, latitude: number) => { this.receivedLocation(longitude, latitude); });
        this.mapReady = true;
      } else {
        this.homeMap.locate();
      }
      this.locationStatus = '正在定位当前位置…';
    } catch (error) {
      const reason = (error as Error).message;
      this.locationStatus = reason === '请在系统设置中允许精确位置权限，然后点击重新定位' ||
        reason === '请开启系统位置服务，然后点击重新定位' ? reason :
        '无法定位，请检查精确位置权限、系统定位开关和网络后重试';
      this.cancelCityLocation();
    } finally {
      this.locating = false;
    }
  }

  private beginCityLocation(): void {
    this.searchOrigin = undefined;
    this.cityTransport.cancelAll();
    this.searchCity.begin();
    this.syncCity();
  }

  private cancelCityLocation(): void {
    this.searchCity.cancel();
    this.cityTransport.cancelAll();
  }

  private syncCity(): void {
    this.city = this.searchCity.city;
  }

  private async receivedLocation(longitude: number, latitude: number): Promise<void> {
    if (!this.alive || !this.visible || !this.foreground) { return; }
    this.located = true;
    this.searchOrigin = { longitude: longitude, latitude: latitude, receivedAt: Date.now() };
    const updated = await this.searchCity.located(longitude, latitude, (lng: number, lat: number) => {
      return new AMapRouteService(this.cityTransport, this.webKey).cityAt(lng, lat);
    });
    if (updated && this.alive && this.visible && this.foreground) { this.syncCity(); }
  }

  private openSearch(): void {
    if (this.starting || this.searchSession > 0) { return; }
    this.searchSession = destinationSearchSession.begin(this.city, this.webKey, this.searchOrigin);
    const session = this.searchSession;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchDestination', params: { session: session } })
      .catch(() => {
        destinationSearchSession.finish(session);
        if (this.searchSession === session) { this.searchSession = 0; }
        this.message = '无法打开搜索，请重试';
      });
  }

  private clearDestination(): void {
    this.navigation.cancelPending();
    this.destination = undefined;
    this.homeMap.clearSelection();
    this.message = '';
  }

  private async startNavigation(): Promise<void> {
    const destination = this.destination;
    if (!destination || !this.located || this.starting) {
      return;
    }
    this.getUIContext().getFocusController().clearFocus();
    this.starting = true;
    try {
      await this.navigation.open(this.context(), this.harmonyKey, destination,
        (status: string) => { this.message = status; }, new LanePanelOverlay(this.getUIContext()));
    } catch (error) {
      this.message = (error as Error).message || '无法打开导航，请重试';
    } finally {
      this.starting = false;
    }
  }

  private async privacy(): Promise<void> {
    try {
      await this.context().startAbility({ action: 'ohos.want.action.viewData', uri: 'https://lbs.amap.com/pages/privacy/' });
    } catch {
      this.message = '请访问 https://lbs.amap.com/pages/privacy/ 阅读隐私政策';
    }
  }

  @Builder
  consentCard() {
    Column({ space: 16 }) {
      Text('从你的位置出发').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#F0F5EF')
      Text('高德地图、定位与导航服务将处理您的位置、设备及网络信息，用于显示当前位置、路线与语音引导。首次同意后申请精确位置权限，以后打开应用自动定位。')
        .fontSize(15).fontColor('#B7C8BA').lineHeight(24)
      Text('阅读高德隐私政策').fontSize(14).fontColor('#B5F489').onClick(() => { this.privacy(); })
      Button('同意并定位').width('100%').fontColor('#132019').backgroundColor('#B5F489')
        .onClick(() => { this.consent = true; this.initializeLocation(); })
    }.padding(24).width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Text('LaneAhead').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').layoutWeight(1)
        Button('我的').height(32).fontSize(13).fontColor('#B5F489').backgroundColor('#263F2E')
          .onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/My' }); })
        Button(this.settings ? '完成' : '设置').height(32).fontSize(13).fontColor('#B5F489').backgroundColor('#263F2E')
          .onClick(() => { this.settings = !this.settings; })
      }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
      if (!this.consent) {
        Column() {
          this.consentCard()
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Stack({ alignContent: Alignment.BottomEnd }) {
          if (this.mapReady) {
            MapViewComponent({ mapViewName: 'lane-ahead-home' }).width('100%').height('100%')
          } else {
            Text(this.locationStatus).fontColor('#B7C8BA').width('100%').textAlign(TextAlign.Center)
          }
          Button('重新定位').fontSize(13).height(36).fontColor('#132019').backgroundColor('#FFFFFF')
            .margin({ right: 12, bottom: 30 }).enabled(!this.locating && !this.starting)
            .onClick(() => { this.initializeLocation(); })
        }.width('100%').layoutWeight(1)
      }
      if (this.settings) {
        Scroll() {
          Column({ space: 10 }) {
            Text(this.webKey && this.harmonyKey ? '地图服务已默认配置' : '请配置地图服务 Key')
              .fontColor('#B7C8BA').fontSize(13).width('100%')
            Button('车道采集诊断').onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/LaneDiagnostics' }); })
            TextInput({ placeholder: '高德 Web 服务 Key', text: this.webKey }).type(InputType.Password)
              .fontColor('#F0F5EF').placeholderColor('#9FB5A8').backgroundColor('#1D352B')
              .onChange((value: string) => {
                if (value !== this.webKey) { this.webKey = value; this.clearDestination(); this.cancelCityLocation(); }
              })
            TextInput({ placeholder: '高德鸿蒙导航 Key', text: this.harmonyKey }).type(InputType.Password)
              .fontColor('#F0F5EF').placeholderColor('#9FB5A8').backgroundColor('#1D352B')
              .enabled(!this.mapReady).onChange((value: string) => { this.harmonyKey = value; })
            Button('应用配置并定位').onClick(() => { this.settings = false; this.initializeLocation(); })
            Button('指定起点规划').onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/PlanRoute' }); })
            Button('车道演示').onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/Index' }); })
            Text('导航页显示前方 2／3 个引导点。实际观测的车道仅保存在本机，历史参考保留 7 天。')
              .fontSize(12).fontColor('#B7C8BA').width('100%')
            Button('清除历史车道').onClick(() => {
              this.message = new LaneHistoryStore(this.context().filesDir).clear() ? '历史车道已清除' : '清除失败，请重试';
            })
            if (this.message) { Text(this.message).fontSize(12).fontColor('#E4CA92').width('100%') }
            Text('高德隐私政策').fontColor('#B5F489').onClick(() => { this.privacy(); })
          }.padding(16).width('100%')
        }.width('100%').constraintSize({ maxHeight: 300 })
      } else if (this.consent) {
        Column({ space: 10 }) {
          Text(this.locationStatus).fontSize(12).fontColor(this.located ? '#B5F489' : '#E4CA92').width('100%')
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text(this.destination ? this.destination.name : '你要去哪里？')
                .fontSize(19).fontWeight(FontWeight.Medium)
                .fontColor(this.destination ? '#F0F5EF' : '#B7C8BA').width('100%').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.destination ? this.destination.address || '已选择目的地' : '搜索地点、地址')
                .fontSize(12).fontColor('#9FB5A8').width('100%').maxLines(2)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text(this.destination ? '更换' : '搜索').fontSize(14).fontColor('#B5F489')
          }.width('100%').padding(16).backgroundColor('#1D352B').borderRadius(14)
            .enabled(!this.starting).onClick(() => { this.openSearch(); })
            .accessibilityText('搜索目的地')
          if (this.message) { Text(this.message).fontSize(12).fontColor('#E4CA92').width('100%') }
          Button(this.starting ? '正在打开导航…' : '开始导航').width('100%').height(46)
            .fontColor('#132019').backgroundColor('#B5F489')
            .enabled(this.located && this.destination !== undefined && !this.starting)
            .onClick(() => { this.startNavigation(); })
        }.width('100%').padding(16).backgroundColor('#142B22')
      }
    }.width('100%').height('100%').backgroundColor('#0B1B17')
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width);
        if (Number.isFinite(width) && width > 0) { AppStorage.setOrCreate('laneAheadWindowWidth', width); }
      })
  }
}
