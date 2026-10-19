import { Junction, Lane, LaneGuidance, RouteSnapshot, Turn } from './Guidance';

// Entirely synthetic. No real road or lane recommendation is implied.
export function createDemoRoute(missingLanes: boolean = false): RouteSnapshot {
  return new RouteSnapshot('synthetic-route-v1', '演示终点', 2300, [
    new Junction('demo-1', 350, '示例路口 A', Turn.STRAIGHT,
      new LaneGuidance('演示数据', [
        new Lane([Turn.LEFT]),
        new Lane([Turn.STRAIGHT], [Turn.STRAIGHT]),
        new Lane([Turn.STRAIGHT], [Turn.STRAIGHT]),
        new Lane([Turn.RIGHT])
      ])),
    new Junction('demo-2', 680, '示例路口 B', Turn.LEFT,
      missingLanes ? undefined : new LaneGuidance('演示数据', [
        new Lane([Turn.LEFT], [Turn.LEFT]),
        new Lane([Turn.LEFT, Turn.STRAIGHT], [Turn.LEFT]),
        new Lane([Turn.STRAIGHT]),
        new Lane([Turn.STRAIGHT, Turn.RIGHT])
      ])),
    new Junction('demo-3', 1160, '示例路口 C', Turn.RIGHT,
      new LaneGuidance('演示数据', [
        new Lane([Turn.LEFT]),
        new Lane([Turn.STRAIGHT]),
        new Lane([Turn.STRAIGHT, Turn.RIGHT], [Turn.RIGHT])
      ])),
    new Junction('demo-4', 1510, '示例路口 D', Turn.STRAIGHT,
      new LaneGuidance('演示数据', [
        new Lane([Turn.STRAIGHT], [Turn.STRAIGHT]),
        new Lane([Turn.STRAIGHT, Turn.RIGHT], [Turn.STRAIGHT])
      ])),
    new Junction('demo-5', 2020, '示例路口 E', Turn.LEFT,
      new LaneGuidance('演示数据', [
        new Lane([Turn.LEFT], [Turn.LEFT]),
        new Lane([Turn.STRAIGHT]),
        new Lane([Turn.RIGHT])
      ]))
  ]);
}
