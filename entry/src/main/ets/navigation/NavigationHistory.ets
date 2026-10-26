export class NavigationRecord {
  id: string;
  destination: string;
  address: string;
  startedAt: number;
  endedAt: number = 0;
  status: string = 'navigating';
  plannedMeters: number;
  city?: string;
  constructor(id: string, destination: string, address: string, startedAt: number, plannedMeters: number,
    city: string = '') {
    this.id = id; this.destination = destination; this.address = address;
    this.startedAt = startedAt; this.plannedMeters = plannedMeters;
    this.city = city;
  }
}

class HistoryFile {
  version: number = 1;
  records: NavigationRecord[] = [];
}

export class NavigationHistory {
  records: NavigationRecord[] = [];
  static readonly LIMIT: number = 200;

  static valid(record: NavigationRecord): boolean {
    return record !== null && typeof record === 'object' && typeof record.id === 'string' &&
      record.id.length > 0 && record.id.length <= 100 && typeof record.destination === 'string' &&
      record.destination.trim().length > 0 && record.destination.length <= 240 && typeof record.address === 'string' &&
      record.address.length <= 500 && Number.isSafeInteger(record.startedAt) && record.startedAt > 0 &&
      (record.city === undefined || (typeof record.city === 'string' && record.city.length <= 80)) &&
      Number.isSafeInteger(record.endedAt) && record.endedAt >= 0 && Number.isFinite(record.plannedMeters) &&
      record.plannedMeters >= 0 && record.plannedMeters <= 100000000 &&
      ['navigating', 'arrived', 'ended', 'interrupted', 'failed'].indexOf(record.status) >= 0 &&
      ((record.status === 'navigating' || record.status === 'interrupted') ? record.endedAt === 0 :
        record.endedAt >= record.startedAt);
  }

  restore(text: string): boolean {
    try {
      if (text.length > 1000000) { return false; }
      const data = JSON.parse(text) as HistoryFile;
      if (!data || data.version !== 1 || !Array.isArray(data.records) || data.records.length > NavigationHistory.LIMIT ||
        !data.records.every((record: NavigationRecord) => NavigationHistory.valid(record))) { return false; }
      const ids: string[] = data.records.map((record: NavigationRecord) => record.id);
      if (ids.some((id: string, index: number) => ids.indexOf(id) !== index)) { return false; }
      this.records = data.records.sort((a: NavigationRecord, b: NavigationRecord) => b.startedAt - a.startedAt);
      return true;
    } catch { return false; }
  }

  put(record: NavigationRecord): void {
    if (!NavigationHistory.valid(record)) { return; }
    this.records = this.records.filter((item: NavigationRecord) => item.id !== record.id);
    this.records.push(JSON.parse(JSON.stringify(record)) as NavigationRecord);
    this.records.sort((a: NavigationRecord, b: NavigationRecord) => b.startedAt - a.startedAt);
    this.records = this.records.slice(0, NavigationHistory.LIMIT);
  }

  remove(id: string): void { this.records = this.records.filter((record: NavigationRecord) => record.id !== id); }

  recoverInterrupted(): boolean {
    let changed = false;
    this.records.forEach((record: NavigationRecord) => {
      if (record.status === 'navigating') { record.status = 'interrupted'; changed = true; }
    });
    return changed;
  }

  serialize(): string {
    const file = new HistoryFile(); file.records = this.records;
    return JSON.stringify(file);
  }
}

export function navigationStatus(status: string): string {
  if (status === 'arrived') { return '已到达'; }
  if (status === 'ended') { return '已结束'; }
  if (status === 'interrupted') { return '未正常结束'; }
  if (status === 'failed') { return '导航异常结束'; }
  return '导航中';
}

export function navigationTime(at: number): string {
  if (!at) { return '未记录'; }
  const date = new Date(at);
  return date.getFullYear() + '-' + (date.getMonth() + 1).toString().padStart(2, '0') + '-' +
    date.getDate().toString().padStart(2, '0') + ' ' + date.getHours().toString().padStart(2, '0') + ':' +
    date.getMinutes().toString().padStart(2, '0');
}

export function navigationDuration(record: NavigationRecord): string {
  if (!record.endedAt) { return '未记录完整时长'; }
  const seconds = Math.max(0, Math.floor((record.endedAt - record.startedAt) / 1000));
  if (seconds < 60) { return seconds + ' 秒'; }
  const minutes = Math.floor(seconds / 60);
  return minutes < 60 ? minutes + ' 分钟' : Math.floor(minutes / 60) + ' 小时 ' + minutes % 60 + ' 分钟';
}
