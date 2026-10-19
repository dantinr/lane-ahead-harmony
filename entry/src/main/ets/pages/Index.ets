import { LaneArrow } from '../components/LaneArrow';
import { createDemoRoute } from '../navigation/DemoRoute';
import { Lane, LookAheadEngine, PreviewStatus, RouteProgress, UpcomingJunction } from '../navigation/Guidance';

@Entry
@Component
struct Index {
  @State traveled: number = 0;
  @State previewCount: number = 3;
  @State speed: number = 60;
  @State playing: boolean = false;
  @State missingLanes: boolean = false;
  @State upcoming: UpcomingJunction[] = [];
  @State remaining: number = 2300;
  @State status: PreviewStatus = PreviewStatus.ACTIVE;
  @StorageLink('laneAheadForeground') @Watch('foregroundChanged') foreground: boolean = true;
  private engine: LookAheadEngine = new LookAheadEngine();
  private timer: number = -1;
  private lastTick: number = 0;

  aboutToAppear(): void {
    this.refresh();
  }

  aboutToDisappear(): void {
    this.pause();
  }

  onPageHide(): void {
    this.pause();
  }

  private foregroundChanged(): void {
    if (!this.foreground) {
      this.pause();
    }
  }

  private refresh(): void {
    const route = createDemoRoute(this.missingLanes);
    const state = this.engine.preview(route, new RouteProgress(route.id, this.traveled), this.previewCount);
    this.upcoming = state.upcoming;
    this.remaining = state.remainingRouteMeters;
    this.status = state.status;
    if (state.status === PreviewStatus.ARRIVED) {
      this.pause();
    }
  }

  private pause(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    this.playing = false;
  }

  private togglePlayback(): void {
    if (this.playing) {
      this.pause();
      return;
    }
    if (this.status === PreviewStatus.ARRIVED) {
      this.traveled = 0;
      this.refresh();
    }
    this.lastTick = Date.now();
    this.playing = true;
    this.timer = setInterval(() => {
      const now = Date.now();
      const elapsed = Math.max(0, Math.min(1, (now - this.lastTick) / 1000));
      this.lastTick = now;
      this.traveled = Math.min(2300, this.traveled + this.speed / 3.6 * elapsed);
      this.refresh();
    }, 250);
  }

  private nextJunction(): void {
    this.pause();
    this.traveled = this.upcoming.length > 0 ?
      Math.min(2300, this.upcoming[0].junction.metersFromStart + 1) : 2300;
    this.refresh();
  }

  private distance(meters: number): string {
    return meters >= 1000 ? (meters / 1000).toFixed(2) + ' km' : Math.ceil(meters) + ' m';
  }

  private lanes(item: UpcomingJunction): Lane[] {
    const guidance = item.junction.laneGuidance;
    return guidance === undefined ? [] : guidance.lanes;
  }

  @Builder
  countButton(count: number) {
    Button(count + ' 个', { type: ButtonType.Normal })
      .height(32)
      .fontSize(13)
      .fontColor(this.previewCount === count ? '#112217' : '#B2C7BB')
      .backgroundColor(this.previewCount === count ? '#B5F489' : '#1D352B')
      .borderRadius(10)
      .onClick(() => {
        this.previewCount = count;
        this.refresh();
      })
  }

