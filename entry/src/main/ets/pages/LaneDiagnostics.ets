import { common } from '@kit.AbilityKit';
import { CollectionEvent, CollectionReason, LaneCollectionState } from '../navigation/LaneCollection';
import { LaneCollectionStore } from '../navigation/LaneCollectionStore';
import { LaneHistoryStore } from '../navigation/LaneHistoryStore';

@Entry
@Component
struct LaneDiagnostics {
  @State summary: LaneCollectionState = new LaneCollectionState();
  @State events: CollectionEvent[] = [];
  @State storedCount: number = 0;
  @StorageProp('laneAheadCollectionPersistenceError') diagnosticError: string = '';

  aboutToAppear(): void { this.refresh(); }

  private refresh(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.summary = new LaneCollectionStore(context.filesDir).load();
    const current = AppStorage.get<LaneCollectionState>('laneAheadCollection');
    if (current && current.startedAt > 0 && current.updatedAt >= this.summary.updatedAt) {
      this.summary = current;
    }
    this.events = this.summary.events.slice().reverse();
    this.storedCount = new LaneHistoryStore(context.filesDir).load().count(Date.now());
  }

  private time(at: number): string {
    if (!at) { return '暂无'; }
    return new Date(at).toLocaleString();
  }

  @Builder
  metric(label: string, value: number) {
    Column({ space: 5 }) {
      Text(value.toString()).fontSize(26).fontWeight(FontWeight.Bold).fontColor('#B5F489')
      Text(label).fontSize(12).fontColor('#B7C8BA')
    }.layoutWeight(1).padding(12).backgroundColor('#1D352B').borderRadius(10)
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Button('返回').height(32).fontSize(13).backgroundColor('#263F2E').fontColor('#B5F489')
          .onClick(() => { this.getUIContext().getRouter().back(); })
        Text('车道采集诊断').fontSize(21).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').layoutWeight(1)
        Button('刷新').height(32).fontSize(13).backgroundColor('#263F2E').fontColor('#B5F489')
          .onClick(() => { this.refresh(); })
      }.width('100%').padding(16)
      Scroll() {
        Column({ space: 12 }) {
          Text('最近一次导航').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').width('100%')
          Text(this.summary.status).fontSize(18).fontColor('#B5F489').width('100%')
          Text(this.summary.reason).fontSize(14).fontColor('#B7C8BA').width('100%')
          Text('开始：' + this.time(this.summary.startedAt) + '\n结束：' + this.time(this.summary.endedAt) +
            '\n最近更新：' + this.time(this.summary.updatedAt)).fontSize(12).fontColor('#9FB5A8').width('100%')
          Row({ space: 10 }) { this.metric('车道回调', this.summary.received); this.metric('有效车道回调', this.summary.decoded) }.width('100%')
          Row({ space: 10 }) { this.metric('通过路口确认', this.summary.confirmed); this.metric('文件写入成功', this.summary.writes) }.width('100%')
          Text('其中多组车道回调 ' + this.summary.alternate + ' 次，暂不用于路口学习。')
            .fontSize(12).fontColor('#9FB5A8').width('100%')
          Text('本机有效历史：' + this.storedCount + ' 条 · 最近文件写入：' + this.time(this.summary.lastSavedAt))
            .fontSize(13).fontColor('#B7C8BA').width('100%')
          Text('回调可能重复；通过确认仍需写入成功才会保留。写入次数含历史更新与撤销，不等于不同路口数量。')
            .fontSize(12).fontColor('#9FB5A8').width('100%')
          if (this.summary.historyWriteError) {
            Text(this.summary.historyWriteError).fontSize(14).fontColor('#FFD58A').width('100%')
          }
          if (this.diagnosticError) { Text(this.diagnosticError).fontSize(14).fontColor('#FFD58A').width('100%') }
          Text('最近未保存原因').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').width('100%')
          Text(this.summary.lastNotSaved || '暂无未保存原因').fontSize(14).fontColor('#FFD58A').width('100%')
          if (this.summary.lastNotSavedAt > 0) {
            Text(this.time(this.summary.lastNotSavedAt)).fontSize(12).fontColor('#9FB5A8').width('100%')
          }
          ForEach(this.summary.reasons, (reason: CollectionReason) => {
            Text(reason.message + ' · ' + reason.count + ' 次').fontSize(13).fontColor('#B7C8BA').width('100%')
          }, (reason: CollectionReason) => reason.message)
          Text('连续相同原因合并记录，次数表示原因出现的状态变化，不代表丢失的路口数量。')
            .fontSize(12).fontColor('#9FB5A8').width('100%')
          Text('最近事件（最多 60 条）').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').width('100%')
          ForEach(this.events, (event: CollectionEvent) => {
            Column({ space: 5 }) {
              Text(this.time(event.at)).fontSize(11).fontColor('#9FB5A8').width('100%')
              Text(event.message).fontSize(13).fontColor(event.warning ? '#FFD58A' : '#B7C8BA').width('100%')
            }.width('100%').padding(12).backgroundColor('#1D352B').borderRadius(8)
          })
          Text('仅在本机保留最近一次导航的计数与原因，不记录坐标、道路名称或完整轨迹。退出导航时保存摘要；异常退出时最近约 5 秒的诊断可能缺失。')
            .fontSize(12).fontColor('#9FB5A8').width('100%')
        }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%')
    }.height('100%').width('100%').backgroundColor('#0B1B17')
  }
}
