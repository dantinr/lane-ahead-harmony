import { fileIo as fs } from '@kit.CoreFileKit';
import { LaneCollectionState, restoreCollection } from './LaneCollection';

export class LaneCollectionStore {
  private path: string;
  constructor(filesDir: string) { this.path = filesDir + '/lane-collection-v1.json'; }

  load(): LaneCollectionState {
    try {
      if (fs.statSync(this.path).size <= 100000) { return restoreCollection(fs.readTextSync(this.path)); }
      const state = new LaneCollectionState();
      state.reason = '诊断文件过大，请开始新导航重新采集诊断。';
      return state;
    } catch { return new LaneCollectionState(); }
  }

  save(state: LaneCollectionState): boolean {
    try {
      const file = fs.openSync(this.path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      try { fs.writeSync(file.fd, JSON.stringify(state)); } finally { fs.closeSync(file); }
      fs.renameSync(this.path + '.tmp', this.path);
      return true;
    } catch { return false; }
  }
}
