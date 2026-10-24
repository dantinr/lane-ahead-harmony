import { AMapRouteService, Place, PlannedRoute, PlanningStep } from '../navigation/RoutePlanning';
import { HttpRouteTransport } from '../navigation/HttpRouteTransport';
import { common } from '@kit.AbilityKit';
import { NativeNavigation } from '../navigation/NativeNavigation';
import { LanePanelOverlay } from '../components/LaneLookAheadPanel';
import { loadMapConfiguration } from '../navigation/MapConfiguration';

@Entry
@Component
struct PlanRoute {
  @State apiKey: string = '';
  @State navigationKey: string = '';
  @State navigationStarting: boolean = false;
  @State navigationPrivacyAgreed: boolean = false;
  @State navigationPrivacyVisible: boolean = false;
  @State city: string = '';
  @State originText: string = '';
  @State destinationText: string = '';
  @State origin: Place | undefined = undefined;
  @State destination: Place | undefined = undefined;
  @State results: Place[] = [];
  @State choosingOrigin: boolean = false;
  @State routes: PlannedRoute[] = [];
  @State selectedId: string = '';
  @State previewCount: number = 3;
  @State busy: boolean = false;
  @State message: string = '';
  @StorageLink('laneAheadForeground') @Watch('foregroundChanged') foreground: boolean = true;
  private revision: number = 0;
  private transport: HttpRouteTransport = new HttpRouteTransport();
  private nativeNavigation: NativeNavigation = new NativeNavigation();

  aboutToAppear(): void {
    const config = loadMapConfiguration(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.apiKey = config.webKey;
    this.navigationKey = config.harmonyKey;
  }

  aboutToDisappear(): void {
    this.cancelRequests();
    this.apiKey = '';
    this.navigationKey = '';
    this.nativeNavigation.cancelPending();
  }

  onPageHide(): void {
    this.cancelRequests();
  }

  private foregroundChanged(): void {
    if (!this.foreground) {
      this.cancelRequests();
    }
  }

  private cancelRequests(): void {
    if (this.busy) {
      this.message = '请求已取消，可重新搜索或规划路线';
    }
    this.revision += 1;
    this.transport.cancelAll();
    this.busy = false;
  }

  private invalidate(resetOrigin: boolean, resetDestination: boolean): void {
    this.navigationPrivacyVisible = false;
    this.nativeNavigation.cancelPending();
    this.cancelRequests();
    if (resetOrigin) {
      this.origin = undefined;
    }
    if (resetDestination) {
      this.destination = undefined;
    }
    this.results = [];
    this.routes = [];
    this.selectedId = '';
    this.message = '';
  }

  private async search(isOrigin: boolean): Promise<void> {
    this.getUIContext().getFocusController().clearFocus();
    this.invalidate(isOrigin, !isOrigin);
    const requestRevision: number = this.revision;
    this.choosingOrigin = isOrigin;
    this.busy = true;
    try {
      const service = new AMapRouteService(this.transport, this.apiKey);
      const places = await service.search(isOrigin ? this.originText : this.destinationText, this.city);
      if (requestRevision !== this.revision) {
        return;
      }
      this.results = places;
      this.message = places.length === 0 ? '未找到地点，请换一个名称或检查城市' :
        '请选择' + (isOrigin ? '起点' : '终点') + '，核对地址后再规划';
    } catch (error) {
      if (requestRevision === this.revision) {
        this.message = (error as Error).message || '地点搜索失败，请重试';
      }
    } finally {
      if (requestRevision === this.revision) {
        this.busy = false;
      }
    }
  }

  private choose(place: Place): void {
    if (this.choosingOrigin) {
      this.origin = place;
      this.originText = place.name;
    } else {
      this.destination = place;
      this.destinationText = place.name;
    }
    this.results = [];
    this.message = '';
  }

  private async openNavigationPrivacy(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await context.startAbility({ action: 'ohos.want.action.viewData',
        uri: 'https://lbs.amap.com/pages/privacy/' });
    } catch {
      this.message = '无法打开隐私政策，请访问 https://lbs.amap.com/pages/privacy/';
    }
  }

