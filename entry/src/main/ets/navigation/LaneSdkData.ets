import { AMapNaviPath, AMapNaviStep, IAMapLaneInfo, LaneAction, NaviLatLng } from '@amap/amap_lbs_navi';
import { PreviewLane, PreviewPoint } from './LanePreview';

function arrows(code: number): string[] {
  if (code === LaneAction.LANE_ACTION_AHEAD) { return ['↑']; }
  if (code === LaneAction.LANE_ACTION_LEFT) { return ['←']; }
  if (code === LaneAction.LANE_ACTION_RIGHT) { return ['→']; }
  if (code === LaneAction.LANE_ACTION_LU_TURN) { return ['↶']; }
  if (code === LaneAction.LANE_ACTION_RU_TURN) { return ['↷']; }
  if (code === LaneAction.LANE_ACTION_AHEAD_LEFT) { return ['↑', '←']; }
  if (code === LaneAction.LANE_ACTION_AHEAD_RIGHT) { return ['↑', '→']; }
  if (code === LaneAction.LANE_ACTION_LEFT_RIGHT) { return ['←', '→']; }
  if (code === LaneAction.LANE_ACTION_AHEAD_LEFT_RIGHT) { return ['↑', '←', '→']; }
  if (code === LaneAction.LANE_ACTION_AHEAD_LU_TURN) { return ['↑', '↶']; }
  if (code === LaneAction.LANE_ACTION_AHEAD_RU_TURN) { return ['↑', '↷']; }
  if (code === LaneAction.LANE_ACTION_LEFT_LU_TURN) { return ['←', '↶']; }
  if (code === LaneAction.LANE_ACTION_RIGHT_RU_TURN) { return ['→', '↷']; }
  if (code === LaneAction.LANE_ACTION_AHEAD_LEFT_LU_TURN) { return ['↑', '←', '↶']; }
  // Extended and variable types are intentionally not guessed.
  return [];
}

function special(code: number): string {
  if (code === LaneAction.LANE_ACTION_BUS) { return '公交'; }
  if (code === LaneAction.LANE_ACTION_VARIABLE) { return '可变'; }
  if (code === LaneAction.LANE_ACTION_TIDAL) { return '潮汐'; }
  if (code === LaneAction.LANE_ACTION_DEDICATED) { return '专用'; }
  if (code === LaneAction.LANE_ACTION_EMPTY) { return '空车道'; }
  return '未识别';
}

export function decodeLanes(info: IAMapLaneInfo | null): PreviewLane[] {
  if (!info || !Number.isInteger(info.laneCount) || info.laneCount < 1 || info.laneCount > 16 ||
    info.backgroundLane.length < info.laneCount || info.frontLane.length < info.laneCount) { return []; }
  const lanes: PreviewLane[] = [];
  for (let i = 0; i < info.laneCount; i++) {
    const directions = arrows(info.backgroundLane[i]);
    const recommended = arrows(info.frontLane[i]).filter((arrow: string) => directions.indexOf(arrow) >= 0);
    lanes.push(new PreviewLane(directions, recommended, directions.length > 0 ? '' : special(info.backgroundLane[i])));
  }
  return lanes;
}

function roadName(step: AMapNaviStep | undefined): string {
  const links = step?.getLinks();
  if (links) {
    for (let i = links.length - 1; i >= 0; i--) {
      const name = links[i].getRoadName();
      if (name) { return name; }
    }
  }
  return '未命名道路';
}

function coordinate(point: NaviLatLng): string {
  return point.latitude.toFixed(6) + ',' + point.longitude.toFixed(6);
}

// Public SDK icon numbers; these labels describe maneuvers, not lane counts.
export function maneuver(icon: number): string {
  if (icon === 2 || icon === 4 || icon === 6) { return '左转'; }
  if (icon === 3 || icon === 5 || icon === 7) { return '右转'; }
  if (icon === 8 || icon === 19) { return '掉头'; }
  if (icon === 11 || icon === 17) { return '进入环岛'; }
  if (icon === 12 || icon === 18) { return '驶出环岛'; }
  if (icon === 15) { return '到达终点'; }
  if (icon === 10) { return '途经点'; }
  if (icon === 13) { return '服务区'; }
  if (icon === 14) { return '收费站'; }
  if (icon === 16) { return '隧道'; }
  return '继续行驶';
}

export function routePoints(path: AMapNaviPath): PreviewPoint[] {
  const steps = path.getSteps();
  const points: PreviewPoint[] = [];
  if (!steps) { return points; }
  let end = 0;
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    const length = step.getLength();
    if (!Number.isFinite(length) || length < 0) { return []; }
    end += length;
    const next = i + 1 < steps.length ? steps[i + 1] : undefined;
    const coords = step.getCoords();
    const nextCoords = next?.getCoords();
    const shape: string[] = [];
    if (coords) {
      for (let j = Math.max(0, coords.length - 4); j < coords.length; j++) { shape.push(coordinate(coords[j])); }
    }
    shape.push('>');
    if (nextCoords) {
      for (let j = 0; j < Math.min(4, nextCoords.length); j++) { shape.push(coordinate(nextCoords[j])); }
    }
    const incoming = roadName(step);
    const outgoing = roadName(next);
    const key = JSON.stringify([incoming, outgoing, step.getIconType().toString(), shape.join(';')]);
    const links = step.getLinks();
    const terminal = links && links.length > 0 ? links[links.length - 1] : undefined;
    const terminalCoords = terminal?.getCoords();
    // Lane callbacks carry no point ID. Learn only single-signal steps whose signal
    // link ends at the step endpoint, and only after a continuous observed crossing.
    const eligible = step.getTrafficLightCount() === 1 && terminal?.getTrafficLights() === true &&
      coords !== null && coords.length >= 2 && nextCoords !== null && nextCoords !== undefined &&
      nextCoords.length >= 2 && terminalCoords !== null && terminalCoords !== undefined &&
      terminalCoords.length >= 2 && coordinate(terminalCoords[terminalCoords.length - 1]) ===
      coordinate(coords[coords.length - 1]);
    const reason = step.getTrafficLightCount() > 1 ? '本路段包含多个信号灯，无法确定车道对应路口' :
      step.getTrafficLightCount() === 0 ? '本路段未标注信号灯，不满足路口关联条件' :
      !next ? '当前为终点路段，缺少驶出道路用于匹配' :
      terminal?.getTrafficLights() !== true ? '信号灯不在路段末端，无法关联路口' :
      '路口进出道路几何不足或末端不匹配，无法关联车道';
    points.push(new PreviewPoint(i, end, incoming + ' → ' + outgoing, maneuver(step.getIconType()), key, eligible, reason));
  }
  return points;
}
