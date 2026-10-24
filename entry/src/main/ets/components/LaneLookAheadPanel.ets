import { LanePreviewState, PreviewLane, PreviewRow } from '../navigation/LanePreview';

@Builder
export function laneLookAheadBuilder() {
  LaneLookAheadPanel()
}

@Component
struct LaneLookAheadPanel {
  @StorageLink('laneAheadLanePreview') preview: LanePreviewState = new LanePreviewState();
  @StorageLink('laneAheadPreviewCount') count: number = 3;
  @StorageLink('laneAheadPanelExpanded') expanded: boolean = true;
  @StorageProp('laneAheadWindowWidth') windowWidth: number = 360;

  private distance(meters: number): string {
    return meters >= 1000 ? (meters / 1000).toFixed(1) + ' km' : Math.ceil(meters) + ' m';
  }

  private date(timestamp: number): string {
    const date = new Date(timestamp);
    return (date.getMonth() + 1) + '/' + date.getDate();
  }

  @Builder
  laneStrip(lanes: PreviewLane[], history: boolean) {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(lanes, (lane: PreviewLane) => {
          Row({ space: 1 }) {
            if (lane.special) {
              Text(lane.special).fontSize(11).fontColor('#CBD7D1')
            } else {
              ForEach(lane.directions, (arrow: string) => {
                Text(arrow).fontSize(21).fontWeight(FontWeight.Bold)
                  .fontColor(lane.recommended.indexOf(arrow) >= 0 ? (history ? '#FFD58A' : '#B5F489') : '#8B9E94')
              }, (arrow: string) => arrow)
            }
          }.constraintSize({ minWidth: 30 }).height(30).justifyContent(FlexAlign.Center)
            .padding({ left: 4, right: 4 }).borderRadius(5)
            .backgroundColor(lane.recommended.length > 0 ? (history ? '#59452A' : '#2F5037') : '#24382D')
            .accessibilityText(lane.special || lane.directions.join('、') +
              (lane.recommended.length > 0 ? '，推荐' + lane.recommended.join('、') : ''))
        })
      }
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(32)
  }

  @Builder
  point(row: PreviewRow, index: number) {
    Column({ space: 3 }) {
      Row({ space: 5 }) {
        Text((index + 1) + ' · ' + this.distance(row.distance) + ' ' + row.action)
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor('#F1F6F0').layoutWeight(1)
        Text(row.source + (row.recordedAt > 0 ? ' ' + this.date(row.recordedAt) : ''))
          .fontSize(10).fontColor(row.source === '历史参考' ? '#FFD58A' : '#B7C8BA')
      }.width('100%')
      Text(row.road).fontSize(10).fontColor('#B7C8BA').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (row.lanes.length > 0) { this.laneStrip(row.lanes, row.source === '历史参考') }
    }.width('100%').padding({ top: 5, bottom: 5 })
  }

  build() {
    // The SDK provides a narrow centered slot. Center our wider panel inside it
    // so it remains within the window and above the SDK's full-route button.
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 2 }) {
      Row({ space: 6 }) {
        Text('前方车道').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#F1F6F0').layoutWeight(1)
        if (this.expanded) {
          Button(this.count + ' 个').height(26).fontSize(11).backgroundColor('#2D4837').fontColor('#B5F489')
            .onClick(() => { this.count = this.count === 3 ? 2 : 3; })
        }
        Button(this.expanded ? '收起' : '展开').height(26).fontSize(11).backgroundColor('#2D4837').fontColor('#B5F489')
          .onClick(() => { this.expanded = !this.expanded; })
      }.width('100%')
      if (this.expanded) {
        ForEach(this.preview.rows, (row: PreviewRow, index: number) => { this.point(row, index) },
          (row: PreviewRow) => row.id + row.distance + row.source + row.recordedAt + JSON.stringify(row.lanes))
        if (this.preview.liveLanes.length > 0) {
          Text('当前实时车道 · 未关联引导点').fontSize(10).fontColor('#B7C8BA').width('100%')
          this.laneStrip(this.preview.liveLanes, false)
        }
        Text(this.preview.status).fontSize(10).fontColor('#B7C8BA').width('100%')
        if (this.preview.rows.some((row: PreviewRow) => row.source === '历史参考')) {
          Text('历史观测 7 天内有效，仅供参考，以现场标线为准').fontSize(10).fontColor('#FFD58A').width('100%')
        }
      }
      }.width(this.expanded ? Math.max(200, Math.min(420, this.windowWidth - 24)) : 208)
        .padding(10).borderRadius(12).backgroundColor('#F2142B22')
        .margin({ bottom: this.expanded ? 56 : 6 })
    }.width('100%')
  }
}
