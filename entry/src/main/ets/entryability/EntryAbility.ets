import { UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { NavigationHistoryStore } from '../navigation/NavigationHistoryStore';
import { drivingGSession } from '../navigation/DrivingGSession';
import { compassSession } from '../navigation/CompassSession';
import { spiritLevelSession } from '../navigation/SpiritLevelSession';
import { nativeRoutePage } from '../navigation/NativeRoutePageSession';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    const history = new NavigationHistoryStore(this.context.filesDir);
    history.recoverInterrupted();
    AppStorage.setOrCreate('laneAheadNavigationHistoryError', history.error);
    AppStorage.setOrCreate('laneAheadForeground', true);
    windowStage.loadContent('pages/Home', (error) => {
      if (error.code) {
        hilog.error(0x0000, 'LaneAhead', '页面加载失败 %{public}s', JSON.stringify(error));
      }
    });
  }

  onForeground(): void {
    drivingGSession.setForeground(true);
    compassSession.setForeground(true);
    spiritLevelSession.setForeground(true);
    nativeRoutePage.setForeground(true);
    AppStorage.setOrCreate('laneAheadForeground', true);
  }

  onBackground(): void {
    drivingGSession.setForeground(false);
    compassSession.setForeground(false);
    spiritLevelSession.setForeground(false);
    nativeRoutePage.setForeground(false);
    // A replay must not keep advancing while the app is hidden.
    AppStorage.setOrCreate('laneAheadForeground', false);
  }

  onDestroy(): void {
    nativeRoutePage.close(undefined, false); drivingGSession.stop(); compassSession.stop(); spiritLevelSession.stop();
  }
}
