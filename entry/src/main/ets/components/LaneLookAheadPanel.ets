import { LanePreviewState, PreviewRow } from '../navigation/LanePreview';
import { LanePreviewRows, PreviewLaneStrip } from './LanePreviewRows';
import { ComponentContent, UIContext } from '@kit.ArkUI';
import { NavigationPanel } from '../navigation/NativeNavigation';
import { LaneCollectionState } from '../navigation/LaneCollection';
import { DrivingGReadout } from './DrivingGReadout';

// Mount above navigation pages, independent of the SDK's clipped custom slots.
// Only the panel receives touch events; the map and navigation controls remain usable.
export class LanePanelOverlay implements NavigationPanel {
  private context: UIContext;
  private content: ComponentContent<Object> | undefined = undefined;

  constructor(context: UIContext) { this.context = context; }

  show(): void {
    if (this.content) { return; }
    this.context.runScopedTask(() => {
      const content = new ComponentContent<Object>(this.context, wrapBuilder(laneLookAheadBuilder));
      this.content = content;
      try { this.context.getOverlayManager().addComponentContent(content); } catch {
        this.content = undefined;
        content.dispose();
        throw new Error('无法显示前方车道');
      }
    });
  }

  hide(): void {
    const content = this.content;
    this.content = undefined;
    if (!content) { return; }
    try { this.context.getOverlayManager().removeComponentContent(content); } catch {
      // The window or its overlay may already have been released.
    } finally { content.dispose(); }
  }
}

@Builder
export function laneLookAheadBuilder() {
  // Keep the full-window touch surface on the builder's native Stack, rather
  // than on a full-window custom-component wrapper that blocks the SDK below.
  Stack({ alignContent: Alignment.TopEnd }) {
    LaneLookAheadPanel().margin({ top: 146, right: 44 })
  }.width('100%').height('100%').focusable(false).hitTestBehavior(HitTestMode.Transparent)
}

@Component
struct LaneLookAheadPanel {
  @StorageLink('laneAheadLanePreview') preview: LanePreviewState = new LanePreviewState();
  @StorageLink('laneAheadPreviewCount') count: number = 3;
  @StorageLink('laneAheadPanelExpanded') expanded: boolean = true;
  @StorageProp('laneAheadWindowWidth') windowWidth: number = 360;
  @StorageLink('laneAheadCollection') collection: LaneCollectionState = new LaneCollectionState();
  @StorageLink('laneAheadCollectionPersistenceError') diagnosticError: string = '';

  private panelWidth(): number {
    // Fit between the speed indicator and the traffic bar below the turn card.
    return Math.max(200, Math.min(420, this.windowWidth - 132));
  }

  build() {
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
          LanePreviewRows({ rows: this.preview.rows })
          if (this.preview.liveLanes.length > 0) {
            Text('当前实时车道 · 未关联引导点').fontSize(10).fontColor('#B7C8BA').width('100%')
            PreviewLaneStrip({ lanes: this.preview.liveLanes })
          }
          Text(this.preview.status).fontSize(10).fontColor('#B7C8BA').width('100%')
          Text(this.collection.status + ' · 本机历史 ' + this.collection.storedCount + ' 条')
            .fontSize(11).fontColor(this.collection.historyWriteError ? '#FFD58A' : '#B5F489').width('100%')
          if (this.collection.historyWriteError || this.collection.reason !== this.preview.status) {
            Text(this.collection.historyWriteError || this.collection.reason).fontSize(10).fontColor('#D1D9CF')
              .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.diagnosticError) {
            Text(this.diagnosticError).fontSize(10).fontColor('#FFD58A').width('100%')
          }
          if (this.preview.rows.some((row: PreviewRow) => row.source === '历史参考')) {
            Text('历史长期保留，满 3 个月标记待更新；以现场标线为准').fontSize(10).fontColor('#FFD58A').width('100%')
          }
        }
        Divider().color('#3C5145').margin({ top: 4, bottom: 4 })
        DrivingGReadout({ compact: true })
    }.width(this.panelWidth()).padding(10).borderRadius(12).backgroundColor('#F2142B22')
  }
}
