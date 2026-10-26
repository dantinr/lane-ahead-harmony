// Decorative angular speed, not wheel speed or engine RPM. Input is km/h.
export class CarIconSpin {
  angle: number = 0;
  running: boolean = false;
  private speed: number = 0;
  private receivedAt: number = 0;
  private tickAt: number = 0;

  start(): void { this.pause(); this.running = true; }
  pause(): void { this.running = false; this.speed = 0; this.receivedAt = 0; this.tickAt = 0; }

  update(speed: number, now: number): void {
    if (!this.running || !Number.isFinite(now) || now <= this.receivedAt) { return; }
    if (!Number.isFinite(speed) || speed < 0 || speed > 300) {
      this.speed = 0; this.receivedAt = 0; return;
    }
    if (!this.receivedAt || now - this.receivedAt > 5000) { this.tickAt = now; }
    else { this.tick(now); }
    this.speed = speed < 2 ? 0 : speed;
    this.receivedAt = now;
  }

  tick(now: number): number {
    if (!this.running || !Number.isFinite(now) || now <= this.tickAt) { return this.frame(); }
    const elapsed = this.tickAt ? now - this.tickAt : 0;
    this.tickAt = now;
    if (!this.receivedAt || now < this.receivedAt || now - this.receivedAt > 5000 || elapsed > 500) {
      this.speed = 0; return this.frame();
    }
    // 30/60/120 km/h -> 7.5/15/30 rotations per minute; cap at 30 RPM.
    this.angle = (this.angle + Math.min(this.speed * 0.25, 30) * 6 * Math.min(elapsed, 200) / 1000) % 360;
    return this.frame();
  }

  frame(): number { return Math.floor(this.angle / 5) % 72; }
}
