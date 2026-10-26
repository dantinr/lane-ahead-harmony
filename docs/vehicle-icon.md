# 大众车辆标记

导航地图的车辆标记使用大众 Logo。Logo 随 GPS 车速旋转，外圈顶部的尖角不参与装饰旋转，车辆位置和朝向仍由高德 SDK 控制。

## 速度与暂停

- 小于 2 km/h 停止；30 / 60 / 120 km/h 分别为每分钟 7.5 / 15 / 30 圈，上限 30 圈。这是装饰动画，不是发动机转速。
- 仅真实 GPS 导航驱动动画，使用 SDK `getSpeed()` 的 km/h 数值；网络定位、精度大于 50 米、无效速度或旧时间戳不用于更新。
- 弱 GPS、关闭定位、进入后台或离开页面立即暂停；恢复后等待新速度。5 秒无更新或定时器明显延迟时停止，不补转。
- 不保存或上传车速及方向样本。结束和到达时停转，退出释放动画资源。

## 接入

使用高德公开的 `AMapNaviComponent` 与自有 `AMapNaviView` 承载导航，通过 `AMapNaviViewOptions.setCarPixelMap()` 更新车辆贴图。首页“开始导航”先打开原生选路页，调用 SDK 从当前位置规划多路线，卡片展示 SDK 返回的耗时和里程，用户选择并点击“开始 GPS 导航”后才启动。地图路线、选中路线和实际 GPS 导航使用同一个 SDK 实例；导航保留 SDK 控制与语音。路由仅传入数字会话 ID。

72 张 112×112 透明贴图以 5° 为一帧，启动时解码一次，帧缓存约 3.5 MiB；定时器 20 Hz，仅在帧变化时更新视图。图片不可用时保留 SDK 默认车标。

## 素材

原始 SVG 为 [Wikimedia Commons 的 Volkswagen logo 2019](https://commons.wikimedia.org/wiki/File:Volkswagen_logo_2019.svg)，本地源文件为 `assets/volkswagen-logo.svg`。该页标记为 PD-textlogo；大众标识归品牌所有。本项目将其处理为白色 Logo、深蓝圆底和绿色方向尖角。

`scripts/generate-car-icon.cjs` 从 SVG 生成已提交的透明帧图 `entry/src/main/resources/rawfile/volkswagen-car-frames.png`。仅重新生成素材需要 Node.js 和 `sharp`，可通过环境变量 `LANEAHEAD_SHARP` 指定其模块路径；普通构建不需要 `sharp`。

SDK 接口参考：[自定义车辆图标](https://lbs.amap.com/api/harmonyosnext-navi-sdk/guide/custom-ui/custom-annotation)、[导航组件基础功能](https://lbs.amap.com/api/harmonyosnext-navi-sdk/guide/navi-component/basic-functions)。

## 验证范围

0.0.27 已完成宿主机测试和完整 ArkTS 编译。测试覆盖速度映射、停车、数据过期、异常时间、帧缓存释放、前后台、页面会话隔离和确认路线后启动导航。真机原地检查包括多路线选择、GPS 导航启动、顶部车道面板与退出；地图车辆贴图已核对。尚未完成行驶时转速变化、跟随效果和性能的实车验证。
