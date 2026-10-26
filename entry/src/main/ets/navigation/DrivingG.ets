export class GVector {
  x: number; y: number; z: number;
  constructor(x: number = 0, y: number = 0, z: number = 0) { this.x = x; this.y = y; this.z = z; }
}

export class DrivingGState {
  available: boolean = true;
  running: boolean = false;
  calibrated: boolean = false;
  calibrating: boolean = false;
  valid: boolean = false;
  status: string = '固定手机，停车后校准';
  longitudinal: number = 0;
  lateral: number = 0;
  total: number = 0;
  peakAcceleration: number = 0;
  peakBraking: number = 0;
  peakLateral: number = 0;
  peakTotal: number = 0;
  calibrationProgress: number = 0;
}

const STANDARD_G: number = 9.80665;
function dot(a: GVector, b: GVector): number { return a.x * b.x + a.y * b.y + a.z * b.z; }
function length(v: GVector): number { return Math.sqrt(dot(v, v)); }
function valid(v: GVector): boolean {
  return Number.isFinite(v.x) && Number.isFinite(v.y) && Number.isFinite(v.z);
}
function scale(v: GVector, n: number): GVector { return new GVector(v.x * n, v.y * n, v.z * n); }
function add(a: GVector, b: GVector): GVector { return new GVector(a.x + b.x, a.y + b.y, a.z + b.z); }
function subtract(a: GVector, b: GVector): GVector { return add(a, scale(b, -1)); }

// Phone frame: +X right, +Y top, +Z out of the screen. Mount the screen toward
// the rear of the car. Gravity determines up; projected -Z determines forward.
// This cannot determine whether a user points the phone toward the car's front.
export class DrivingGEngine {
  state: DrivingGState = new DrivingGState();
  private gravity: GVector = new GVector();
  private gravityAt: number = 0;
  private sampleAt: number = 0;
  private up: GVector | undefined = undefined;
  private forward: GVector = new GVector();
  private right: GVector = new GVector();
  private bias: GVector = new GVector();
  private sum: GVector = new GVector();
  private gravitySum: GVector = new GVector();
  private sumSquares: number = 0;
  private samples: number = 0;
  private calibrationAt: number = 0;
  private calibrationGravity: GVector = new GVector();
  private filteredForward: number = 0;
  private filteredRight: number = 0;

  activate(resetPeaks: boolean): void {
    this.state.available = true;
    this.pause(this.up ? '等待传感器更新' : '固定手机，停车后校准');
    this.state.running = true;
    if (resetPeaks) { this.resetPeaks(); }
  }

  pause(status: string): void {
    this.state.valid = false;
    this.state.running = false;
    this.state.calibrating = false;
    this.state.calibrationProgress = 0;
    this.state.status = status;
    this.gravityAt = 0; this.sampleAt = 0;
    this.filteredForward = 0; this.filteredRight = 0;
    this.resetCalibrationSamples();
  }

  unavailable(status: string): void { this.pause(status); this.state.available = false; }

  resetPeaks(): void {
    this.state.peakAcceleration = 0; this.state.peakBraking = 0;
    this.state.peakLateral = 0; this.state.peakTotal = 0;
  }

  calibrate(): void {
    if (!this.state.running || !this.state.available) { return; }
    this.up = undefined;
    this.state.calibrated = false;
    this.state.valid = false;
    this.state.calibrating = true;
    this.state.status = '保持静止约 2 秒';
    this.resetCalibrationSamples();
  }

  private resetCalibrationSamples(): void {
    this.sum = new GVector(); this.gravitySum = new GVector(); this.sumSquares = 0;
    this.samples = 0; this.calibrationAt = 0; this.state.calibrationProgress = 0;
  }

  updateGravity(value: GVector, now: number): void {
    if (!this.state.running || !Number.isFinite(now)) { return; }
    const magnitude = length(value);
    if (!valid(value) || magnitude < 7 || magnitude > 12 || now <= this.gravityAt) { return; }
    this.gravity = value; this.gravityAt = now;
    if (this.up && dot(scale(value, 1 / magnitude), this.up) < Math.cos(Math.PI / 12)) {
      this.up = undefined; this.state.calibrated = false;
      this.state.valid = false; this.state.status = '姿态变化较大，请停车重新校准';
    }
  }

