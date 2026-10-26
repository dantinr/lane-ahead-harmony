import { sensor } from '@kit.SensorServiceKit';
import { DrivingGEngine, GVector } from './DrivingG';

export class DrivingGSession {
  private engine: DrivingGEngine = new DrivingGEngine();
  private active: boolean = false;
  private foreground: boolean = true;
  private generation: number = 0;
  private timer: number = -1;
  private linear: ((data: sensor.LinearAccelerometerResponse) => void) | undefined = undefined;
  private gravity: ((data: sensor.GravityResponse) => void) | undefined = undefined;

  start(): void {
    if (this.active) { return; }
    this.active = true; this.engine.activate(true);
    if (this.foreground) { this.subscribe(); }
    else { this.engine.pause('后台暂停测量'); this.publish(); }
  }

  stop(): void {
    if (!this.active) { return; }
    this.active = false; this.release(); this.engine.pause('测量已结束'); this.publish();
  }

  setForeground(value: boolean): void {
    if (this.foreground === value) { return; }
    this.foreground = value;
    if (!this.active) { return; }
    if (value) { this.engine.activate(false); this.subscribe(); }
    else { this.release(); this.engine.pause('后台暂停测量'); this.publish(); }
  }

  calibrate(): void {
    if (!this.active || !this.foreground || !this.engine.state.available) { return; }
    this.engine.calibrate(); this.publish();
  }

  resetPeaks(): void { this.engine.resetPeaks(); this.publish(); }

  private subscribe(): void {
    const generation = ++this.generation;
    let linearStamp = 0; let gravityStamp = 0;
    this.linear = (data: sensor.LinearAccelerometerResponse) => {
      if (generation !== this.generation || !this.active || !this.foreground ||
        !Number.isFinite(data.timestamp) || data.timestamp <= linearStamp) { return; }
      linearStamp = data.timestamp;
      if (!gravityStamp || Math.abs(linearStamp - gravityStamp) > 200000000) { return; }
      this.engine.sample(new GVector(data.x, data.y, data.z), Date.now());
    };
    this.gravity = (data: sensor.GravityResponse) => {
      if (generation !== this.generation || !this.active || !this.foreground ||
        !Number.isFinite(data.timestamp) || data.timestamp <= gravityStamp) { return; }
      gravityStamp = data.timestamp;
      this.engine.updateGravity(new GVector(data.x, data.y, data.z), Date.now());
    };
    try {
      sensor.getSingleSensorSync(sensor.SensorId.LINEAR_ACCELEROMETER);
      sensor.getSingleSensorSync(sensor.SensorId.GRAVITY);
      sensor.on(sensor.SensorId.GRAVITY, this.gravity, { interval: 20000000 });
      sensor.on(sensor.SensorId.LINEAR_ACCELEROMETER, this.linear, { interval: 20000000 });
      this.timer = setInterval(() => {
        if (generation !== this.generation || !this.active || !this.foreground) { return; }
        this.engine.tick(Date.now()); this.publish();
      }, 100);
    } catch {
      this.release();
      this.engine.unavailable('传感器不可用或无访问权限');
    }
    this.publish();
  }

  private release(): void {
    this.generation += 1;
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
    if (this.linear) {
      try { sensor.off(sensor.SensorId.LINEAR_ACCELEROMETER, this.linear); } catch { /* Already released. */ }
      this.linear = undefined;
    }
    if (this.gravity) {
      try { sensor.off(sensor.SensorId.GRAVITY, this.gravity); } catch { /* Already released. */ }
      this.gravity = undefined;
    }
  }

  private publish(): void { AppStorage.setOrCreate('laneAheadDrivingG', this.engine.snapshot()); }
}

// Only in memory. No sensor samples, calibration or peaks are persisted/uploaded.
export const drivingGSession: DrivingGSession = new DrivingGSession();
