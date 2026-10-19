export enum Turn {
  STRAIGHT = '直行',
  LEFT = '左转',
  RIGHT = '右转',
  U_TURN = '掉头'
}

// Lanes are ordered from left to right in the driver's view.
export class Lane {
  directions: Turn[];
  recommendedDirections: Turn[];

  constructor(directions: Turn[], recommendedDirections: Turn[] = []) {
    if (directions.length === 0 ||
      recommendedDirections.some((turn: Turn) => !directions.includes(turn))) {
      throw new Error('推荐方向必须属于该车道允许的方向');
    }
    this.directions = directions;
    this.recommendedDirections = recommendedDirections;
  }
}

export class LaneGuidance {
  source: string;
  lanes: Lane[];

  constructor(source: string, lanes: Lane[]) {
    if (source.trim().length === 0 || lanes.length === 0) {
      throw new Error('车道信息必须包含来源及至少一条车道');
    }
    this.source = source;
    this.lanes = lanes;
  }
}

export class Junction {
  id: string;
  metersFromStart: number;
  name: string;
  turn: Turn;
  laneGuidance: LaneGuidance | undefined;

  constructor(id: string, metersFromStart: number, name: string, turn: Turn,
    laneGuidance: LaneGuidance | undefined) {
    if (id.trim().length === 0 || !Number.isFinite(metersFromStart) || metersFromStart < 0) {
      throw new Error('路口标识或沿路线距离无效');
    }
    this.id = id;
    this.metersFromStart = metersFromStart;
    this.name = name;
    this.turn = turn;
    this.laneGuidance = laneGuidance;
  }
}

export class RouteSnapshot {
  id: string;
  destination: string;
  totalMeters: number;
  junctions: Junction[];

  constructor(id: string, destination: string, totalMeters: number, junctions: Junction[]) {
    if (id.trim().length === 0 || !Number.isFinite(totalMeters) || totalMeters <= 0) {
      throw new Error('路线标识或长度无效');
    }
    const ids: string[] = [];
    let previous: number = -1;
    junctions.forEach((junction: Junction) => {
      if (ids.includes(junction.id) || junction.metersFromStart <= previous ||
        junction.metersFromStart > totalMeters) {
        throw new Error('路口必须唯一并按沿路线距离递增排列');
      }
      ids.push(junction.id);
      previous = junction.metersFromStart;
    });
    this.id = id;
    this.destination = destination;
    this.totalMeters = totalMeters;
    this.junctions = junctions;
  }
}

// Real progress must be map matched to this route; never use straight-line GPS distance.
export class RouteProgress {
  routeId: string;
  traveledMeters: number;

  constructor(routeId: string, traveledMeters: number) {
    if (!Number.isFinite(traveledMeters) || traveledMeters < 0) {
      throw new Error('路线进度无效');
    }
    this.routeId = routeId;
    this.traveledMeters = traveledMeters;
  }
}

export class UpcomingJunction {
  junction: Junction;
  remainingMeters: number;

  constructor(junction: Junction, remainingMeters: number) {
    this.junction = junction;
    this.remainingMeters = remainingMeters;
  }
}

export enum PreviewStatus {
  ACTIVE,
  ARRIVED,
  ROUTE_MISMATCH
}

export class PreviewState {
  status: PreviewStatus;
  upcoming: UpcomingJunction[];
  remainingRouteMeters: number;

  constructor(status: PreviewStatus, upcoming: UpcomingJunction[], remainingRouteMeters: number) {
    this.status = status;
    this.upcoming = upcoming;
    this.remainingRouteMeters = remainingRouteMeters;
  }
}

export class LookAheadEngine {
  preview(route: RouteSnapshot, progress: RouteProgress, count: number = 3): PreviewState {
    if (!Number.isInteger(count) || count < 1 || count > 3) {
      throw new Error('预览路口数量必须在 1 至 3 之间');
    }
    if (route.id !== progress.routeId) {
      return new PreviewState(PreviewStatus.ROUTE_MISMATCH, [], route.totalMeters);
    }
    const remaining: number = Math.max(0, route.totalMeters - progress.traveledMeters);
    const upcoming: UpcomingJunction[] = route.junctions
      .filter((junction: Junction) => junction.metersFromStart > progress.traveledMeters)
      .slice(0, count)
      .map((junction: Junction) => new UpcomingJunction(junction,
        junction.metersFromStart - progress.traveledMeters));
    return new PreviewState(remaining === 0 ? PreviewStatus.ARRIVED : PreviewStatus.ACTIVE,
      upcoming, remaining);
  }
}
