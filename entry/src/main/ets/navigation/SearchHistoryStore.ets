import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SearchHistory } from './SearchHistory';

export class SearchHistoryStore {
  private path: string;
  error: string = '';
  constructor(filesDir: string) { this.path = filesDir + '/search-history-v1.json'; }

  load(): SearchHistory {
    this.error = '';
    const history = new SearchHistory();
    try {
      if (!fs.accessSync(this.path)) { return history; }
      if (fs.statSync(this.path).size > 64000 || !history.restore(fs.readTextSync(this.path))) {
        this.error = '搜索记录无法读取，已保留原文件；可点击清空重新记录';
      }
    } catch (error) {
      if ((error as BusinessError).code !== 13900002) { this.error = '搜索记录读取失败，请稍后重试'; }
    }
    return history;
  }

  save(history: SearchHistory): boolean {
    try {
      const file = fs.openSync(this.path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      try { fs.writeSync(file.fd, history.serialize()); } finally { fs.closeSync(file); }
      fs.renameSync(this.path + '.tmp', this.path);
      this.error = '';
      return true;
    } catch {
      this.error = '搜索记录保存失败，请检查本机存储后重试';
      return false;
    }
  }
}