  private async startCurrentNavigation(): Promise<void> {
    const destination = this.destination;
    const key: string = this.navigationKey.trim();
    if (destination === undefined || this.navigationStarting) {
      return;
    }
    this.getUIContext().getFocusController().clearFocus();
    if (!/^[a-fA-F0-9]{32}$/.test(key)) {
      this.message = '请先填写高德鸿蒙导航 Key，再开始导航';
      return;
    }
    if (!this.navigationPrivacyAgreed) {
      this.navigationPrivacyVisible = true;
      return;
    }
    this.navigationPrivacyVisible = false;
    this.navigationStarting = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.message = '正在获取当前位置并打开导航地图…';
      await this.nativeNavigation.open(context, key, destination,
        (message: string) => { this.message = message; }, new LanePanelOverlay(this.getUIContext()));
    } catch (error) {
      this.message = (error as Error).message || '无法打开导航，请重试';
    } finally {
      this.navigationStarting = false;
    }
  }

  private async plan(): Promise<void> {
    this.getUIContext().getFocusController().clearFocus();
    const origin = this.origin;
    const destination = this.destination;
    if (origin === undefined || destination === undefined) {
      this.message = '请先搜索并选择起点和终点';
      return;
    }
    this.invalidate(false, false);
    const requestRevision: number = this.revision;
    this.busy = true;
    try {
      const service = new AMapRouteService(this.transport, this.apiKey);
      const routes = await service.plan(origin, destination);
      if (requestRevision !== this.revision) {
        return;
      }
      this.routes = routes;
      this.message = routes.length === 0 ? '未找到可驾车路线，请选择其他地点' : '请选择一条路线';
    } catch (error) {
      if (requestRevision === this.revision) {
        this.message = (error as Error).message || '路线规划失败，请重试';
      }
    } finally {
      if (requestRevision === this.revision) {
        this.busy = false;
      }
    }
  }

  private distance(meters: number): string {
    return meters >= 1000 ? (meters / 1000).toFixed(1) + ' km' : Math.ceil(meters) + ' m';
  }

  private duration(route: PlannedRoute): string {
    return route.durationSeconds === undefined ? '耗时未知' : Math.ceil(route.durationSeconds / 60) + ' 分钟';
  }

  private summary(route: PlannedRoute): string {
    const roads: string[] = [];
    route.steps.forEach((step: PlanningStep) => {
      if (step.road.length > 0 && !roads.includes(step.road) && roads.length < 3) {
        roads.push(step.road);
      }
    });
    return roads.length > 0 ? '途经 ' + roads.join(' → ') : '至 ' + route.destination;
  }

  @Builder
  placeInput(isOrigin: boolean) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: isOrigin ? '输入起点名称' : '输入终点名称',
          text: isOrigin ? this.originText : this.destinationText })
          .layoutWeight(1).fontSize(15).fontColor('#F0F5EF').placeholderColor('#9FB5A8')
          .backgroundColor('#1D352B')
          .onChange((value: string) => {
            // Updating text after choosing a POI can also trigger onChange.
            if (value === (isOrigin ? this.originText : this.destinationText)) {
              return;
            }
            if (isOrigin) {
              this.originText = value;
            } else {
              this.destinationText = value;
            }
            this.invalidate(isOrigin, !isOrigin);
          })
        Button('搜索').height(38).fontSize(13).fontColor('#B5F489').backgroundColor('#294635')
          .enabled(!this.busy && !this.navigationStarting)
          .onClick(() => { this.search(isOrigin); })
      }.width('100%')
      if ((isOrigin ? this.origin : this.destination) !== undefined) {
        Text('已选' + (isOrigin ? '起点：' : '终点：') +
          (isOrigin ? this.origin?.name : this.destination?.name) + ' · ' +
          (isOrigin ? this.origin?.address : this.destination?.address))
          .fontSize(12).fontColor('#B5F489').width('100%')
      }
      if (this.choosingOrigin === isOrigin) {
        ForEach(this.results, (place: Place) => {
          Column({ space: 5 }) {
            Text(place.name).fontSize(16).fontColor('#F0F5EF').width('100%')
            Text(place.address || '暂无详细地址').fontSize(12).fontColor('#A4BBAA').width('100%')
          }.width('100%').padding(13).backgroundColor('#1D352B').borderRadius(12)
            .onClick(() => this.choose(place))
            .accessibilityText('选择' + (isOrigin ? '起点' : '终点') + place.name + place.address)
        }, (place: Place) => place.id + '-' + place.location)
      }
    }.width('100%')
  }

  @Builder
  selectedPreview(route: PlannedRoute) {
    Column({ space: 12 }) {
      Text('已选路线 · 至 ' + route.destination).fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor('#F0F5EF').width('100%')
      Column({ space: 6 }) {
        Text('前方多个路口的车道信息暂不可用').fontSize(16).fontColor('#E4CA92')
        Text('当前路线服务未提供完整路口及车道数据。下方仅预览起点后的路线指引；尚未开始实时导航。')
          .fontSize(13).fontColor('#B7C8BA').lineHeight(20)
      }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor('#3A3324').borderRadius(12)
      Row({ space: 8 }) {
        Text('路线指引预览').fontSize(14).fontColor('#D6E2D7').layoutWeight(1)
        Button(this.previewCount === 2 ? '查看 3 条' : '查看 2 条').height(32).fontSize(12)
          .fontColor('#B5F489').backgroundColor('#294635')
          .onClick(() => { this.previewCount = this.previewCount === 2 ? 3 : 2; })
      }.width('100%')
      ForEach(route.steps.slice(0, this.previewCount), (step: PlanningStep, index: number) => {
        Column({ space: 5 }) {
          Text((index + 1) + '. ' + step.instruction).fontSize(15).fontColor('#F0F5EF').width('100%')
          Text('本段 ' + this.distance(step.distanceMeters)).fontSize(12).fontColor('#A4BBAA').width('100%')
        }.width('100%').padding(12).backgroundColor('#142C23').borderRadius(12)
      }, (step: PlanningStep, index: number) => route.id + '-' + index)
      if (route.steps.length === 0) {
        Text('该路线暂无分段指引').fontSize(13).fontColor('#A4BBAA')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 3 }) {
          Text('LaneAhead').fontSize(27).fontWeight(FontWeight.Bold).fontColor('#F0F5EF')
          Text('当前位置出发，驾车导航').fontSize(12).fontColor('#A8C0AF')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('车道演示').height(32).fontSize(12).fontColor('#B5F489').backgroundColor('#263F2E')
          .onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/Index' }); })
      }.width('100%')
      Scroll() {
        Column({ space: 14 }) {
          Column({ space: 10 }) {
            Text('规划驾车路线').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').width('100%')
            TextInput({ placeholder: '高德 Web 服务 Key', text: this.apiKey })
              .type(InputType.Password).fontSize(14).fontColor('#F0F5EF').placeholderColor('#9FB5A8')
              .backgroundColor('#1D352B')
              .onChange((value: string) => { this.apiKey = value; this.invalidate(true, true); })
            TextInput({ placeholder: '高德鸿蒙导航 Key', text: this.navigationKey })
              .type(InputType.Password).fontSize(14).fontColor('#F0F5EF').placeholderColor('#9FB5A8')
              .backgroundColor('#1D352B')
              .onChange((value: string) => {
                if (value !== this.navigationKey) {
                  this.navigationKey = value;
                  this.nativeNavigation.cancelPending();
                }
              })
            Text('Web Key 用于地点搜索，鸿蒙 Key 用于导航。Key 仅保存在当前页面内存。')
              .fontSize(11).fontColor('#A4BBAA').width('100%')
            TextInput({ placeholder: '城市，例如：上海', text: this.city })
              .fontSize(14).fontColor('#F0F5EF').placeholderColor('#9FB5A8').backgroundColor('#1D352B')
              .onChange((value: string) => { this.city = value; this.invalidate(true, true); })
            this.placeInput(false)
            Button(this.navigationStarting ? '正在打开导航…' : '从当前位置开始导航')
              .width('100%').height(44).fontSize(15).fontColor('#132019').backgroundColor('#B5F489')
              .enabled(!this.busy && !this.navigationStarting && this.destination !== undefined)
              .onClick(() => { this.startCurrentNavigation(); })
            if (this.navigationPrivacyVisible) {
              Column({ space: 10 }) {
                Text('定位与导航服务').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').width('100%')
                Text('导航使用高德定位与导航 SDK，会处理您的位置、设备及网络信息，用于地图、路线和语音引导。请阅读高德隐私政策，同意后将申请精确位置权限。')
                  .fontSize(13).fontColor('#D6E2D7').width('100%')
                Text('阅读高德隐私政策').fontSize(13).fontColor('#B5F489').width('100%')
                  .onClick(() => { this.openNavigationPrivacy(); })
                Row({ space: 10 }) {
                  Button('暂不使用').layoutWeight(1).height(40).fontColor('#D6E2D7').backgroundColor('#294635')
                    .onClick(() => { this.navigationPrivacyVisible = false; })
                  Button('同意并继续').layoutWeight(1).height(40).fontColor('#132019').backgroundColor('#B5F489')
                    .onClick(() => {
                      this.navigationPrivacyAgreed = true;
                      this.startCurrentNavigation();
                    })
                }.width('100%')
              }.width('100%').padding(12).backgroundColor('#263F2E').borderRadius(12)
            }
            Text('先搜索并选中终点，进入导航地图选路线，再点击开始导航。路线以导航地图中选择的方案为准。')
              .fontSize(12).fontColor('#A4BBAA').width('100%')
            Text('高德定位与导航隐私政策').fontSize(12).fontColor('#B5F489').width('100%')
              .onClick(() => { this.openNavigationPrivacy(); })
            Text('指定起点规划（可选）').fontSize(14).fontColor('#D6E2D7').width('100%')
            this.placeInput(true)
            Button(this.busy ? '正在请求地图服务…' : '规划路线').width('100%').height(42).fontSize(15)
              .fontColor('#132019').backgroundColor('#B5F489')
              .enabled(!this.busy && !this.navigationStarting && this.origin !== undefined && this.destination !== undefined)
              .onClick(() => { this.plan(); })
          }.width('100%').padding(14).backgroundColor('#142B22').borderRadius(16)

          if (this.message.length > 0) {
            Text(this.message).fontSize(13).fontColor('#E4CA92').width('100%')
          }
          ForEach(this.routes, (route: PlannedRoute, index: number) => {
            Column({ space: 7 }) {
              Text('方案 ' + (index + 1) + ' · ' + this.duration(route) + ' · ' + this.distance(route.distanceMeters))
                .fontSize(16).fontColor('#F0F5EF').width('100%')
              Text(this.summary(route)).fontSize(12).fontColor('#A4BBAA').width('100%')
              Button(this.selectedId === route.id ? '已选此路线' : '选择此路线').height(34).fontSize(13)
                .fontColor('#132019').backgroundColor('#B5F489')
                .onClick(() => { this.selectedId = route.id; this.message = ''; })
            }.width('100%').alignItems(HorizontalAlign.Start).padding(14).borderRadius(14)
              .backgroundColor(this.selectedId === route.id ? '#1C3B2D' : '#142C23')
          }, (route: PlannedRoute) => route.id)

          ForEach(this.routes.filter((route: PlannedRoute) => route.id === this.selectedId),
            (route: PlannedRoute) => {
              this.selectedPreview(route)
            }, (route: PlannedRoute) => route.id)
          Text('路线数据来自高德地图 · 路线规划预览').fontSize(10).fontColor('#8EA595')
        }.width('100%').padding({ bottom: 16 })
      }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .backgroundColor('#0B1B17')
  }
}
