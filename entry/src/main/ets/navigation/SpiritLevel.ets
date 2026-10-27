import { GVector } from './DrivingG';

export class SpiritLevelState {
  running: boolean = false;
  valid: boolean = false;
  roll: number = 0;
  pitch: number = 0;
  tilt: number = 0;
  bubbleX: number = 0;
  bubbleY: number = 0;
  level: boolean = false;
  status: string = '等待水平仪数据';
}

export class SpiritLevelEngine {
  private state: SpiritLevelState = new SpiritLevelState();
  private sampleAt: number = 0;
  private filtered: GVector = new GVector();

  start(): void { this.pause('等待水平仪数据'); this.state.running = true; }
  pause(status: string): void {
    this.state.running = false; this.invalidate(status); this.sampleAt = 0;
  }
  unavailable(): void { this.pause('重力传感器不可用'); }
  private invalidate(status: string): void {
    this.state.valid = false; this.state.level = false; this.state.status = status;
  }

  sample(value: GVector, now: number): void {
    if (!this.state.running || !Number.isFinite(now) || now <= this.sampleAt) { return; }
    const gap = this.sampleAt ? now - this.sampleAt : 50;
    this.sampleAt = now;
    const length = Math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
    if (!Number.isFinite(length) || length < 7 || length > 12) {
      this.invalidate('姿态数据暂不可用'); return;
    }
    if (value.z < 0) { this.invalidate('请将手机屏幕朝上'); return; }
    if (!this.state.valid || gap > 500) {
      this.filtered = new GVector(value.x / length, value.y / length, value.z / length);
    } else {
      const alpha = 1 - Math.exp(-Math.min(gap, 100) / 150);
      this.filtered.x += (value.x / length - this.filtered.x) * alpha;
      this.filtered.y += (value.y / length - this.filtered.y) * alpha;
      this.filtered.z += (value.z / length - this.filtered.z) * alpha;
    }
    const norm = Math.sqrt(this.filtered.x * this.filtered.x + this.filtered.y * this.filtered.y +
      this.filtered.z * this.filtered.z);
    const x = this.filtered.x / norm; const y = this.filtered.y / norm;
    const z = Math.max(0, Math.min(1, this.filtered.z / norm));
    this.state.roll = Math.atan2(x, Math.sqrt(y * y + z * z)) * 180 / Math.PI;
    this.state.pitch = Math.atan2(y, Math.sqrt(x * x + z * z)) * 180 / Math.PI;
    this.state.tilt = Math.acos(z) * 180 / Math.PI;
    // Bubble moves toward the raised edge; full travel at 15 degrees, bounded to the dial.
    const horizontal = Math.sqrt(x * x + y * y);
    const travel = Math.min(1, this.state.tilt / 15);
    this.state.bubbleX = horizontal > 0 ? x / horizontal * travel : 0;
    this.state.bubbleY = horizontal > 0 ? -y / horizontal * travel : 0;
    this.state.level = this.state.tilt <= 1;
    this.state.valid = true;
    this.state.status = this.state.level ? '接近水平（总倾角 ≤ 1°）' : '气泡移向较高的一侧';
  }

  tick(now: number): void {
    if (this.state.running && (!this.sampleAt || now - this.sampleAt > 500 || now < this.sampleAt)) {
      this.invalidate('水平仪数据已过期，等待更新');
    }
  }
  snapshot(): SpiritLevelState { return JSON.parse(JSON.stringify(this.state)) as SpiritLevelState; }
}
