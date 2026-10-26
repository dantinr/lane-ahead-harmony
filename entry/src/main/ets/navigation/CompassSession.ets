import { sensor } from '@kit.SensorServiceKit';
import { CompassEngine } from './Compass';
import { GVector } from './DrivingG';

export class CompassSession {
  private engine: CompassEngine = new CompassEngine();
  private active: boolean = false;
  private foreground: boolean = true;
  private generation: number = 0;
  private timer: number = -1;
  private magnetic: ((data: sensor.MagneticFieldResponse) => void) | undefined = undefined;
  private gravity: ((data: sensor.GravityResponse) => void) | undefined = undefined;

  start(): void {
    if (this.active) { return; }
    this.active = true;
    if (this.foreground) { this.engine.start(); this.subscribe(); }
    else { this.engine.pause('后台暂停指南针'); this.publish(); }
  }

  stop(): void {
    if (!this.active) { return; }
    this.active = false; this.release(); this.engine.pause('指南针已停止'); this.publish();
  }

  setForeground(value: boolean): void {
    if (this.foreground === value) { return; }
    this.foreground = value;
    if (!this.active) { return; }
    if (value) { this.engine.start(); this.subscribe(); }
    else { this.release(); this.engine.pause('后台暂停指南针'); this.publish(); }
  }

  private subscribe(): void {
    const generation = ++this.generation;
    let magneticStamp = 0; let gravityStamp = 0;
    this.gravity = (data: sensor.GravityResponse) => {
      if (generation !== this.generation || !this.active || !this.foreground ||
        !Number.isFinite(data.timestamp) || data.timestamp <= gravityStamp) { return; }
      gravityStamp = data.timestamp;
      this.engine.updateGravity(new GVector(data.x, data.y, data.z), Date.now());
    };
    this.magnetic = (data: sensor.MagneticFieldResponse) => {
      if (generation !== this.generation || !this.active || !this.foreground ||
        !Number.isFinite(data.timestamp) || data.timestamp <= magneticStamp) { return; }
      magneticStamp = data.timestamp;
      if (!gravityStamp || Math.abs(magneticStamp - gravityStamp) > 200000000) { return; }
      this.engine.sample(new GVector(data.x, data.y, data.z), data.accuracy, Date.now());
    };
    try {
      sensor.getSingleSensorSync(sensor.SensorId.MAGNETIC_FIELD);
      sensor.getSingleSensorSync(sensor.SensorId.GRAVITY);
      sensor.on(sensor.SensorId.GRAVITY, this.gravity, { interval: 50000000 });
      sensor.on(sensor.SensorId.MAGNETIC_FIELD, this.magnetic, { interval: 50000000 });
      this.timer = setInterval(() => {
        if (generation !== this.generation || !this.active || !this.foreground) { return; }
        this.engine.tick(Date.now()); this.publish();
      }, 100);
    } catch { this.release(); this.engine.unavailable(); }
    this.publish();
  }

  private release(): void {
    this.generation += 1;
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
    if (this.magnetic) {
      try { sensor.off(sensor.SensorId.MAGNETIC_FIELD, this.magnetic); } catch { /* Already released. */ }
      this.magnetic = undefined;
    }
    if (this.gravity) {
      try { sensor.off(sensor.SensorId.GRAVITY, this.gravity); } catch { /* Already released. */ }
      this.gravity = undefined;
    }
  }

  private publish(): void { AppStorage.setOrCreate('laneAheadCompass', this.engine.snapshot()); }
}

// Only the independent driving G page starts this session. No files or network.
export const compassSession: CompassSession = new CompassSession();
