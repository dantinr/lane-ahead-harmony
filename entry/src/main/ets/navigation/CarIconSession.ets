import { resourceManager } from '@kit.LocalizationKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AMapNaviView, IAMapNavi, IAMapNaviListener, IAMapNaviLocation, NaviType } from '@amap/amap_lbs_navi';
import { CarIconSpin } from './CarIconSpin';

export class CarIconSession {
  private engine: CarIconSpin = new CarIconSpin();
  private frames: image.PixelMap[] = [];
  private listener: IAMapNaviListener;
  private active: boolean = false;
  private foreground: boolean = true;
  private visible: boolean = true;
  private weak: boolean = false;
  private gps: boolean = true;
  private disposed: boolean = false;
  private timer: number = -1;
  private generation: number = 0;
  private locationStamp: number = 0;
  private lastFrame: number = -1;
  private navi: IAMapNavi;
  private view: AMapNaviView;

  constructor(navi: IAMapNavi, view: AMapNaviView, resources: resourceManager.ResourceManager) {
    this.navi = navi; this.view = view;
    this.listener = {
      onStartNavi: (type: number) => {
        this.active = type === NaviType.GPS; if (this.active) { this.refresh(); } this.sync();
      },
      onLocationChange: (location: IAMapNaviLocation | null) => { this.location(location); },
      onGpsSignalWeak: (weak: boolean) => { this.weak = weak; this.sync(); },
      onGpsOpenStatus: (enabled: boolean) => { this.gps = enabled; this.sync(); },
      onStopNavi: () => { this.active = false; this.sync(); },
      onArriveDestination: () => { this.active = false; this.sync(); }
    };
    // Decode once, retain a bounded 3.5 MiB frame cache. Never rotate a marker
    // around a screen coordinate: the SDK owns its position, bearing and anchor.
    let source: image.ImageSource | undefined = undefined;
    let atlas: image.PixelMap | undefined = undefined;
    let stage: string = 'decode';
    try {
      source = image.createImageSource(resources.getRawFileContentSync('volkswagen-car-frames.png').buffer as ArrayBuffer);
      atlas = source.createPixelMapSync({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      const info = atlas.getImageInfoSync();
      if (info.size.width !== 112 || info.size.height !== 8064) { throw new Error('Invalid car icon atlas'); }
      const pixels = new ArrayBuffer(112 * 8064 * 4);
      atlas.readPixelsToBufferSync(pixels);
      stage = 'frames';
      const bytes = 112 * 112 * 4;
      for (let i = 0; i < 72; i++) {
        this.frames.push(image.createPixelMapSync(pixels.slice(i * bytes, (i + 1) * bytes), {
          size: { width: 112, height: 112 }, pixelFormat: image.PixelMapFormat.RGBA_8888,
          // createPixelMapSync defaults source bytes to BGRA, even when the
          // requested output is RGBA. State both formats to preserve blue/red.
          srcPixelFormat: image.PixelMapFormat.RGBA_8888,
          alphaType: image.AlphaType.PREMUL, editable: false
        }));
      }
      stage = 'view'; this.apply(0);
      hilog.info(0x0000, 'LaneAhead', '大众车标贴图就绪');
    } catch {
      hilog.warn(0x0000, 'LaneAhead', '车辆标记加载失败，阶段 %{public}s', stage);
      try {
        const options = this.view.getViewOptions(); options.setCarPixelMap(null); this.view.setViewOptions(options);
      } catch { /* Keep the default SDK car icon. */ }
      this.releaseFrames();
    }
    finally { atlas?.release(); source?.release(); }
    try { navi.addAMapNaviListener(this.listener); } catch { /* A static logo can still be shown. */ }
    try { view.getMapAsync(() => { this.refresh(); }); } catch { /* The start callback also reapplies the icon. */ }
  }

  setForeground(value: boolean): void { this.foreground = value; this.sync(); }
  setVisible(value: boolean): void { this.visible = value; this.sync(); }

  private refresh(): void {
    if (this.disposed || this.frames.length !== 72) { return; }
    this.lastFrame = -1;
    try { this.apply(this.engine.frame()); }
    catch { hilog.warn(0x0000, 'LaneAhead', '车辆标记暂时无法应用'); }
  }

  private location(location: IAMapNaviLocation | null): void {
    if (this.disposed || !this.engine.running || !location) { return; }
    if (!Number.isFinite(location.time) || location.time <= this.locationStamp) { return; }
    this.locationStamp = location.time;
    const usable = location.locationType === 0 && Number.isFinite(location.accuracy) &&
      location.accuracy >= 0 && location.accuracy <= 50;
    let speed: number = NaN;
    try { if (usable) { speed = location.getSpeed(); } } catch { /* Missing speed freezes the logo. */ }
    this.engine.update(speed, Date.now());
  }

  private sync(): void {
    if (this.disposed) { return; }
    const running = this.active && this.foreground && this.visible && this.gps && !this.weak && this.frames.length === 72;
    if (running === this.engine.running) { return; }
    this.generation += 1;
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
    if (!running) { this.engine.pause(); return; }
    this.engine.start();
    const generation = this.generation;
    this.timer = setInterval(() => {
      if (this.disposed || generation !== this.generation || !this.engine.running) { return; }
      try { this.apply(this.engine.tick(Date.now())); }
      catch { this.engine.pause(); clearInterval(this.timer); this.timer = -1; }
    }, 50);
  }

  private apply(frame: number): void {
    if (frame === this.lastFrame || !this.frames[frame]) { return; }
    const options = this.view.getViewOptions();
    options.setCarPixelMap(this.frames[frame]);
    this.view.setViewOptions(options);
    this.lastFrame = frame;
  }

  dispose(): void {
    if (this.disposed) { return; }
    this.disposed = true; this.generation += 1; this.engine.pause();
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
    try { this.navi.removeAMapNaviListener(this.listener); } catch { /* SDK already disposed. */ }
    try {
      const options = this.view.getViewOptions(); options.setCarPixelMap(null); this.view.setViewOptions(options);
    } catch { /* View already disposed. */ }
    this.releaseFrames();
  }

  private releaseFrames(): void { this.frames.forEach((frame: image.PixelMap) => { frame.release(); }); this.frames = []; }
}
