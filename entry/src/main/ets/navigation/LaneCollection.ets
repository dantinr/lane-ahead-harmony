// Bounded diagnostic summaries only: no keys, coordinates, roads or trip trace.
export class CollectionEvent {
  at: number;
  code: string;
  message: string;
  warning: boolean;
  constructor(at: number, code: string, message: string, warning: boolean) {
    this.at = at; this.code = code; this.message = message; this.warning = warning;
  }
}

export class CollectionReason {
  message: string;
  count: number;
  constructor(message: string, count: number) { this.message = message; this.count = count; }
}

export class LaneCollectionState {
  version: number = 1;
  startedAt: number = 0;
  endedAt: number = 0;
  updatedAt: number = 0;
  status: string = '尚无采集诊断';
  reason: string = '请使用新版开始一次真实导航；旧版本的行驶无法补录诊断。';
  received: number = 0;
  alternate: number = 0;
  decoded: number = 0;
  confirmed: number = 0;
  writes: number = 0;
  storedCount: number = 0;
  lastSavedAt: number = 0;
  lastNotSaved: string = '';
  lastNotSavedAt: number = 0;
  historyWriteError: string = '';
  reasons: CollectionReason[] = [];
  events: CollectionEvent[] = [];
}

export class LaneCollection {
  state: LaneCollectionState = new LaneCollectionState();
  revision: number = 0;
  private lastCode: string = '';
  private lastReason: string = '';

  begin(now: number, storedCount: number): void {
    this.state = new LaneCollectionState();
    this.state.startedAt = now;
    this.state.storedCount = storedCount;
    this.lastCode = ''; this.lastReason = '';
    this.report('start', '等待车道', '导航已开始，等待高德返回车道信息', now);
  }

  receive(now: number): void { this.state.received += 1; this.touch(now); }
  decoded(now: number): void { this.state.decoded += 1; this.touch(now); }
  confirmed(now: number): void {
    this.state.confirmed += 1;
    this.report('confirmed', '正在保存', '已连续通过路口，正在写入本机', now);
    this.touch(now);
  }

  persisted(now: number, count: number): void {
    this.state.writes += 1;
    this.state.storedCount = count;
    this.state.lastSavedAt = now;
    this.state.historyWriteError = '';
    this.report('saved', '保存成功', '车道历史更新已写入本机', now);
    this.touch(now);
  }

  writeFailed(message: string, now: number): void {
    this.state.historyWriteError = message;
    this.report('write_failed', '保存失败', message + '，将自动重试', now, true);
  }

  end(reason: string, now: number): void {
    this.state.endedAt = now;
    this.report('ended', '采集已结束', reason, now);
    this.touch(now);
  }

  report(code: string, status: string, reason: string, now: number, notSaved: boolean = false): void {
    if (code === this.lastCode && reason === this.lastReason) { return; }
    this.lastCode = code; this.lastReason = reason;
    this.state.status = status; this.state.reason = reason;
    this.state.events.push(new CollectionEvent(now, code, reason, notSaved));
    this.state.events = this.state.events.slice(-60);
    if (notSaved) {
      this.state.lastNotSaved = reason; this.state.lastNotSavedAt = now;
      const item = this.state.reasons.find((entry: CollectionReason) => entry.message === reason);
      if (item) { item.count += 1; } else { this.state.reasons.push(new CollectionReason(reason, 1)); }
      this.state.reasons = this.state.reasons.slice(-40);
    }
    this.touch(now);
  }

  private touch(now: number): void { this.state.updatedAt = now; this.revision += 1; }
  snapshot(): LaneCollectionState { return JSON.parse(JSON.stringify(this.state)) as LaneCollectionState; }
}

export function restoreCollection(text: string): LaneCollectionState {
  const empty = new LaneCollectionState();
  empty.reason = '诊断文件不可读取，请开始新导航重新采集诊断。';
  try {
    if (text.length > 100000) { return empty; }
    const data = JSON.parse(text) as LaneCollectionState;
    if (!data || data.version !== 1) { return empty; }
    const numbers: number[] = [data.startedAt, data.endedAt, data.updatedAt, data.received, data.alternate, data.decoded,
      data.confirmed, data.writes, data.storedCount, data.lastSavedAt, data.lastNotSavedAt];
    const strings: string[] = [data.status, data.reason, data.lastNotSaved, data.historyWriteError];
    if (!numbers.every((value: number) => Number.isSafeInteger(value) && value >= 0) ||
      !strings.every((value: string) => typeof value === 'string' && value.length <= 200) ||
      !Array.isArray(data.events) || data.events.length > 60 || !Array.isArray(data.reasons) || data.reasons.length > 40 ||
      !data.events.every((event: CollectionEvent) => event !== null && Number.isSafeInteger(event.at) && event.at >= 0 &&
        typeof event.code === 'string' && event.code.length <= 40 && typeof event.message === 'string' &&
        event.message.length <= 200 && typeof event.warning === 'boolean') ||
      !data.reasons.every((reason: CollectionReason) => reason !== null && typeof reason.message === 'string' &&
        reason.message.length <= 200 && Number.isSafeInteger(reason.count) && reason.count > 0)) { return empty; }
    return data;
  } catch { return empty; }
}
