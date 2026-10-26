import { DrivingGReadout } from '../components/DrivingGReadout';
import { drivingGSession } from '../navigation/DrivingGSession';

@Entry
@Component
struct DrivingG {
  onPageShow(): void { drivingGSession.start(); }
  onPageHide(): void { drivingGSession.stop(); }
  aboutToDisappear(): void { drivingGSession.stop(); }

  build() {
    Column({ space: 20 }) {
      Row() {
        Button('返回').fontColor('#B5F489').backgroundColor('#263F2E')
          .onClick(() => { this.getUIContext().getRouter().back(); })
        Text('驾驶 G 值').fontSize(22).fontColor('#F1F6F0').layoutWeight(1).margin({ left: 12 })
      }.width('100%')
      DrivingGReadout().padding(16).backgroundColor('#1D352B').borderRadius(14)
      Text('出发前将手机固定在支架上，屏幕朝向车尾；停车保持静止，点击“停车校准”。手机不要平放。')
        .fontSize(15).fontColor('#D1D9CF').width('100%')
      Text('加速、刹车和左右方向以安装方向为基准。当前值为去重力后的水平加速度，经过滤波，数值仅供参考。')
        .fontSize(14).fontColor('#9FB5A8').width('100%')
      Text('校准仅在本次应用运行期间保留。每次开始导航会重置峰值，导航页顶部同时显示 G 值；进入后台时暂停测量。')
        .fontSize(14).fontColor('#9FB5A8').width('100%')
    }.padding(20).width('100%').height('100%').backgroundColor('#0B1B17')
  }
}
