import { DrivingGState } from '../navigation/DrivingG';
import { drivingGSession } from '../navigation/DrivingGSession';

@Component
export struct DrivingGReadout {
  @Prop compact: boolean = false;
  @StorageLink('laneAheadDrivingG') reading: DrivingGState = new DrivingGState();

  private value(value: number): string { return this.reading.valid ? Math.abs(value).toFixed(2) + 'g' : '--'; }

  @Builder
  metric(label: string, value: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(this.compact ? 10 : 13).fontColor('#B7C8BA')
      Text(value).fontSize(this.compact ? 16 : 24).fontWeight(FontWeight.Bold).fontColor('#B5F489')
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  build() {
    Column({ space: 6 }) {
      Row() {
        Text('驾驶 G 值').fontSize(this.compact ? 13 : 20).fontWeight(FontWeight.Bold)
          .fontColor('#F1F6F0').layoutWeight(1)
        Button(this.reading.calibrating ? '校准中' : '停车校准').height(this.compact ? 26 : 36)
          .fontSize(this.compact ? 11 : 13).backgroundColor('#2D4837').fontColor('#B5F489')
          .enabled(this.reading.available && this.reading.running && !this.reading.calibrating)
          .onClick(() => { drivingGSession.calibrate(); })
      }.width('100%')
      Row({ space: 6 }) {
        this.metric(this.reading.longitudinal < 0 ? '刹车' : '加速', this.value(this.reading.longitudinal))
        this.metric(this.reading.lateral < 0 ? '左向' : '右向', this.value(this.reading.lateral))
        this.metric('水平合成', this.value(this.reading.total))
      }.width('100%')
      Text(this.reading.status + (this.reading.calibrating ?
        ' ' + Math.floor(this.reading.calibrationProgress * 100) + '%' : ''))
        .fontSize(this.compact ? 10 : 13).fontColor(this.reading.valid ? '#B7C8BA' : '#FFD58A')
        .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('峰值 加速 ' + this.reading.peakAcceleration.toFixed(2) + 'g · 刹车 ' +
        this.reading.peakBraking.toFixed(2) + 'g · 左右 ' + this.reading.peakLateral.toFixed(2) + 'g')
        .fontSize(this.compact ? 10 : 13).fontColor('#D1D9CF').width('100%')
      if (!this.compact) {
        Row() {
          Text('水平合成峰值 ' + this.reading.peakTotal.toFixed(2) + 'g')
            .fontSize(13).fontColor('#D1D9CF').layoutWeight(1)
          Button('重置峰值').height(32).fontSize(12).backgroundColor('#2D4837').fontColor('#B5F489')
            .onClick(() => { drivingGSession.resetPeaks(); })
        }.width('100%')
      }
    }.width('100%')
  }
}
