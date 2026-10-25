import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NavigationHistory, NavigationRecord } from './NavigationHistory';

export class NavigationHistoryStore {
  private path: string;
  error: string = '';
  constructor(filesDir: string) { this.path = filesDir + '/navigation-history-v1.json'; }

  load(): NavigationHistory {
    this.error = '';
    const history = new NavigationHistory();
    try {
      if (!fs.accessSync(this.path)) { return history; }
      if (fs.statSync(this.path).size > 1000000 || !history.restore(fs.readTextSync(this.path))) {
        this.error = '导航历史文件损坏或格式不支持，已保留原文件';
      }
    } catch (error) {
      if ((error as BusinessError).code !== 13900002) { this.error = '无法读取导航历史，请稍后重试'; }
    }
    return history;
  }

  save(history: NavigationHistory): boolean {
    try {
      const file = fs.openSync(this.path + '.tmp', fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.READ_WRITE);
      try { fs.writeSync(file.fd, history.serialize()); } finally { fs.closeSync(file); }
      fs.renameSync(this.path + '.tmp', this.path);
      this.error = '';
      return true;
    } catch {
      this.error = '导航历史保存失败，请检查本机存储后重试';
      return false;
    }
  }

  recoverInterrupted(): void {
    const history = this.load();
    if (!this.error && history.recoverInterrupted()) { this.save(history); }
  }
}

// One GPS start creates one record. Repeated/late finish calls cannot demote arrival.
export class NavigationHistorySession {
  private store: NavigationHistoryStore;
  private destination: string;
  private address: string;
  private record: NavigationRecord | undefined = undefined;
  private dirty: boolean = false;

  constructor(filesDir: string, destination: string, address: string) {
    this.store = new NavigationHistoryStore(filesDir);
    this.destination = destination.slice(0, 240); this.address = address.slice(0, 500);
  }

  start(plannedMeters: number, now: number = Date.now()): void {
    if (this.record) { return; }
    const id = now.toString() + '-' + Math.random().toString(36).slice(2, 12);
    this.record = new NavigationRecord(id, this.destination, this.address, now,
      Number.isFinite(plannedMeters) && plannedMeters >= 0 && plannedMeters <= 100000000 ? plannedMeters : 0);
    this.persist();
  }

  finish(status: string, now: number = Date.now()): void {
    const record = this.record;
    if (!record || ['arrived', 'ended', 'failed'].indexOf(status) < 0) { return; }
    if (record.status === 'navigating' || (record.status === 'ended' && status === 'arrived')) {
      record.status = status;
      if (!record.endedAt) { record.endedAt = Math.max(record.startedAt, now); }
      this.dirty = true;
    }
    if (this.dirty) { this.persist(); }
  }

  private persist(): void {
    const record = this.record;
    if (!record) { return; }
    this.dirty = true;
    const history = this.store.load();
    if (!this.store.error) { history.put(record); if (this.store.save(history)) { this.dirty = false; } }
    AppStorage.setOrCreate('laneAheadNavigationHistoryError', this.store.error);
  }
}
