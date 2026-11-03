import { common } from '@kit.AbilityKit';
import { LaneHistoryStore } from '../navigation/LaneHistoryStore';
import { LaneHistoryRow, laneHistoryRows } from '../navigation/LaneHistoryView';
import { PreviewLane } from '../navigation/LanePreview';
import { navigationTime } from '../navigation/NavigationHistory';

@Entry
@Component
struct LaneRecords {
  @State records: LaneHistoryRow[] = [];
  @State readError: string = '';
  @State onlyDue: boolean = false;

  aboutToAppear(): void { this.refresh(); }
  onPageShow(): void { this.refresh(); }

  private refresh(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const store = new LaneHistoryStore(context.filesDir);
    this.records = laneHistoryRows(store.load(), Date.now());
    this.readError = store.loadError;
  }

  private visibleRecords(): LaneHistoryRow[] {
    return this.onlyDue ? this.records.filter((row: LaneHistoryRow) => row.needsRefresh) : this.records;
  }

  @Builder
  lane(lane: PreviewLane, index: number) {
    Column({ space: 4 }) {
      Text('车道 ' + (index + 1)).fontSize(11).fontColor('#B7C8BA')
      Row({ space: 2 }) {
        ForEach(lane.directions, (arrow: string) => {
          Text(arrow).fontSize(26).fontWeight(FontWeight.Bold)
            .fontColor(lane.recommended.indexOf(arrow) >= 0 ? '#FFD58A' : '#9FB5A8')
        }, (arrow: string) => arrow)
      }
      if (lane.special) { Text(lane.special).fontSize(12).fontColor('#B7C8BA') }
      Text(lane.recommended.length > 0 ? '推荐 ' + lane.recommended.join(' ') : '未推荐')
        .fontSize(11).fontColor(lane.recommended.length > 0 ? '#FFD58A' : '#9FB5A8')
    }.constraintSize({ minWidth: 78 }).padding(10).borderRadius(8)
      .backgroundColor(lane.recommended.length > 0 ? '#59452A' : '#24382D')
  }

  @Builder
  card(row: LaneHistoryRow) {
    Column({ space: 10 }) {
      Text(row.road).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').width('100%')
      Text('历史参考' + (row.needsRefresh ? ' · 待更新' : '') + ' · ' + row.lanes.length + ' 条车道')
        .fontSize(13).fontColor('#FFD58A').width('100%')
      Text('最近观测：' + navigationTime(row.recordedAt)).fontSize(12).fontColor('#B7C8BA').width('100%')
      Scroll() {
        Row({ space: 6 }) {
          ForEach(row.lanes, (lane: PreviewLane, index: number) => { this.lane(lane, index); })
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).width('100%')
    }.width('100%').padding(16).backgroundColor('#1D352B').borderRadius(14)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Button('返回').height(32).fontSize(13).backgroundColor('#263F2E').fontColor('#B5F489')
          .onClick(() => { this.getUIContext().getRouter().back(); })
        Text('车道记录').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').layoutWeight(1)
        Button('刷新').height(32).fontSize(13).backgroundColor('#263F2E').fontColor('#B5F489')
          .onClick(() => { this.refresh(); })
      }.width('100%')
      Text('已保存 ' + this.records.length + ' 条 · 待更新 ' +
        this.records.filter((row: LaneHistoryRow) => row.needsRefresh).length + ' 条')
        .fontSize(15).fontColor('#B5F489').width('100%')
      Text('按最近观测排序，车道从左到右排列，黄色箭头为当时推荐。记录长期保留，满 3 个月标记待更新；再次经过收到有效车道后更新，以现场标线为准。')
        .fontSize(12).fontColor('#9FB5A8').width('100%')
      Row({ space: 8 }) {
        Button('全部').fontSize(13).backgroundColor(this.onlyDue ? '#263F2E' : '#446636').fontColor('#B5F489')
          .onClick(() => { this.onlyDue = false; })
        Button('待更新').fontSize(13).backgroundColor(this.onlyDue ? '#446636' : '#263F2E').fontColor('#B5F489')
          .onClick(() => { this.onlyDue = true; })
      }.width('100%')
      if (this.readError) { Text(this.readError).fontSize(13).fontColor('#FFD58A').width('100%') }
      if (this.visibleRecords().length === 0 && !this.readError) {
        Text(this.onlyDue ? '暂无待更新记录' : '还没有车道记录，真实导航中收到可关联的红绿灯路口车道后会自动保存。')
          .fontSize(15).fontColor('#B7C8BA').width('100%').padding({ top: 24, bottom: 24 })
      }
      List({ space: 12 }) {
        ForEach(this.visibleRecords(), (row: LaneHistoryRow) => {
          ListItem() { this.card(row); }
        }, (row: LaneHistoryRow) => row.id + ':' + row.recordedAt)
      }.width('100%').layoutWeight(1)
    }.padding(16).width('100%').height('100%').backgroundColor('#0B1B17')
  }
}
