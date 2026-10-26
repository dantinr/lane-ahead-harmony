import { CompassState } from '../navigation/Compass';

@Component
export struct CompassReadout {
  @StorageLink('laneAheadCompass') reading: CompassState = new CompassState();
  private ticks: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('指南针').fontSize(18).fontColor('#F1F6F0').fontWeight(FontWeight.Bold).layoutWeight(1)
        Text('磁北参考').fontSize(12).fontColor('#9FB5A8')
      }.width('100%')
      Row({ space: 16 }) {
        Stack() {
          Circle().width(144).height(144).fill('#10261F').stroke('#4C6557').strokeWidth(1)
          if (this.reading.valid) {
            Stack() {
              ForEach(this.ticks, (tick: number) => {
                Column() {
                  Rect().width(2).height(tick % 3 === 0 ? 8 : 4).fill('#6D8677')
                  Blank()
                }.width(144).height(144).rotate({ angle: tick * 30 })
              }, (tick: number) => tick.toString())
              Column() {
                Text('北').fontSize(13).fontColor('#FF8276')
                Blank()
                Text('南').fontSize(13).fontColor('#B7C8BA')
              }.width(144).height(118)
              Row() {
                Text('西').fontSize(13).fontColor('#B7C8BA')
                Blank()
                Text('东').fontSize(13).fontColor('#B7C8BA')
              }.width(118).height(144)
              Column({ space: 0 }) {
                Text('▲').fontSize(20).fontColor('#FF8276').height(18)
                Rect().width(4).height(26).fill('#FF8276')
                Rect().width(4).height(26).fill('#93B7A0')
                Text('▼').fontSize(20).fontColor('#93B7A0').height(18)
              }.width(22).height(88)
              Circle().width(8).height(8).fill('#F1F6F0')
            }.width(144).height(144).rotate({ angle: this.reading.rotation })
              .animation({ duration: 100, curve: Curve.Linear })
          } else {
            Text('--').fontSize(30).fontColor('#9FB5A8')
          }
          Text('▾').fontSize(15).fontColor('#B5F489').position({ x: 65, y: -14 })
        }.width(144).height(144).accessibilityText(this.reading.valid ? '红色指针指向磁北' : '方向未知')
        Column({ space: 6 }) {
          Text(this.reading.valid ? this.reading.direction : '方向未知').fontSize(22)
            .fontColor('#B5F489').fontWeight(FontWeight.Bold)
          Text(this.reading.valid ? Math.round(this.reading.heading) % 360 + '°' : '--°')
            .fontSize(26).fontColor('#F1F6F0')
          Text(this.reading.valid ? this.reading.reference : '等待有效传感器数据')
            .fontSize(11).fontColor('#B7C8BA').width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding({ top: 8 })
      Text(this.reading.status).fontSize(11).fontColor(this.reading.valid ? '#B7C8BA' : '#FFD58A').width('100%')
    }.padding(16).width('100%').backgroundColor('#1D352B').borderRadius(14)
  }
}
