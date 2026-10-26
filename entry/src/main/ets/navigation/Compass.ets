import { GVector } from './DrivingG';

export class CompassState {
  available: boolean = true;
  running: boolean = false;
  valid: boolean = false;
  heading: number = 0;
  rotation: number = 0;
  direction: string = '';
  reference: string = '';
  status: string = '等待方向数据';
}

function dot(a: GVector, b: GVector): number { return a.x * b.x + a.y * b.y + a.z * b.z; }
function norm(v: GVector): number { return Math.sqrt(dot(v, v)); }
function finite(v: GVector): boolean { return Number.isFinite(v.x) && Number.isFinite(v.y) && Number.isFinite(v.z); }
function scale(v: GVector, n: number): GVector { return new GVector(v.x * n, v.y * n, v.z * n); }
function horizontal(v: GVector, up: GVector): GVector {
  const vertical = dot(v, up);
  return new GVector(v.x - up.x * vertical, v.y - up.y * vertical, v.z - up.z * vertical);
}
function degrees(value: number): number { return ((value % 360) + 360) % 360; }

export class CompassEngine {
  state: CompassState = new CompassState();
  private gravity: GVector = new GVector();
  private gravityAt: number = 0;
  private sampleAt: number = 0;
  private filtered: number = 0;
  private mounted: boolean = false;

  start(): void {
    this.pause('等待方向数据'); this.state.available = true; this.state.running = true;
  }

  pause(status: string): void {
    this.state.running = false; this.invalidate(status); this.gravityAt = 0; this.sampleAt = 0;
  }

  unavailable(): void { this.pause('指南针不可用'); this.state.available = false; }

  private invalidate(status: string): void { this.state.valid = false; this.state.status = status; }

  updateGravity(value: GVector, now: number): void {
    if (!this.state.running || !Number.isFinite(now) || now <= this.gravityAt) { return; }
    if (!finite(value) || norm(value) < 7 || norm(value) > 12) {
      this.gravityAt = 0; this.invalidate('姿态数据暂不可用'); return;
    }
    this.gravity = value; this.gravityAt = now;
  }

  sample(magnetic: GVector, accuracy: number, now: number): void {
    if (!this.state.running || !Number.isFinite(now) || now <= this.sampleAt) { return; }
    const gap = this.sampleAt ? now - this.sampleAt : 50; this.sampleAt = now;
    if (!this.gravityAt || now < this.gravityAt || now - this.gravityAt > 200) {
      this.invalidate('等待姿态数据'); return;
    }
    if (!finite(magnetic) || !Number.isFinite(accuracy) || accuracy <= 0 || accuracy > 3 ||
      norm(magnetic) < 10 || norm(magnetic) > 100) {
      this.invalidate('磁场不可靠，请远离磁铁并画 8 字校准'); return;
    }
    const up = scale(this.gravity, 1 / norm(this.gravity));
    const north = horizontal(magnetic, up);
    if (norm(north) < 5) { this.invalidate('水平磁场过弱，请调整位置'); return; }
    const unitNorth = scale(north, 1 / norm(north));
    const east = new GVector(unitNorth.y * up.z - unitNorth.z * up.y,
      unitNorth.z * up.x - unitNorth.x * up.z, unitNorth.x * up.y - unitNorth.y * up.x);
    // Upright: same forward (-screen Z) as the driving G mount. Flat: physical
    // phone top (+Y). Hysteresis avoids changing references near the boundary.
    const screenForward = horizontal(new GVector(0, 0, -1), up);
    let mounted = this.mounted;
    if (norm(screenForward) > 0.75) { mounted = true; }
    else if (norm(screenForward) < 0.55) { mounted = false; }
    const forward = mounted ? screenForward : horizontal(new GVector(0, 1, 0), up);
    if (norm(forward) < 0.4) { this.invalidate('请调整手机姿态'); return; }
    const heading = degrees(Math.atan2(dot(forward, east), dot(forward, unitNorth)) * 180 / Math.PI);
    if (!this.state.valid || gap > 500 || mounted !== this.mounted) { this.filtered = heading; }
    else {
      const delta = degrees(heading - this.filtered + 180) - 180;
      this.filtered += delta * (1 - Math.exp(-Math.min(gap, 100) / 180));
    }
    this.mounted = mounted;
    this.state.heading = degrees(this.filtered);
    this.state.rotation = -this.filtered;
    this.state.direction = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'][
      Math.floor((this.state.heading + 22.5) / 45) % 8];
    this.state.reference = mounted ? '屏幕朝向车尾时，按车头方向' : '平放时，按手机顶端方向';
    this.state.status = accuracy === 1 ? '磁北 · 精度较低，可画 8 字校准' : '磁北 · 远离磁吸支架与金属干扰';
    this.state.valid = true;
  }

  tick(now: number): void {
    if (this.state.running && (!this.sampleAt || now - this.sampleAt > 500 ||
      !this.gravityAt || now - this.gravityAt > 500)) { this.invalidate('方向数据已过期，等待更新'); }
  }

  snapshot(): CompassState { return JSON.parse(JSON.stringify(this.state)) as CompassState; }
}
