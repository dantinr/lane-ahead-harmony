// SDK steps are navigation guidance points, not an inventory of physical junctions.
// This model deliberately keeps unknown lanes unknown. History is only advisory.
import { LaneCollection } from './LaneCollection';

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
  unlearnableReason: string;
  constructor(step: number, endMeters: number, road: string, action: string, key: string, learnable: boolean,
    unlearnableReason: string = '路口关联条件不足，无法确认车道属于哪个路口') {
    this.step = step;
    this.endMeters = endMeters;
    this.road = road;
    this.action = action;
    this.key = key;
    this.learnable = learnable;
    this.unlearnableReason = unlearnableReason;
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
  lastChangeWasRemoval: boolean = false;

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
    this.lastChangeWasRemoval = false;
    this.revision += 1;
  }

  forget(key: string): void {
    if (!this.records.some((record: LaneObservation) => record.key === key)) { return; }
    this.records = this.records.filter((record: LaneObservation) => record.key !== key);
    this.lastChangeWasRemoval = true;
    this.revision += 1;
  }

  serialize(): string {
    const data = new HistoryFile();
    data.records = this.records;
    return JSON.stringify(data);
  }

  count(now: number): number {
    return this.records.filter((record: LaneObservation) => record.recordedAt <= now &&
      now - record.recordedAt < LaneHistory.MAX_AGE).length;
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
  collection: LaneCollection = new LaneCollection();
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
  private observedRecommendation: string = '';
  private observedRecommendedDirections: string = '';
  private conflictReason: string = '';
  private receivedInStep: boolean = false;
  private suspended: string = '等待实时导航';

  constructor(history: LaneHistory = new LaneHistory()) { this.history = history; }

  setRoute(id: string, points: PreviewPoint[]): void {
    this.suspend('路线更新，等待当前路线位置', Date.now(), this.pending !== undefined || this.live.length > 0);
    this.route = id;
    this.points = points;
    this.step = -1;
    this.observedSignature = '';
    this.observedRecommendation = '';
    this.observedRecommendedDirections = '';
    this.receivedInStep = false;
    this.conflictStep = -1;
  }

  suspend(reason: string, now: number = Date.now(), notSaved: boolean = true): void {
    this.suspended = reason;
    this.infoAt = 0;
    this.clearLanes();
    this.collection.report('suspended', '暂停采集', reason, now, notSaved);
  }

  finish(reason: string, now: number): void {
    if (this.pending) {
      this.collection.report('ended_before_crossing', '未保存', '导航结束前未确认通过路口，待保存记录已取消', now, true);
    }
    this.suspend(reason, now, false);
    this.collection.end(reason, now);
  }

  hideLanes(now: number = Date.now()): void {
    const hadPending = this.pending !== undefined;
    this.clearLanes();
    this.collection.report('lane_hidden', '等待车道', hadPending ?
      '高德已在通过确认前隐藏车道，待保存记录已取消' : '高德已隐藏车道，等待新的车道信息', now, hadPending);
  }

  private clearLanes(): void {
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
      this.suspend(!realtime ? '模拟导航不记录车道' : route !== this.route ?
        '当前位置不属于选定路线' : '路段或剩余距离无效，无法确认路口位置', now);
      return;
    }
    if (step !== this.step) {
      // Commit only after a continuous, forward crossing of the observed guidance point.
      if (this.pending && step === this.step + 1 && now - this.infoAt <= 5000 && this.infoAt > 0) {
        this.history.remember(this.pending.key, this.pending.lanes, now);
        this.collection.confirmed(now);
      } else if (this.pending) {
        this.collection.report('crossing_lost', '未保存', '路段跳变或定位间隔超过 5 秒，未能确认连续通过', now, true);
      }
      this.clearLanes();
      this.conflictStep = -1;
      this.observedSignature = '';
      this.observedRecommendation = '';
      this.observedRecommendedDirections = '';
      this.receivedInStep = false;
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
    this.receivedInStep = true;
    this.collection.receive(now);
    if (!LaneHistory.validLanes(lanes)) {
      this.clearLanes();
      this.collection.report('invalid_lanes', '未保存', '高德车道数据为空或不完整', now, true);
      return;
    }
    this.collection.decoded(now);
    if (!this.infoAt || now - this.infoAt > 2500 || this.suspended) {
      this.clearLanes();
      this.collection.report('lane_without_position', '未保存', '收到车道，但缺少 2.5 秒内的有效路线位置', now, true);
      return;
    }
    const point = this.points.find((item: PreviewPoint) => item.step === this.step);
    // Recommendations may change while the physical lane group stays the same.
    // Compare the count, left-to-right directions and special types separately.
    const signature = JSON.stringify(lanes.map((lane: PreviewLane) =>
      new PreviewLane(lane.directions.slice().sort(), [], lane.special)));
    const recommendation = JSON.stringify(lanes.map((lane: PreviewLane) => lane.recommended.slice().sort()));
    const recommendedDirections = ['↑', '←', '→', '↶', '↷'].filter((arrow: string) =>
      lanes.some((lane: PreviewLane) => lane.recommended.indexOf(arrow) >= 0)).join('');
    if (this.observedSignature && (this.observedSignature !== signature ||
      this.observedRecommendedDirections !== recommendedDirections)) {
      // Several lane groups in one SDK step cannot safely be assigned to its endpoint.
      this.conflictReason = this.observedSignature !== signature ? '本路段出现不同车道组，无法确认对应路口' :
        '车道推荐转向发生变化，无法确认对应路口';
      this.conflictStep = this.step;
      if (point) { this.history.forget(point.key); }
      this.pending = undefined;
    } else if (this.observedSignature && this.observedRecommendation !== recommendation &&
      this.conflictStep !== this.step) {
      this.collection.report('recommendation_update', '推荐已更新',
        '车道结构一致，仅更新推荐方向，继续等待通过确认', now);
    }
    this.observedSignature = signature;
    this.observedRecommendation = recommendation;
    this.observedRecommendedDirections = recommendedDirections;
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
      this.collection.report('pending', '待通过确认', '已收到车道，等待连续通过路口后保存', now);
    } else {
      this.pending = undefined;
      if (this.conflictStep === this.step) {
        this.collection.report('lane_conflict', '未保存', this.conflictReason, now, true);
      } else if (this.live.length === 0) {
        if (!this.receivedInStep) {
          this.collection.report('no_lanes', '等待车道', '高德尚未返回当前路段车道信息', now, true);
        }
      } else if (point && !point.learnable) {
        this.collection.report('unlearnable', '未保存', point.unlearnableReason, now, true);
      } else if (now - this.liveAt > 15000) {
        this.collection.report('lane_expired', '未保存', '车道信息超过 15 秒未刷新，已取消待保存记录', now, true);
      } else {
        this.collection.report('too_far', '等待靠近', '已收到车道，进入路口前 80 米后才准备保存', now);
      }
    }
  }

  preview(count: number, now: number): LanePreviewState {
    const state = new LanePreviewState();
    if (!this.infoAt || now - this.infoAt > 15000 || this.suspended) {
      state.status = this.suspended || '定位更新中，暂不提示车道';
      this.pending = undefined;
      if (!this.suspended) {
        this.collection.report('position_expired', '暂停采集', '定位超过 15 秒未更新，待保存记录已取消', now, true);
      }
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
