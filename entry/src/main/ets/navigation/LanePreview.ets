// SDK steps are navigation guidance points, not an inventory of physical junctions.
// This model deliberately keeps unknown lanes unknown. History is only advisory.
export class PreviewLane {
  directions: string[];
  recommended: string[];
  special: string;
  constructor(directions: string[], recommended: string[], special: string = '') {
    this.directions = directions;
    this.recommended = recommended;
    this.special = special;
  }
}

export class PreviewPoint {
  step: number;
  endMeters: number;
  road: string;
  action: string;
  key: string;
  learnable: boolean;
  constructor(step: number, endMeters: number, road: string, action: string, key: string, learnable: boolean) {
    this.step = step;
    this.endMeters = endMeters;
    this.road = road;
    this.action = action;
    this.key = key;
    this.learnable = learnable;
  }
}

export class LaneObservation {
  key: string;
  recordedAt: number;
  lanes: PreviewLane[];
  constructor(key: string, recordedAt: number, lanes: PreviewLane[]) {
    this.key = key;
    this.recordedAt = recordedAt;
    this.lanes = lanes;
  }
}

class HistoryFile {
  version: number = 1;
  records: LaneObservation[] = [];
}

export class LaneHistory {
  static readonly MAX_AGE: number = 7 * 24 * 60 * 60 * 1000;
  private records: LaneObservation[] = [];
  revision: number = 0;

  static validLanes(lanes: PreviewLane[]): boolean {
    const allowed: string[] = ['↑', '←', '→', '↶', '↷'];
    return Array.isArray(lanes) && lanes.length > 0 && lanes.length <= 16 &&
      lanes.every((lane: PreviewLane) => lane !== null && typeof lane === 'object' &&
        Array.isArray(lane.directions) && Array.isArray(lane.recommended) &&
        typeof lane.special === 'string' && lane.special.length <= 12 &&
        (lane.directions.length > 0 || lane.special.length > 0) && lane.directions.length <= 5 &&
        lane.directions.every((arrow: string) => allowed.indexOf(arrow) >= 0) &&
        lane.recommended.every((arrow: string) => lane.directions.indexOf(arrow) >= 0));
  }

  restore(text: string, now: number): void {
    this.records = [];
    try {
      if (text.length > 2000000) { return; }
      const data = JSON.parse(text) as HistoryFile;
      if (!data || data.version !== 1 || !Array.isArray(data.records)) { return; }
      this.records = data.records.filter((record: LaneObservation) => record !== null &&
        typeof record.key === 'string' && record.key.length > 0 && record.key.length <= 2048 &&
        Number.isFinite(record.recordedAt) && record.recordedAt <= now &&
        now - record.recordedAt < LaneHistory.MAX_AGE && LaneHistory.validLanes(record.lanes)).slice(-500);
    } catch { this.records = []; }
  }

  find(key: string, now: number): LaneObservation | undefined {
    return this.records.find((record: LaneObservation) => record.key === key &&
      record.recordedAt <= now && now - record.recordedAt < LaneHistory.MAX_AGE);
  }

  remember(key: string, lanes: PreviewLane[], now: number): void {
    if (!key || key.length > 2048 || !LaneHistory.validLanes(lanes)) { return; }
    this.records = this.records.filter((record: LaneObservation) => record.key !== key &&
      record.recordedAt <= now && now - record.recordedAt < LaneHistory.MAX_AGE);
    this.records.push(new LaneObservation(key, now, lanes));
    this.records = this.records.slice(-500);
    this.revision += 1;
  }

  forget(key: string): void {
    this.records = this.records.filter((record: LaneObservation) => record.key !== key);
    this.revision += 1;
  }

  serialize(): string {
    const data = new HistoryFile();
    data.records = this.records;
    return JSON.stringify(data);
  }
}

export class PreviewRow {
  id: string;
  distance: number;
  road: string;
  action: string;
  lanes: PreviewLane[];
  source: string;
  recordedAt: number;
  constructor(id: string, distance: number, road: string, action: string,
    lanes: PreviewLane[], source: string, recordedAt: number = 0) {
    this.id = id;
    this.distance = distance;
    this.road = road;
    this.action = action;
    this.lanes = lanes;
    this.source = source;
    this.recordedAt = recordedAt;
  }
}

export class LanePreviewState {
  rows: PreviewRow[] = [];
  liveLanes: PreviewLane[] = [];
  status: string = '等待实时导航';
}

export class LanePreviewEngine {
  history: LaneHistory;
  private points: PreviewPoint[] = [];
  private route: string = '';
  private step: number = -1;
  private traveled: number = 0;
  private infoAt: number = 0;
  private liveAt: number = 0;
  private live: PreviewLane[] = [];
  private liveStep: number = -1;
  private pending: LaneObservation | undefined = undefined;
  private conflictStep: number = -1;
  private observedSignature: string = '';
  private suspended: string = '等待实时导航';

