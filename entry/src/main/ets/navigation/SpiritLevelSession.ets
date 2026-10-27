import { sensor } from '@kit.SensorServiceKit';
import { GVector } from './DrivingG';
import { SpiritLevelEngine } from './SpiritLevel';

export class SpiritLevelSession {
  private engine: SpiritLevelEngine = new SpiritLevelEngine();
  private active: boolean = false;
  private foreground: boolean = true;
  private generation: number = 0;
  private timer: number = -1;
  private gravity: ((data: sensor.GravityResponse) => void) | undefined = undefined;

  start(): void {
    if (this.active) { return; }
    this.active = true;
    if (this.foreground) { this.engine.start(); this.subscribe(); }
    else { this.engine.pause('后台暂停水平仪'); this.publish(); }
  }
  stop(): void {
    if (!this.active) { return; }
    this.active = false; this.release(); this.engine.pause('水平仪已停止'); this.publish();
  }
  setForeground(value: boolean): void {
    if (this.foreground === value) { return; }
    this.foreground = value;
    if (!this.active) { return; }
    if (value) { this.engine.start(); this.subscribe(); }
    else { this.release(); this.engine.pause('后台暂停水平仪'); this.publish(); }
  }
  private subscribe(): void {
    const generation = ++this.generation;
    let stamp = 0;
    this.gravity = (data: sensor.GravityResponse) => {
      if (generation !== this.generation || !this.active || !this.foreground ||
        !Number.isFinite(data.timestamp) || data.timestamp <= stamp) { return; }
      stamp = data.timestamp;
      this.engine.sample(new GVector(data.x, data.y, data.z), Date.now());
    };
    try {
      sensor.getSingleSensorSync(sensor.SensorId.GRAVITY);
      sensor.on(sensor.SensorId.GRAVITY, this.gravity, { interval: 50000000 });
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
    if (this.gravity) {
      try { sensor.off(sensor.SensorId.GRAVITY, this.gravity); } catch { /* Already released. */ }
      this.gravity = undefined;
    }
  }
  private publish(): void { AppStorage.setOrCreate('laneAheadSpiritLevel', this.engine.snapshot()); }
}

export const spiritLevelSession: SpiritLevelSession = new SpiritLevelSession();
