import { LaneHistory, LaneObservation, PreviewLane } from './LanePreview';

export class LaneHistoryRow {
  id: string;
  road: string = '道路名称暂不可用';
  recordedAt: number;
  lanes: PreviewLane[];
  needsRefresh: boolean;

  constructor(record: LaneObservation, now: number) {
    this.id = record.key;
    this.recordedAt = record.recordedAt;
    this.lanes = record.lanes;
    this.needsRefresh = LaneHistory.needsRefresh(record.recordedAt, now);
    try {
      const parts = JSON.parse(record.key) as string[];
      // Only expose road labels. The stored geometry and raw matching key stay private.
      if (Array.isArray(parts) && parts.length === 4 &&
        parts.every((part: string) => typeof part === 'string') && parts[0].trim() && parts[1].trim()) {
        this.road = parts[0] + ' → ' + parts[1];
      }
    } catch { /* Older or unknown keys remain viewable without exposing their raw contents. */ }
  }
}

export function laneHistoryRows(history: LaneHistory, now: number): LaneHistoryRow[] {
  return history.observations(now).map((record: LaneObservation) => new LaneHistoryRow(record, now));
}
