# LaneAhead · HarmonyOS

提前查看未来 2～3 个物理路口的车道、推荐方向及距离。原生 ArkTS / ArkUI 工程，面向 HarmonyOS 7（SDK / API 26.0.0），应用包名 `com.laneahead.app`。

**目前是演示原型：五个虚构路口、2.3 km 路线，没有真实地图、定位或导航服务。** 每个路口的车道推荐相互独立，不能据此推断一条车道可以连续通过多个路口。

## 在 DevEco Studio 打开

1. 选择 **File → Open**，打开文件夹 `C:\codex_works\laneahead-harmony`。
2. 等待工程同步完成；顶部运行配置选择 **entry**。
3. 首次启动 DevEco 的欢迎设置或许可页面需要在 IDE 中完成。本机已检测到 DevEco Studio 26.0.0.851 及内置 SDK 26.0.0.105。

## 运行到模拟器

1. 打开 **Tools → Device Manager**，创建一个 **Phone** 本地模拟器。
2. 选择 API 26.0.0 / HarmonyOS 7 对应镜像，按界面要求下载并启动。当前机器尚未检测到已部署的鸿蒙模拟器镜像。
3. 待模拟器进入桌面后，在 DevEco 顶部设备下拉框选择它。
4. 如果提示签名，进入 **File → Project Structure → Project → Signing Configs**，按下文配置自动签名。
5. 点击顶部绿色 **Run ▶**（运行 entry）。只启动模拟器会显示手机桌面，点击 Run 后才会安装并启动 LaneAhead。

## 运行到 HarmonyOS 7 真机

1. 手机在「设置 → 关于手机」连续点击版本号启用开发者模式。在开发者选项中开启 USB 调试。
2. 用支持数据传输的 USB 线连接电脑，在手机上允许调试授权；设备应出现在 DevEco 顶部设备列表。
3. 打开 **File → Project Structure → Project → Signing Configs**。登录自己的华为开发者账号，勾选 **Automatically generate signature** 并完成自动签名。本工程是 HarmonyOS 工程，初次本地调试可以使用未关联注册应用的自动签名流程。
4. 顶部选择 **entry** 和自己的手机，点击 **Run ▶**。

当前 `artifacts/LaneAhead-0.1.0-unsigned.hap` 是未签名调试包，不能直接当作已签名安装包使用。DevEco 自动签名后会在工程构建目录产生签名包。签名证书和密钥保留在本机，不要提交到版本库。

官方说明：[自动签名](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-signing-auto)、[模拟器命令行与设备调试](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-commandline-emulator)。

## 界面操作

- **2 个 / 3 个**：切换前方路口数量。
- **开始回放 / 暂停**：按选定速度模拟沿路线前进，距离随回放变化；切到后台会暂停。
- **驶过路口**：直接跳到下一个路口之后，检查卡片向前切换。
- **重置**：回到起点。
- **模拟路口 B 缺少车道数据**：检查缺失数据提示。
- 绿色高亮表示该路口演示数据给出的推荐方向；混合车道只高亮被推荐的箭头分支。

## 本机构建与测试

```powershell
cd C:\codex_works\laneahead-harmony
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1
```

脚本使用 `D:\programs\DevEcoStudio` 内置 Node、JBR、SDK 和 Hvigor，先跑 10 项路线逻辑测试，再编译未签名 HAP。安装位置不同时通过 `-DevEcoHome '你的 DevEco 路径'` 指定。只测逻辑可加 `-TestOnly`。

已验证：10 项逻辑测试通过；ArkTS / 资源编译及 HAP 打包成功。宿主机测试直接执行应用的纯逻辑源码，不依赖模拟器。尚未完成：鸿蒙设备上的页面与交互运行验证。独立调用本机 Previewer 时发生工具崩溃，该结果不代表真机运行成功或失败。

## 接入真实数据的边界

核心模型见 `entry/src/main/ets/navigation/Guidance.ets`。每个物理路口关联沿选定路线的累计距离、转向和独立车道信息；车道按驾驶员视角从左到右排列。车道未知使用 `undefined`，不会补造推荐。到达最后一个路口不等于到达终点。

真实进度必须来自当前路线的地图匹配结果。重规划后路线 ID 必须同时更新，旧路线的进度与车道应立即失效。不能用 GPS 到路口的直线距离替代沿路线距离，也不能直接将三条转向指令当作三个物理路口。

国内数据源可行性调研保留在相邻 Android 工程 `C:\codex_works\laneahead\docs\data-feasibility.md`。目前尚未验证任何供应商能在实际路线中提前返回三个物理路口的完整车道信息；后续先验证数据再集成。鸿蒙地图 SDK 是否提供所需未来车道字段，需要独立确认，Android SDK 的能力不能直接套用。