  sample(value: GVector, now: number): void {
    if (!this.state.running) { return; }
    if (!Number.isFinite(now) || now <= this.sampleAt) { return; }
    const gap = this.sampleAt > 0 ? now - this.sampleAt : 20;
    this.sampleAt = now;
    if (!valid(value) || !this.gravityAt || now < this.gravityAt || now - this.gravityAt > 200) {
      this.state.valid = false; this.filteredForward = 0; this.filteredRight = 0;
      this.resetCalibrationSamples();
      this.state.status = '传感器数据暂不可用';
      return;
    }
    if (gap > 500) {
      this.filteredForward = 0; this.filteredRight = 0; this.resetCalibrationSamples();
    }
    if (this.state.calibrating) { this.calibrationSample(value, now); return; }
    if (!this.up) {
      this.state.valid = false;
      if (this.state.status === '等待传感器更新' || this.state.status === '传感器数据暂不可用') {
        this.state.status = '固定手机，停车后校准';
      }
      return;
    }
    const linear = subtract(value, this.bias);
    // A 150 ms time-based low-pass filter reduces vibration. Peaks refer to
    // these filtered horizontal readings, not raw impacts or crash detection.
    const alpha = 1 - Math.exp(-Math.min(gap, 50) / 150);
    this.filteredForward += alpha * (dot(linear, this.forward) / STANDARD_G - this.filteredForward);
    this.filteredRight += alpha * (dot(linear, this.right) / STANDARD_G - this.filteredRight);
    this.state.longitudinal = Math.abs(this.filteredForward) < 0.008 ? 0 : this.filteredForward;
    this.state.lateral = Math.abs(this.filteredRight) < 0.008 ? 0 : this.filteredRight;
    this.state.total = Math.sqrt(this.filteredForward ** 2 + this.filteredRight ** 2);
    this.state.peakAcceleration = Math.max(this.state.peakAcceleration, this.filteredForward);
    this.state.peakBraking = Math.max(this.state.peakBraking, -this.filteredForward);
    this.state.peakLateral = Math.max(this.state.peakLateral, Math.abs(this.filteredRight));
    this.state.peakTotal = Math.max(this.state.peakTotal, this.state.total);
    this.state.valid = true; this.state.status = '水平 G 值 · 仅供参考';
  }

  private calibrationSample(value: GVector, now: number): void {
    const unitGravity = scale(this.gravity, 1 / length(this.gravity));
    if (length(value) > 0.35 || (this.samples > 0 &&
      dot(unitGravity, this.calibrationGravity) < Math.cos(Math.PI / 60))) {
      this.resetCalibrationSamples(); this.state.status = '检测到移动，请保持静止'; return;
    }
    if (this.samples === 0) { this.calibrationAt = now; this.calibrationGravity = unitGravity; }
    this.state.status = '保持静止约 2 秒';
    this.sum = add(this.sum, value); this.gravitySum = add(this.gravitySum, this.gravity);
    this.sumSquares += dot(value, value); this.samples += 1;
    this.state.calibrationProgress = Math.min(1, (now - this.calibrationAt) / 2000);
    if (now - this.calibrationAt < 2000 || this.samples < 40) { return; }
    const bias = scale(this.sum, 1 / this.samples);
    if (this.sumSquares / this.samples - dot(bias, bias) > 0.02) {
      this.resetCalibrationSamples(); this.state.status = '振动较大，请停车后重试'; return;
    }
    const up = scale(this.gravitySum, 1 / length(this.gravitySum));
    const screenForward = new GVector(0, 0, -1);
    const projected = subtract(screenForward, scale(up, dot(screenForward, up)));
    if (length(projected) < 0.5) {
      this.state.calibrating = false; this.resetCalibrationSamples();
      this.state.status = '手机勿平放，屏幕朝向车尾后重试'; return;
    }
    this.up = up; this.forward = scale(projected, 1 / length(projected));
    this.right = new GVector(this.forward.y * up.z - this.forward.z * up.y,
      this.forward.z * up.x - this.forward.x * up.z, this.forward.x * up.y - this.forward.y * up.x);
    this.bias = bias; this.filteredForward = 0; this.filteredRight = 0;
    this.state.calibrated = true; this.state.calibrating = false; this.state.valid = true;
    this.state.longitudinal = 0; this.state.lateral = 0; this.state.total = 0;
    this.state.status = '校准完成 · 水平 G 值'; this.state.calibrationProgress = 1;
  }

  tick(now: number): void {
    if (!this.state.running) { return; }
    if (!this.sampleAt || now - this.sampleAt > 500 || !this.gravityAt || now - this.gravityAt > 500) {
      this.state.valid = false; this.filteredForward = 0; this.filteredRight = 0;
      this.resetCalibrationSamples();
      this.state.status = '等待传感器更新';
    }
  }

  snapshot(): DrivingGState { return JSON.parse(JSON.stringify(this.state)) as DrivingGState; }
}
