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

function sameCoordinate(a: NaviLatLng, b: NaviLatLng): boolean {
  return Number.isFinite(a.latitude) && Number.isFinite(a.longitude) &&
    Number.isFinite(b.latitude) && Number.isFinite(b.longitude) &&
    Math.abs(a.latitude) <= 90 && Math.abs(a.longitude) <= 180 &&
    Math.abs(b.latitude) <= 90 && Math.abs(b.longitude) <= 180 && coordinate(a) === coordinate(b);
}

function signalEndsAtJunction(step: AMapNaviStep): boolean {
  const links = step.getLinks();
  if (!links || links.length === 0) { return false; }
  let signalIndex = -1;
  for (let i = 0; i < links.length; i++) {
    if (links[i].getTrafficLights()) {
      if (signalIndex !== -1) { return false; }
      signalIndex = i;
    }
  }
  if (signalIndex === -1) { return false; }
  const signalCoords = links[signalIndex].getCoords();
  if (!signalCoords || signalCoords.length < 2) { return false; }
  let endpoint = signalCoords[signalCoords.length - 1];
  let internalMeters = 0;
  // SDK road type 2 is a road inside an intersection. Accept only a short,
  // connected chain after the unique signal; ordinary roads remain ambiguous.
  for (let i = signalIndex + 1; i < links.length; i++) {
    const link = links[i];
    const length = link.getLength();
    const coords = link.getCoords();
    if (link.getRoadType() !== 2 || !Number.isFinite(length) || length <= 0 ||
      !coords || coords.length < 2 || !sameCoordinate(endpoint, coords[0])) { return false; }
    internalMeters += length;
    if (internalMeters > 60) { return false; }
    endpoint = coords[coords.length - 1];
  }
  const stepCoords = step.getCoords();
  return stepCoords !== null && stepCoords.length >= 2 &&
    sameCoordinate(endpoint, stepCoords[stepCoords.length - 1]);
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
    // Lane callbacks carry no point ID. A unique signal must end at the guidance
    // point or connect to it solely through <=60 m of intersection-internal links.
    const connectedSignal = signalEndsAtJunction(step);
    const eligible = step.getTrafficLightCount() === 1 && connectedSignal &&
      coords !== null && coords.length >= 2 && nextCoords !== null && nextCoords !== undefined &&
      nextCoords.length >= 2 && sameCoordinate(coords[coords.length - 1], nextCoords[0]);
    const reason = step.getTrafficLightCount() > 1 ? '本路段包含多个信号灯，无法确定车道对应路口' :
      step.getTrafficLightCount() === 0 ? '本路段未标注信号灯，不满足路口关联条件' :
      !next ? '当前为终点路段，缺少驶出道路用于匹配' :
      !connectedSignal ? '信号灯与引导点之间缺少可确认的短路口内部道路连接' :
      '路口进出道路几何不足或末端不匹配，无法关联车道';
    points.push(new PreviewPoint(i, end, incoming + ' → ' + outgoing, maneuver(step.getIconType()), key, eligible, reason));
  }
  return points;
}