  constructor(history: LaneHistory = new LaneHistory()) { this.history = history; }

  setRoute(id: string, points: PreviewPoint[]): void {
    this.suspend('等待当前路线位置');
    this.route = id;
    this.points = points;
    this.step = -1;
    this.observedSignature = '';
    this.conflictStep = -1;
  }

  suspend(reason: string): void {
    this.suspended = reason;
    this.infoAt = 0;
    this.hideLanes();
  }

  hideLanes(): void {
    this.live = [];
    this.liveAt = 0;
    this.liveStep = -1;
    this.pending = undefined;
  }

  progress(route: string, step: number, remaining: number, now: number, realtime: boolean): void {
    const point = this.points.find((item: PreviewPoint) => item.step === step);
    const previousEnd = step === 0 ? 0 : this.points.find((item: PreviewPoint) => item.step === step - 1)?.endMeters;
    if (!realtime || route !== this.route || !point || previousEnd === undefined ||
      !Number.isFinite(remaining) || remaining < 0 || remaining > point.endMeters - previousEnd + 30) {
      this.suspend(realtime ? '等待路线重新匹配' : '模拟导航不记录车道');
      return;
    }
    if (step !== this.step) {
      // Commit only after a continuous, forward crossing of the observed guidance point.
      if (this.pending && step === this.step + 1 && now - this.infoAt <= 5000 && this.infoAt > 0) {
        this.history.remember(this.pending.key, this.pending.lanes, now);
      }
      this.hideLanes();
      this.conflictStep = -1;
      this.observedSignature = '';
    } else if (this.infoAt > 0 && now - this.infoAt <= 5000 && this.liveStep === step && now - this.liveAt <= 15000) {
      // A visible SDK lane group stays valid while matched progress keeps arriving,
      // including a red-light stop. hideLaneInfo / suspension still clears it.
      this.liveAt = now;
    }
    this.step = step;
    this.traveled = point.endMeters - remaining;
    this.infoAt = now;
    this.suspended = '';
    this.prepareObservation(now);
  }

  lanes(lanes: PreviewLane[], now: number): void {
    if (!LaneHistory.validLanes(lanes) || !this.infoAt || now - this.infoAt > 2500 || this.suspended) {
      this.hideLanes();
      return;
    }
    const point = this.points.find((item: PreviewPoint) => item.step === this.step);
    const signature = JSON.stringify(lanes);
    if (this.observedSignature && this.observedSignature !== signature) {
      // Several lane groups in one SDK step cannot safely be assigned to its endpoint.
      this.conflictStep = this.step;
      if (point) { this.history.forget(point.key); }
      this.pending = undefined;
    }
    this.observedSignature = signature;
    this.live = lanes;
    this.liveAt = now;
    this.liveStep = this.step;
    this.prepareObservation(now);
  }

  private bindable(point: PreviewPoint): boolean {
    return point.learnable && point.step === this.liveStep && this.conflictStep !== this.step &&
      point.endMeters - this.traveled <= 200;
  }

  private prepareObservation(now: number): void {
    const point = this.points.find((item: PreviewPoint) => item.step === this.step);
    if (point && this.bindable(point) && point.endMeters - this.traveled <= 80 &&
      this.live.length > 0 && now - this.liveAt <= 15000) {
      this.pending = new LaneObservation(point.key, now, this.live);
    } else { this.pending = undefined; }
  }

  preview(count: number, now: number): LanePreviewState {
    const state = new LanePreviewState();
    if (!this.infoAt || now - this.infoAt > 15000 || this.suspended) {
      state.status = this.suspended || '定位更新中，暂不提示车道';
      this.pending = undefined;
      return state;
    }
    state.status = '仅覆盖导航引导点，部分直行路口可能缺失';
    const liveFresh = this.live.length > 0 && now - this.liveAt <= 15000;
    state.rows = this.points.filter((point: PreviewPoint) => point.step >= this.step && point.action !== '到达终点')
      .slice(0, count === 2 ? 2 : 3).map((point: PreviewPoint) => {
        const distance = Math.max(0, point.endMeters - this.traveled);
        if (liveFresh && this.bindable(point)) {
          return new PreviewRow(point.key, distance, point.road, point.action, this.live, '实时');
        }
        const record = point.learnable ? this.history.find(point.key, now) : undefined;
        if (record && !(point.step === this.step && this.conflictStep === this.step)) {
          return new PreviewRow(point.key, distance, point.road, point.action, record.lanes, '历史参考', record.recordedAt);
        }
        return new PreviewRow(point.key, distance, point.road, point.action, [], '暂无车道数据');
      });
    if (liveFresh && !state.rows.some((row: PreviewRow) => row.source === '实时')) { state.liveLanes = this.live; }
    if (state.rows.length === 0) { state.status = '即将到达终点'; }
    return state;
  }
}
