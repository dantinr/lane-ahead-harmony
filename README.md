# LaneAhead · HarmonyOS

原生 ArkTS / ArkUI 导航应用，面向 HarmonyOS 7（SDK / API 26.0.0），包名 `com.laneahead.app`。当前版本 **0.0.12**，统一记录在 `VERSION`。

当前支持：启动后定位并显示原生地图、搜索并选择目的地、在高德原生页面中选择路线、GPS 驾车导航及内置语音引导。**真实前方多个物理路口的车道预览和历史车道缓存尚未实现。**

## 使用流程

1. 首次打开阅读高德地图、定位与导航说明和隐私政策，点击「同意并定位」，允许精确位置权限并开启系统定位服务。选择会在本机保存，以后启动自动定位。
2. 首页显示当前位置、位置精度和地图；定位失败时点击「重新定位」，同时检查系统权限、位置服务与网络。定位未成功时不能开始导航。
3. 输入目的地名称并搜索，可修改城市筛选范围（默认北京市）；核对候选名称和地址后选择。地图会标出选中的终点。
4. 点击「开始导航」，在原生高德选路页确认「我的位置」和终点，选定方案后再点击「开始导航」。此处使用 GPS 模式，并开启内置语音。
5. 返回可结束导航、退出地图并回到首页；重新定位、修改目的地后可再次导航。

地图使用高德 HarmonyOS NEXT 地图 SDK 11.2.1，定位源和坐标处理交给 SDK。终点为搜索返回的 GCJ-02 坐标，导航时不传原始系统 GPS 坐标或 Web 规划的路线 ID；以原生导航页面选中的路线为准。

应用进入后台或导航页面时暂停首页地图定位，返回后重新获取位置。当前按前台导航使用；实车行驶的定位精度、偏航重算、到达、后台和锁屏持续导航尚未验证。

## 默认 Key 与本机配置

本机安装包已默认配置用户提供的两类高德 Key，首页无需填写。「设置」中可查看配置状态，以及进入指定起点规划或车道演示。

- `.local/gaode`：Web 服务 Key，用于地点搜索及可选的 Web 路线规划。
- `.local/gaode-harmony`：HarmonyOS NEXT 平台 Key，用于地图、定位与导航。必须绑定当前应用签名的完整 AppID。
- `scripts/prepare-local-config.cjs` 在构建时读取本机文件，生成 `entry/src/main/resources/rawfile/map-keys.json` 并打入安装包；不把实际 Key 写入可提交源码或构建日志。
- `.local/`、生成的 Key 资源、签名文件和 HAP 均不提交 Git。安装包包含默认 Key，应作为个人使用包保存。更换默认 Key 后重新构建安装。
- 没有本机配置文件时生成空配置，可在首页设置中填写；移除本机配置后再次构建不会保留旧 Key。

DevEco 的 Hvigor 构建入口和命令行脚本均执行配置生成。获取 Key 的官方说明：[鸿蒙 Key 与 AppID](https://lbs.amap.com/api/harmonyosnext-navi-sdk/guide/create-project/get-key)。

## 开发与构建

在 DevEco Studio 选择 **File → Open** 打开 `D:\codex_projects\lane-ahead-harmony`，同步 OHPM 依赖。当前使用 DevEco 内置 SDK 26.0.0.105，模块运行配置为 **entry**。初次可在终端使用其内置 `ohpm install` 安装依赖。

```powershell
cd D:\codex_projects\lane-ahead-harmony
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1
```

使用 PowerShell 7。脚本默认使用 `D:\programs\DevEcoStudio` 内置 Node、JBR、SDK、Hvigor；其他安装路径使用 `-DevEcoHome`。脚本先同步 `VERSION`、准备本机 Key、运行 **31 项测试**，再编译和打包。只测逻辑加 `-TestOnly`。

`VERSION` 从 0.0.10 开始，构建同步应用 `versionName` 和根包清单 `version`。版本名变化时递增原有 `versionCode`，同一版本重复构建不递增；entry 的 OHPM 模块版本独立为 1.0.0。直接在 IDE 构建前可运行 `node scripts/sync-version.cjs` 同步版本。

输出为 `artifacts/LaneAhead-0.0.12-unsigned.hap`；配置本机签名后同时生成 `artifacts/LaneAhead-0.0.12-signed.hap`。未签名包不能直接当签名安装包使用。地图与导航 SDK 声明和资源存在第三方编译警告；本次完整 ArkTS、资源编译和签名构建通过。

## 连接手机

1. 手机启用开发者模式和 USB 调试，连接数据线并允许调试授权。
2. DevEco 的 **File → Project Structure → Project → Signing Configs** 中登录华为开发者账号，完成自动签名，并将 `products.default.signingConfig` 关联签名配置。
3. 顶部选择 **entry** 和手机，点击 **Run**。签名配置、证书和密码只留在本机。

官方说明：[自动签名](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-signing-auto)、[设备调试](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-commandline-emulator)。

## 保留的规划与演示

「设置 → 指定起点规划」保留 Web 地点搜索、起终点选择、备选路线和前 2 / 3 条路线指引预览。**路线步骤不等于物理路口，也不是实时导航。** Web 结果不提供完整车道时明确提示缺失，不套用演示数据。

「设置 → 车道演示」保留五个虚构路口的 2.3 km 回放，可切换 2 / 3 路口、跳过路口、模拟缺失车道、暂停和重置；后台暂停。每个路口的推荐相互独立，不能推断一条车道能连续通过多个路口。

真实路口引擎 `Guidance.ets` 需要与当前路线一致的物理路口、各自车道和推荐方向、沿路线累计距离及地图匹配进度。未知车道不补造；重规划必须使旧路线的路口和进度失效。目前尚未向该引擎接入真实导航进度或车道源。数据核查、北京路线结果及供应商接口边界见 [多路口车道接入说明](docs/lane-data-integration.md)。

## 已验证范围

2026-10-24 完成电脑与 HarmonyOS 真机的 Web 搜索和规划验证；鸿蒙 Key 鉴权、原生选路、GPS 导航界面启动与退出亦已验证。0.0.12 在新地图首页验证默认 Key、首次同意定位、自动获取当前位置、搜索并选择 301 医院、进入选路及启动导航。未进行实车道路测试。

31 项宿主机逻辑测试覆盖独立路口推荐、路线匹配、地点及路线解析、请求参数、精确位置权限拒绝、定位开关、取消过时请求、GPS 模式保护、错误脱敏、首页位置有效性、暂停/销毁、终点标记坐标顺序，以及构建默认 Key 与移除配置后的清理。
