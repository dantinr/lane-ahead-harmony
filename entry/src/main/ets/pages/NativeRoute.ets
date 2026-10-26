import { AMapNaviComponent } from '@amap/amap_lbs_navi';
import { NativeRouteChoice, NativeRoutePageRequest, nativeRoutePage } from '../navigation/NativeRoutePageSession';

@Entry
@Component
struct NativeRoute {
  @State ready: boolean = false;
  @State started: boolean = false;
  @State busy: boolean = true;
  @State message: string = '';
  @State routes: NativeRouteChoice[] = [];
  @State selected: number = -1;
  private session: number = 0;
  private request: NativeRoutePageRequest | undefined = undefined;
  private paths: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, number>;
    this.session = params?.['navigationSession'] || 0;
    this.request = nativeRoutePage.request(this.session);
    this.ready = this.request !== undefined;
    if (this.request) {
      this.request.onChange = () => { this.update(); };
      this.update();
    }
    if (this.ready) { this.paths.pushPath({ name: 'drive' }); }
  }

  onPageShow(): void { nativeRoutePage.setVisible(this.session, true); }
  onPageHide(): void { nativeRoutePage.setVisible(this.session, false); }
  aboutToDisappear(): void { nativeRoutePage.close(this.session, false); this.request = undefined; }
  onBackPress(): boolean { this.exit(); return true; }

  private exit(): void {
    if (nativeRoutePage.request(this.session)) { nativeRoutePage.close(this.session); }
    else { this.getUIContext().getRouter().back(); }
  }

  private update(): void {
    if (!this.request) { return; }
    this.started = this.request.started;
    this.busy = this.request.planning || this.request.starting;
    this.message = this.request.message;
    this.routes = this.request.routes.slice();
    this.selected = this.request.selected;
  }

  @Builder
  routeContent() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.request) {
          AMapNaviComponent({ appCustomerConfig: this.request.params, naviView: this.request.view })
            .width('100%').height('100%')
        }
        if (!this.started) {
          Column({ space: 10 }) {
            Row() {
              Button('返回').fontColor('#53665A').backgroundColor(Color.Transparent)
                .onClick(() => { this.exit(); })
              Text('选择路线').fontSize(20).fontWeight(FontWeight.Medium).fontColor('#17251D').layoutWeight(1)
              Button('重新规划').fontSize(13).backgroundColor('#EDF6EF').fontColor('#23864B')
                .enabled(!this.busy).onClick(() => { nativeRoutePage.plan(this.session); })
            }.width('100%')
            Text(this.message).fontSize(13).fontColor('#667A6D').width('100%')
            List({ space: 8 }) {
              ForEach(this.routes, (route: NativeRouteChoice, index: number) => {
                ListItem() {
                  Row({ space: 12 }) {
                    Column({ space: 4 }) {
                      Text('方案 ' + (index + 1) + ' · ' + route.label).fontSize(14).fontColor('#33483B')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(Math.ceil(route.seconds / 60) + ' 分钟 · ' + (route.meters / 1000).toFixed(1) + ' 公里')
                        .fontSize(18).fontWeight(FontWeight.Medium).fontColor('#17251D')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Text(this.selected === route.id ? '已选择' : '选择').fontSize(13).fontColor('#23864B')
                  }.width('100%').padding(12).borderRadius(12)
                    .backgroundColor(this.selected === route.id ? '#E0F1E4' : '#F2F5F3')
                    .onClick(() => { nativeRoutePage.select(this.session, route.id); })
                }
              }, (route: NativeRouteChoice) => String(route.id))
            }.width('100%').height(this.routes.length > 0 ? Math.min(this.routes.length, 3) * 84 : 0)
            Button(this.busy ? '请稍候…' : '开始 GPS 导航').width('100%').height(48)
              .backgroundColor('#23864B').fontColor(Color.White)
              .enabled(!this.busy && this.selected !== -1).onClick(() => { nativeRoutePage.start(this.session); })
          }.width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius({ topLeft: 20, topRight: 20 })
        }
      }.width('100%').height('100%')
    }.hideTitleBar(true).onReady(() => { nativeRoutePage.plan(this.session); })
      .onBackPressed(() => { this.exit(); return true; })
  }

  build() {
    Column() {
      if (this.ready) {
        Navigation(this.paths) {}
          .navDestination(this.routeContent).hideNavBar(true).hideTitleBar(true)
          .mode(NavigationMode.Stack).width('100%').height('100%')
      } else {
        Text('导航会话已结束').fontSize(20).fontColor('#F1F6F0')
        Button('返回首页').onClick(() => { this.exit(); })
      }
    }.width('100%').height('100%').backgroundColor('#0B1B17')
  }
}
