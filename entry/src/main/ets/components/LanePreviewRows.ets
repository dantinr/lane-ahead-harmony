import { PreviewLane, PreviewRow } from '../navigation/LanePreview';

@Component
export struct PreviewLaneStrip {
  @Prop lanes: PreviewLane[] = [];
  @Prop history: boolean = false;

  build() {
    Scroll() {
      Row({ space: 3 }) {
        ForEach(this.lanes, (lane: PreviewLane) => {
          Row({ space: 1 }) {
            if (lane.special) {
              Text(lane.special).fontSize(11).fontColor('#CBD7D1')
            } else {
              ForEach(lane.directions, (arrow: string) => {
                Text(arrow).fontSize(21).fontWeight(FontWeight.Bold)
                  .fontColor(lane.recommended.indexOf(arrow) >= 0 ? (this.history ? '#FFD58A' : '#B5F489') : '#8B9E94')
              }, (arrow: string) => arrow)
            }
          }.constraintSize({ minWidth: 26 }).height(30).justifyContent(FlexAlign.Center)
            .padding({ left: 3, right: 3 }).borderRadius(5)
            .backgroundColor(lane.recommended.length > 0 ? (this.history ? '#59452A' : '#2F5037') : '#24382D')
            .accessibilityText(lane.special || lane.directions.join('、') +
              (lane.recommended.length > 0 ? '，推荐' + lane.recommended.join('、') : ''))
        })
      }
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start).width('100%').height(32)
  }
}

// Both the navigation overlay and the explicitly fictional demo use these same rows.
@Component
export struct LanePreviewRows {
  @Prop rows: PreviewRow[] = [];

  private distance(meters: number): string {
    return meters >= 1000 ? (meters / 1000).toFixed(1) + ' km' : Math.ceil(meters) + ' m';
  }

  private date(timestamp: number): string {
    const date = new Date(timestamp);
    return date.getFullYear() + '/' + (date.getMonth() + 1) + '/' + date.getDate();
  }

  @Builder
  point(row: PreviewRow, index: number) {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Text((index + 1).toString()).width(16).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#F1F6F0')
        if (row.lanes.length > 0) {
          PreviewLaneStrip({ lanes: row.lanes, history: row.source === '历史参考' }).layoutWeight(1)
        } else {
          Text('暂无车道数据').fontSize(12).fontColor('#B7C8BA').height(32).layoutWeight(1)
        }
      }.width('100%')
      Row({ space: 5 }) {
        Text(this.distance(row.distance) + ' ' + row.action)
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor('#F1F6F0').layoutWeight(1)
        if (row.lanes.length > 0) {
          Text(row.source + (row.needsRefresh ? ' · 待更新' : ''))
            .fontSize(10).fontColor(row.source === '历史参考' ? '#FFD58A' : '#B7C8BA')
        }
      }.width('100%')
      Text(row.road).fontSize(10).fontColor('#B7C8BA').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (row.source === '历史参考') {
        Text('观测于 ' + this.date(row.recordedAt)).fontSize(10).fontColor('#FFD58A').width('100%')
      }
    }.width('100%').padding({ top: 5, bottom: 5 })
  }

  build() {
    Column({ space: 2 }) {
      ForEach(this.rows, (row: PreviewRow, index: number) => { this.point(row, index) },
        (row: PreviewRow) => row.id + row.distance + row.source + row.recordedAt + row.needsRefresh + JSON.stringify(row.lanes))
    }.width('100%')
  }
}
