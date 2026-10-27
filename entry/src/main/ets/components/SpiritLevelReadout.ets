import { SpiritLevelState } from '../navigation/SpiritLevel';

@Component
export struct SpiritLevelReadout {
  @StorageLink('laneAheadSpiritLevel') reading: SpiritLevelState = new SpiritLevelState();

  private angle(value: number): string { return Math.abs(value).toFixed(1) + '°'; }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('水平仪').fontSize(18).fontColor('#F1F6F0').fontWeight(FontWeight.Bold).layoutWeight(1)
        Text('屏幕朝上 · 平放测量').fontSize(12).fontColor('#9FB5A8')
      }.width('100%')
      Stack() {
        Circle().width(164).height(164).fill('#10261F').stroke('#4C6557').strokeWidth(1)
        Rect().width(144).height(1).fill('#4C6557')
        Rect().width(1).height(144).fill('#4C6557')
        Circle().width(36).height(36).fill(Color.Transparent).stroke('#B5F489').strokeWidth(1)
        if (this.reading.valid) {
          Circle().width(26).height(26).fill(this.reading.level ? '#B5F489' : '#FFD58A')
            .translate({ x: this.reading.bubbleX * 64, y: this.reading.bubbleY * 64 })
            .animation({ duration: 100, curve: Curve.Linear })
        } else {
          Text('--').fontSize(24).fontColor('#9FB5A8')
        }
      }.width(164).height(164).accessibilityText(this.reading.valid ?
        '总倾角' + this.angle(this.reading.tilt) : '倾角未知')
      Text(this.reading.valid ? '总倾角 ' + this.angle(this.reading.tilt) : '总倾角 --°')
        .fontSize(24).fontColor(this.reading.valid && this.reading.level ? '#B5F489' : '#F1F6F0')
      Row({ space: 12 }) {
        Text(this.reading.valid ? (Math.abs(this.reading.roll) < 0.05 ? '左右 ' :
          this.reading.roll > 0 ? '右侧高 ' : '左侧高 ') + this.angle(this.reading.roll) : '左右 --°')
          .fontSize(14).fontColor('#D1D9CF').layoutWeight(1)
        Text(this.reading.valid ? (Math.abs(this.reading.pitch) < 0.05 ? '前后 ' :
          this.reading.pitch > 0 ? '顶端高 ' : '底端高 ') + this.angle(this.reading.pitch) : '前后 --°')
          .fontSize(14).fontColor('#D1D9CF').layoutWeight(1)
      }.width('100%')
      Text(this.reading.status).fontSize(12).fontColor(this.reading.valid ? '#B7C8BA' : '#FFD58A').width('100%')
      Text('以屏幕平面为参考，无需 G 值校准。请静止测量；摄像头凸起、支架和移动会影响结果。')
        .fontSize(12).fontColor('#9FB5A8').width('100%')
    }.padding(16).width('100%').backgroundColor('#1D352B').borderRadius(14)
  }
}
