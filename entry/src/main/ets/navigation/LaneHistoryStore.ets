import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LaneHistory } from './LanePreview';

// App-private storage only. No upload and no full trip trace. Replace atomically.
export class LaneHistoryStore {
  private path: string;
  lastSaveError: string = '';
  constructor(filesDir: string) { this.path = filesDir + '/lane-observations-v1.json'; }

  load(): LaneHistory {
    const history = new LaneHistory();
    try {
      if (fs.statSync(this.path).size <= 2000000) { history.restore(fs.readTextSync(this.path), Date.now()); }
    } catch { /* First run or corrupt/unavailable cache: navigation remains usable. */ }
    return history;
  }

  save(history: LaneHistory): boolean {
    try {
      const file = fs.openSync(this.path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      try { fs.writeSync(file.fd, history.serialize()); } finally { fs.closeSync(file); }
      fs.renameSync(this.path + '.tmp', this.path);
      this.lastSaveError = '';
      return true;
    } catch (error) {
      const code = (error as BusinessError).code;
      this.lastSaveError = '车道历史写入本机失败' + (typeof code === 'number' ? '（错误码 ' + code + '）' : '');
      return false;
    }
  }

  clear(): boolean { return this.save(new LaneHistory()); }
}
