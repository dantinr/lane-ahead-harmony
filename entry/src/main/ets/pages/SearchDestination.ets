import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { AMapRouteService, Place } from '../navigation/RoutePlanning';
import { HttpRouteTransport } from '../navigation/HttpRouteTransport';
import { searchDestinationPlaces } from '../navigation/DestinationPlaceSearch';
import { visitedSearchCities } from '../navigation/VisitedCities';
import { NavigationHistoryStore } from '../navigation/NavigationHistoryStore';
import { destinationSearchSession } from '../navigation/DestinationSearchSession';
import { SearchHistory, SearchRecord } from '../navigation/SearchHistory';
import { SearchHistoryStore } from '../navigation/SearchHistoryStore';

interface SearchPageParams { session: number; }

@Entry
@Component
struct SearchDestination {
  @StorageLink('laneAheadForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State query: string = '';
  @State city: string = '';
  @State showScope: boolean = false;
  @State locatingCity: boolean = false;
  @State busy: boolean = false;
  @State searched: boolean = false;
  @State message: string = '';
  @State results: Place[] = [];
  @State recentSearches: SearchRecord[] = [];
  @State historyError: string = '';
  @State resultCity: string = '';
  @State automaticScope: boolean = true;
  @State visitedCities: string[] = [];
  private session: number = 0;
  private webKey: string = '';
  private transport: HttpRouteTransport = new HttpRouteTransport();
  private cityTransport: HttpRouteTransport = new HttpRouteTransport();
  private cityRevision: number = 0;
  private revision: number = 0;
  private visible: boolean = true;
  private previousKeyboardMode: KeyboardAvoidMode | undefined = undefined;

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as SearchPageParams;
    this.session = params?.session || 0;
    const request = destinationSearchSession.request(this.session);
    if (request) {
      this.city = request.city;
      this.webKey = request.webKey;
      if (!this.city) {
        this.resolveCity();
      }
    } else {
      this.message = '搜索已过期，请返回首页重新打开';
    }
    this.loadHistory();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const navigationStore = new NavigationHistoryStore(context.filesDir);
    this.visitedCities = visitedSearchCities(navigationStore.load().records);
    if (navigationStore.error) { this.message = '导航历史读取失败，暂时只搜索当前城市'; }
  }

  onPageShow(): void {
    this.visible = true;
    this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  onPageHide(): void { this.leave(); }
  aboutToDisappear(): void { this.leave(); }

  private leave(): void {
    this.visible = false;
    this.cancelSearch();
    this.cancelCity();
    if (this.previousKeyboardMode !== undefined) {
      this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode);
      this.previousKeyboardMode = undefined;
    }
  }

  private foregroundChanged(): void {
    if (!this.foreground) { this.cancelSearch(); this.cancelCity(); }
    else if (this.visible && this.automaticScope && !this.city.trim()) { this.resolveCity(); }
  }

  private cancelCity(): void {
    this.cityRevision += 1;
    this.cityTransport.cancelAll();
    this.locatingCity = false;
  }

  private async resolveCity(): Promise<void> {
    const origin = destinationSearchSession.request(this.session)?.origin;
    if (!origin || Date.now() - origin.receivedAt > 120000) {
      this.message = '尚未识别当前城市，请返回首页重新定位，或展开搜索范围填写城市';
      this.showScope = true;
      return;
    }
    this.cancelCity();
    const revision = this.cityRevision;
    this.locatingCity = true;
    try {
      const city = await new AMapRouteService(this.cityTransport, this.webKey).cityAt(origin.longitude, origin.latitude);
      if (revision !== this.cityRevision) { return; }
      this.city = city;
      if (!this.busy && !this.searched) { this.message = ''; }
    } catch {
      if (revision === this.cityRevision && !this.busy && !this.searched) {
        this.message = '未能识别当前城市，请返回首页重新定位，或填写搜索城市';
        this.showScope = true;
      }
    } finally {
      if (revision === this.cityRevision) { this.locatingCity = false; }
    }
  }

  private store(): SearchHistoryStore {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new SearchHistoryStore(context.filesDir);
  }

  private loadHistory(): void {
    const store = this.store();
    this.recentSearches = store.load().records;
    this.historyError = store.error;
  }

  private remember(query: string): void {
    const store = this.store();
    const history = store.load();
    if (!store.error) {
      history.remember(query);
      if (store.save(history)) { this.recentSearches = history.records; }
    }
    this.historyError = store.error;
  }

