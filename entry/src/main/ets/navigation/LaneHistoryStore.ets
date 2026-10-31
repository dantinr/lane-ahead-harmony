import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LaneHistory } from './LanePreview';

// App-private storage only. No upload and no full trip trace. Replace atomically.
export class LaneHistoryStore {
  private path: string;
  private loaded: boolean = false;
  loadError: string = '';
  lastSaveError: string = '';
  constructor(filesDir: string) { this.path = filesDir + '/lane-observations-v1.json'; }

  load(): LaneHistory {
    this.loaded = true;
    this.loadError = '';
    const history = new LaneHistory();
    try {
      if (!history.restore(fs.readTextSync(this.path), Date.now())) {
        this.loadError = '车道历史格式异常，已保留原文件并暂停覆盖；修复文件或显式清除后可重新记录';
      }
    } catch (error) {
      if ((error as BusinessError).code !== 13900002) {
        this.loadError = '车道历史读取失败，已保留原文件并暂停覆盖；请检查本机存储后重试';
      }
    }
    return history;
  }

  save(history: LaneHistory): boolean {
    if (!this.loaded) { this.load(); }
    if (this.loadError) { this.lastSaveError = this.loadError; return false; }
    return this.write(history);
  }

  private write(history: LaneHistory): boolean {
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

  clear(): boolean {
    if (!this.write(new LaneHistory())) { return false; }
    this.loaded = true;
    this.loadError = '';
    return true;
  }
}
