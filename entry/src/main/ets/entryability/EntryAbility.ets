import { UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    AppStorage.setOrCreate('laneAheadForeground', true);
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(0x0000, 'LaneAhead', '页面加载失败 %{public}s', JSON.stringify(error));
      }
    });
  }

  onForeground(): void {
    AppStorage.setOrCreate('laneAheadForeground', true);
  }

  onBackground(): void {
    // A replay must not keep advancing while the app is hidden.
    AppStorage.setOrCreate('laneAheadForeground', false);
  }
}
