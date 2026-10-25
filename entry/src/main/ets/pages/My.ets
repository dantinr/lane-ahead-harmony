import { common } from '@kit.AbilityKit';
import { NavigationHistory, NavigationRecord, navigationStatus, navigationTime, navigationDuration } from '../navigation/NavigationHistory';
import { NavigationHistoryStore } from '../navigation/NavigationHistoryStore';

@Entry
@Component
struct My {
  @State records: NavigationRecord[] = [];
  @State readError: string = '';
  @StorageLink('laneAheadNavigationHistoryError') saveError: string = '';

  aboutToAppear(): void { this.refresh(); }
  onPageShow(): void { this.refresh(); }

  private store(): NavigationHistoryStore {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new NavigationHistoryStore(context.filesDir);
  }

  private refresh(): void {
    const store = this.store();
    this.records = store.load().records;
    this.readError = store.error;
  }

  private remove(id: string): void {
    const store = this.store();
    const history = store.load();
    if (store.error) { this.readError = store.error; return; }
    history.remove(id);
    if (store.save(history)) { this.saveError = ''; this.refresh(); } else { this.saveError = store.error; }
  }

  private confirmClear(): void {
    this.getUIContext().showAlertDialog({
      title: '清空导航历史', message: '将删除本机保存的全部导航历史，车道数据与采集诊断会继续保留。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '清空', action: () => {
        const store = this.store();
        if (store.save(new NavigationHistory())) { this.saveError = ''; this.refresh(); } else { this.saveError = store.error; }
      } }
    });
  }

  @Builder
  historyCard(record: NavigationRecord) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(record.destination).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').layoutWeight(1)
        Text(navigationStatus(record.status)).fontSize(12)
          .fontColor(record.status === 'arrived' ? '#B5F489' : '#E4CA92')
      }.width('100%')
      if (record.address) { Text(record.address).fontSize(12).fontColor('#A4BBAA').width('100%') }
      Text('出发：' + navigationTime(record.startedAt) + '\n结束：' + navigationTime(record.endedAt))
        .fontSize(13).fontColor('#B7C8BA').lineHeight(21).width('100%')
      Row({ space: 8 }) {
        Text('导航时长：' + navigationDuration(record)).fontSize(12).fontColor('#B7C8BA').layoutWeight(1)
        Button('删除').height(30).fontSize(12).fontColor('#E4CA92').backgroundColor('#344133')
          .accessibilityText('删除导航历史' + record.destination)
          .onClick(() => { this.remove(record.id); })
      }.width('100%')
      if (record.plannedMeters > 0) {
        Text('出发时规划里程：' + (record.plannedMeters / 1000).toFixed(1) + ' 公里')
          .fontSize(12).fontColor('#9FB5A8').width('100%')
      }
    }.width('100%').padding(16).backgroundColor('#1D352B').borderRadius(14)
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Button('返回').height(32).fontSize(13).fontColor('#B5F489').backgroundColor('#263F2E')
          .onClick(() => { this.getUIContext().getRouter().back(); })
        Text('我的').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').layoutWeight(1)
        Button('刷新').height(32).fontSize(13).fontColor('#B5F489').backgroundColor('#263F2E')
          .onClick(() => { this.refresh(); })
      }.width('100%').padding(16)
      Scroll() {
        Column({ space: 14 }) {
          Text('导航历史').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#F0F5EF').width('100%')
          Text('已记录 ' + this.records.length + ' 次 · 已到达 ' +
            this.records.filter((record: NavigationRecord) => record.status === 'arrived').length + ' 次')
            .fontSize(14).fontColor('#B5F489').width('100%')
          Text('仅保存在本机，最多保留最近 200 次。导航时长含停留时间，规划里程以出发时选定路线为准。')
            .fontSize(12).fontColor('#9FB5A8').width('100%')
          Button('车道采集诊断').width('100%').fontColor('#B5F489').backgroundColor('#263F2E')
            .onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/LaneDiagnostics' }); })
          if (this.readError || this.saveError) {
            Text(this.readError || this.saveError).fontSize(13).fontColor('#FFD58A').width('100%')
          }
          if (this.records.length === 0 && !this.readError) {
            Column({ space: 10 }) {
              Text('还没有导航历史').fontSize(18).fontColor('#F0F5EF')
              Text('从首页选择目的地，真正开始导航后会自动记录。旧版本的行驶记录无法补录。')
                .fontSize(14).fontColor('#B7C8BA').textAlign(TextAlign.Center)
            }.width('100%').padding({ top: 36, bottom: 36, left: 16, right: 16 })
          }
          ForEach(this.records, (record: NavigationRecord) => { this.historyCard(record); }, (record: NavigationRecord) =>
            record.id + ':' + record.status + ':' + record.endedAt)
          if (this.records.length > 0 || this.readError) {
            Button('清空导航历史').width('100%').fontColor('#E4CA92').backgroundColor('#344133')
              .onClick(() => { this.confirmClear(); })
          }
        }.width('100%').padding(16).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor('#0B1B17')
  }
}