  @Builder
  junctionCard(item: UpcomingJunction, index: number) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text((index + 1).toString())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0B1B17')
          .textAlign(TextAlign.Center)
          .width(27)
          .height(27)
          .borderRadius(14)
          .backgroundColor('#B5F489')
        Column({ space: 2 }) {
          Text(index === 0 ? '下一个路口' : '第 ' + (index + 1) + ' 个路口')
            .fontSize(11)
            .fontColor('#9FB5A8')
          Text(item.junction.name + ' · ' + item.junction.turn)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor('#F0F5EF')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(this.distance(Math.max(0, item.junction.metersFromStart - this.traveled)))
          .fontSize(23)
          .fontWeight(FontWeight.Bold)
          .fontColor('#B5F489')
      }.width('100%')
      if (item.junction.laneGuidance === undefined) {
        Column({ space: 5 }) {
          Text('暂无该路口的车道信息').fontSize(15).fontColor('#E4CA92')
          Text('请以道路标志和标线为准').fontSize(12).fontColor('#A4B6A8')
        }.height(81).width('100%').justifyContent(FlexAlign.Center)
      } else {
        Row({ space: 7 }) {
          ForEach(this.lanes(item), (lane: Lane) => {
            LaneArrow({ lane: lane })
          }, (lane: Lane, laneIndex: number) => item.junction.id + '-' + laneIndex + '-' + this.missingLanes)
        }.width('100%').justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .padding(13)
    .borderRadius(18)
    .backgroundColor(index === 0 ? '#1C3B2D' : '#142C23')
    .border({ width: index === 0 ? 1 : 0, color: '#476D43' })
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Column({ space: 3 }) {
          Text('LaneAhead').fontSize(27).fontWeight(FontWeight.Bold).fontColor('#F0F5EF')
          Text('提前看清，接下来怎么走').fontSize(12).fontColor('#A8C0AF')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text('鸿蒙 · 演示').fontSize(11).fontColor('#B5F489')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor('#263F2E').borderRadius(12)
      }.width('100%')

      Row({ space: 6 }) {
        Text('预览前方').fontSize(14).fontColor('#C8D8CC').layoutWeight(1)
        this.countButton(2)
        this.countButton(3)
      }.width('100%')

      Text('演示路线 · 至终点 ' + this.distance(this.remaining))
        .fontSize(12).fontColor('#A4BBAA').width('100%')

      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.upcoming, (item: UpcomingJunction, index: number) => {
            this.junctionCard(item, index)
          }, (item: UpcomingJunction, index: number) => item.junction.id + '-' + index + '-' + this.missingLanes)
          if (this.upcoming.length === 0) {
            Column({ space: 10 }) {
              Text(this.status === PreviewStatus.ARRIVED ? '已到达演示终点' : '前方暂无需要提示的路口')
                .fontSize(19).fontColor('#B5F489')
              Text(this.status === PreviewStatus.ARRIVED ? '可以重置路线，继续体验' :
                '继续前行 ' + this.distance(this.remaining) + ' 到达终点')
                .fontSize(13).fontColor('#A4BBAA')
            }.width('100%').height(190).justifyContent(FlexAlign.Center)
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)

      Column({ space: 6 }) {
        Row() {
          Text('路线回放').fontSize(13).fontColor('#D6E2D7').layoutWeight(1)
          Text(Math.round(this.speed) + ' km/h').fontSize(13).fontColor('#B5F489')
        }.width('100%')
        Slider({ value: this.speed, min: 0, max: 100, step: 10 })
          .selectedColor('#B5F489').trackColor('#365042')
          .onChange((value: number) => { this.speed = value; })
        Row({ space: 7 }) {
          Button(this.playing ? '暂停' : (this.status === PreviewStatus.ARRIVED ? '重新播放' : '开始回放'))
            .layoutWeight(1).height(38).fontSize(14).fontColor('#132019').backgroundColor('#B5F489')
            .onClick(() => this.togglePlayback())
          Button('驶过路口').layoutWeight(1).height(38).fontSize(14)
            .fontColor('#D5E4D7').backgroundColor('#2B4738')
            .enabled(this.status !== PreviewStatus.ARRIVED)
            .onClick(() => this.nextJunction())
          Button('重置').height(38).fontSize(13).fontColor('#B2C7BB').backgroundColor('#223A2E')
            .onClick(() => { this.pause(); this.traveled = 0; this.refresh(); })
        }.width('100%')
        Row() {
          Text('模拟路口 B 缺少车道数据').fontSize(11).fontColor('#AFC2B2').layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.missingLanes })
            .selectedColor('#638E48').scale({ x: 0.8, y: 0.8 })
            .onChange((value: boolean) => { this.missingLanes = value; this.refresh(); })
        }.width('100%')
      }.width('100%').padding(12).backgroundColor('#142B22').borderRadius(16)

      Text('仅演示数据 · 非实时导航\n各路口车道独立显示，不代表连续可通行车道')
        .fontSize(10).fontColor('#8EA595').textAlign(TextAlign.Center).lineHeight(15)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .backgroundColor('#0B1B17')
  }
}