  private remove(query: string): void {
    const store = this.store();
    const history = store.load();
    if (!store.error) {
      history.remove(query);
      if (store.save(history)) { this.recentSearches = history.records; }
    }
    this.historyError = store.error;
  }

  private clearHistory(): void {
    this.getUIContext().showAlertDialog({
      title: '清空搜索记录', message: '将删除本机保存的搜索关键词，导航历史和车道数据会继续保留。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '清空', action: () => {
        const store = this.store();
        if (store.save(new SearchHistory())) { this.recentSearches = []; }
        this.historyError = store.error;
      } }
    });
  }

  private cancelSearch(): void {
    this.revision += 1;
    this.transport.cancelAll();
    this.busy = false;
  }

  private edit(): void {
    this.cancelSearch();
    this.results = [];
    this.searched = false;
    this.resultCity = '';
    this.message = '';
  }

  private async search(): Promise<void> {
    if (!this.visible || !this.foreground || !destinationSearchSession.request(this.session)) { return; }
    this.getUIContext().getFocusController().clearFocus();
    this.edit();
    const revision = this.revision;
    const query = this.query.trim();
    const city = this.city.trim();
    if (!query) { this.message = '请输入地点名称或地址'; return; }
    this.busy = true;
    try {
      const result = await searchDestinationPlaces(new AMapRouteService(this.transport, this.webKey), {
        query: query, city: city, visitedCities: this.visitedCities.slice(), allowFallback: this.automaticScope
      }, () => revision === this.revision && this.visible && this.foreground,
        (fallbackCity: string) => { this.message = '当前城市未找到，正在搜索去过的城市：' + fallbackCity; });
      if (!result || revision !== this.revision) { return; }
      this.results = result.places;
      this.searched = true;
      this.resultCity = result.explicitCity || result.usedVisitedCity ? result.city : '';
      this.remember(query);
      this.message = result.places.length === 0 ? result.checkedVisitedCities > 0 ?
        '当前城市及去过的城市均未找到相关地点，可在关键词前加城市继续搜索' :
        '未找到相关地点，试试其他关键词或修改搜索范围' :
        result.usedVisitedCity ? '当前城市未找到，以下为去过的城市中的结果' : '';
    } catch (error) {
      if (revision === this.revision) {
        this.message = (error as Error).message || '搜索失败，请重试';
        if (!city) { this.showScope = true; }
      }
    } finally {
      if (revision === this.revision) { this.busy = false; }
    }
  }

  private select(place: Place): void {
    if (!this.visible || !destinationSearchSession.select(this.session, place)) { return; }
    this.getUIContext().getFocusController().clearFocus();
    this.getUIContext().getRouter().back();
  }

  @Builder
  history() {
    Row() {
      Text('最近搜索').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#17251D').layoutWeight(1)
      if (this.recentSearches.length > 0 || this.historyError) {
        Button('清空搜索记录').fontSize(12).height(32).fontColor('#77837B').backgroundColor(Color.Transparent)
          .onClick(() => { this.clearHistory(); })
      }
    }.width('100%').margin({ bottom: 8 })
    ForEach(this.recentSearches, (record: SearchRecord) => {
      Row({ space: 12 }) {
        Text('↺').fontSize(22).fontColor('#98A29B')
        Text(record.query).fontSize(16).fontColor('#25352B').layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ top: 18, bottom: 18 })
          .onClick(() => { this.query = record.query; this.search(); }).accessibilityText('重新搜索' + record.query)
        Button('删除').fontSize(12).height(32).fontColor('#87938B').backgroundColor(Color.Transparent)
          .onClick(() => { this.remove(record.query); }).accessibilityText('删除搜索记录' + record.query)
      }.width('100%').border({ width: { bottom: 0.5 }, color: '#EDF0EE' })
    }, (record: SearchRecord) => record.query)
    if (this.recentSearches.length === 0 && !this.historyError) {
      Column({ space: 12 }) {
        Text('搜索目的地').fontSize(22).fontWeight(FontWeight.Medium).fontColor('#33483B')
        Text('输入地点名称或地址，跨城可搜“北京 望京花园”').fontSize(14).fontColor('#87938B').textAlign(TextAlign.Center)
      }.width('100%').padding({ top: 64, bottom: 40 })
    }
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Button('返回').height(42).padding({ left: 4, right: 4 }).fontSize(15)
          .fontColor('#33483B').backgroundColor(Color.Transparent)
          .onClick(() => {
            this.getUIContext().getFocusController().clearFocus();
            this.getUIContext().getRouter().back();
          })
        TextInput({ placeholder: '搜索地点、地址', text: this.query }).layoutWeight(1).height(44).fontSize(16)
          .maxLength(120).fontColor('#17251D').placeholderColor('#98A29B').backgroundColor('#F1F4F2')
          .borderRadius(12).enterKeyType(EnterKeyType.Search).cancelButton({ style: CancelButtonStyle.INPUT })
          .id('destinationSearchInput').defaultFocus(true)
          .onChange((value: string) => { if (value !== this.query) { this.query = value; this.edit(); } })
          .onSubmit(() => { this.search(); })
        Button('搜索').height(42).padding({ left: 8, right: 8 }).fontSize(15)
          .fontColor('#23864B').backgroundColor(Color.Transparent).enabled(!this.busy)
          .onClick(() => { this.search(); })
      }.width('100%').padding({ left: 12, right: 12, top: 12, bottom: 6 })
      Row() {
        Text(this.busy ? '正在搜索…' : this.resultCity ? this.resultCity + ' · 搜索结果' :
          this.locatingCity ? '正在识别当前城市…' : this.results.length > 0 ? '选择目的地' : '')
          .fontSize(12).fontColor('#87938B').layoutWeight(1)
        Button(this.showScope ? '收起范围' : '搜索范围').height(30).fontSize(12).fontColor('#77837B')
          .backgroundColor(Color.Transparent).onClick(() => { this.showScope = !this.showScope; })
      }.width('100%').padding({ left: 20, right: 12 })
      if (this.showScope) {
        Row({ space: 10 }) {
          Text('城市').fontSize(14).fontColor('#53665A')
          TextInput({ placeholder: '填写搜索城市', text: this.city }).layoutWeight(1).height(40).fontSize(14)
            .maxLength(80).fontColor('#17251D').backgroundColor('#F1F4F2')
            .onChange((value: string) => {
              if (value !== this.city) {
                this.cancelCity(); this.automaticScope = false; this.city = value; this.edit();
              }
            })
            .onSubmit(() => { if (this.query.trim()) { this.search(); } })
        }.width('100%').padding({ left: 20, right: 20, top: 4, bottom: 12 })
        Row() {
          Text(this.automaticScope ? '当前城市优先，未找到时搜索已到达城市（' + this.visitedCities.length + ' 个）' :
            '仅搜索手动指定城市').fontSize(12).fontColor('#87938B').layoutWeight(1)
          if (!this.automaticScope) {
            Button('恢复自动范围').fontSize(12).height(30).backgroundColor(Color.Transparent).fontColor('#23864B')
              .onClick(() => {
                this.cancelCity(); this.edit(); this.automaticScope = true;
                this.city = destinationSearchSession.request(this.session)?.city || '';
                if (!this.city) { this.resolveCity(); }
              })
          }
        }.width('100%').padding({ left: 20, right: 20, bottom: 12 })
      }
      if (this.message) {
        Text(this.message).fontSize(13).fontColor('#A36D2C').width('100%').padding({ left: 20, right: 20, top: 8, bottom: 8 })
      }
      if (this.historyError) {
        Text(this.historyError).fontSize(12).fontColor('#A36D2C').width('100%').padding({ left: 20, right: 20, bottom: 8 })
      }
      List({ space: 0 }) {
        if (this.results.length > 0) {
          ForEach(this.results, (place: Place) => {
            ListItem() {
              Row({ space: 14 }) {
                Text('去').fontSize(14).fontColor('#23864B').width(32).height(32).textAlign(TextAlign.Center)
                  .backgroundColor('#EDF6EF').borderRadius(16)
                Column({ space: 6 }) {
                  Text(place.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#17251D')
                    .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(place.address || '暂无详细地址').fontSize(13).fontColor('#87938B').width('100%').maxLines(2)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%').padding({ top: 18, bottom: 18 })
                .border({ width: { bottom: 0.5 }, color: '#EDF0EE' }).onClick(() => { this.select(place); })
                .accessibilityText('选择终点' + place.name + place.address)
            }
          }, (place: Place) => place.id + place.location)
        } else if (!this.busy && !this.searched) {
          ListItem() { Column() { this.history() }.width('100%') }
        }
      }.width('100%').layoutWeight(1).padding({ left: 20, right: 20 })
    }.width('100%').height('100%').backgroundColor('#FFFFFF')
  }
}
