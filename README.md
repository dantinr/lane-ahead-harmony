# LaneAhead · HarmonyOS

提前查看未来 2～3 个物理路口的车道、推荐方向及距离。原生 ArkTS / ArkUI 工程，面向 HarmonyOS 7（SDK / API 26.0.0），应用包名 `com.laneahead.app`。

**当前是开发版本，尚未实现真实多路口车道导航。** 首页已接入高德 Web 服务的地点搜索、驾车规划和备选路线选择，需要填写有效 Web 服务 Key。已在 HarmonyOS 真机上完成真实搜索和选路验证；没有接入实时定位或导航引擎。

右上角「车道演示」保留五个虚构路口、2.3 km 路线的回放。每个路口的车道推荐相互独立，不能据此推断一条车道可以连续通过多个路口。

## 搜索地点与选路线

1. 在高德开放平台申请 **Web 服务 API** 类型的 Key，填写到首页；此处不使用 Android 或鸿蒙 SDK 类型 Key。Key 仅保存在当前页面内存中，不写入代码、磁盘或日志。
2. 填写城市，分别搜索起点和终点，从返回列表中核对名称及地址后选择。
3. 点击「规划路线」。服务返回的各方案会显示路程、预计耗时及途经道路；返回数量由服务决定。
4. 选择方案后，可预览起点后的前 2 / 3 条路线指引。**这是路线分段预览，不是前方 2 / 3 个物理路口，也不是实时导航。**

修改城市、地点或 Key 会清除旧的选路结果；离开页面、切到后台或修改输入时会取消未完成请求，避免旧结果覆盖新输入。接口不返回车道时明确显示「前方多个路口的车道信息暂不可用」，不会将演示车道套到真实道路。

接入依据与下一步需要的数据见 [真实多路口车道接入说明](docs/lane-data-integration.md)。

## 在 DevEco Studio 打开

1. 选择 **File → Open**，打开文件夹 `D:\codex_projects\lane-ahead-harmony`。
2. 等待工程同步完成；顶部运行配置选择 **entry**。
3. 首次启动时完成 DevEco 的欢迎设置，并安装项目要求的 HarmonyOS SDK。项目当前配置 SDK 26.0.0；请以本机实际安装的 IDE 与 SDK 为准。

## 运行到模拟器

1. 打开 **Tools → Device Manager**，创建一个 **Phone** 本地模拟器。
2. 选择 API 26.0.0 / HarmonyOS 7 对应镜像，按界面要求下载并启动。
3. 待模拟器进入桌面后，在 DevEco 顶部设备下拉框选择它。
4. 如果提示签名，进入 **File → Project Structure → Project → Signing Configs**，按下文配置自动签名。
5. 点击顶部绿色 **Run ▶**（运行 entry）。只启动模拟器会显示手机桌面，点击 Run 后才会安装并启动 LaneAhead。

## 运行到 HarmonyOS 7 真机

1. 手机在「设置 → 关于手机」连续点击版本号启用开发者模式。在开发者选项中开启 USB 调试。
2. 用支持数据传输的 USB 线连接电脑，在手机上允许调试授权；设备应出现在 DevEco 顶部设备列表。
3. 打开 **File → Project Structure → Project → Signing Configs**。登录自己的华为开发者账号，勾选 **Automatically generate signature** 并完成自动签名。本工程是 HarmonyOS 工程，初次本地调试可以使用未关联注册应用的自动签名流程。
4. 顶部选择 **entry** 和自己的手机，点击 **Run ▶**。

脚本输出的 `LaneAhead-0.0.10-unsigned.hap` 是未签名调试包，不能直接当作已签名安装包使用。DevEco 自动签名后还需在 `products.default.signingConfig` 关联已有签名配置，构建目录才会产生 `entry-default-signed.hap`。本次已完成关联、签名构建和真机安装，构建脚本会将签名调试包保存为 `artifacts/LaneAhead-0.0.10-signed.hap`。签名配置、证书和密钥保留在本机，不要提交到版本库。

官方说明：[自动签名](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-signing-auto)、[模拟器命令行与设备调试](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-commandline-emulator)。

## 车道演示操作

- **2 个 / 3 个**：切换前方路口数量。
- **开始回放 / 暂停**：按选定速度模拟沿路线前进，距离随回放变化；切到后台会暂停。
- **驶过路口**：直接跳到下一个路口之后，检查卡片向前切换。
- **重置**：回到起点。
- **模拟路口 B 缺少车道数据**：检查缺失数据提示。
- 绿色高亮表示该路口演示数据给出的推荐方向；混合车道只高亮被推荐的箭头分支。

## 本机构建与测试

```powershell
cd D:\codex_projects\lane-ahead-harmony
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1
```

使用 PowerShell 7（`pwsh`）运行脚本。版本号统一记录在根目录 `VERSION`，从 `0.0.10` 开始；后续修改此文件即可。脚本在构建前同步应用 `versionName` 和根包清单的 `version`，输出包名也从 `VERSION` 读取。应用版本名变化时递增已有 `versionCode`，保证能够覆盖安装；同一版本重复构建不递增。`entry` 的 OHPM 模块版本独立保留为 `1.0.0`，兼容当前 Hvigor 对模块主版本的校验。直接在 IDE 构建前，可先运行 `node scripts/sync-version.cjs` 同步版本。

脚本默认使用 `D:\programs\DevEcoStudio` 内置 Node、JBR、SDK 和 Hvigor，先跑 19 项逻辑测试，再编译 HAP。安装位置不同时通过 `-DevEcoHome '你的 DevEco 路径'` 指定。只测逻辑可加 `-TestOnly`。

未安装 DevEco 时，可使用系统 Node 与 TypeScript 运行纯逻辑测试：

```powershell
$laneTestTools = Join-Path $env:TEMP 'laneahead-test-tools'
npm install --prefix $laneTestTools --no-package-lock --no-save typescript@5.9.3
$env:LANEAHEAD_TYPESCRIPT = Join-Path $laneTestTools 'node_modules\typescript'
.\scripts\build.ps1 -TestOnly
```

本次已验证：19 项宿主机逻辑测试通过，覆盖原有多路口逻辑、地点筛选、规划响应、缺失字段、错误处理及请求参数；使用 DevEco Studio 及 SDK 26.0.0.105 完成 ArkTS、资源编译、签名构建及真机安装启动。真机已检查首页、车道演示、2 / 3 个路口切换、缺失车道提示、驶过路口后卡片更新、回放距离变化，以及切后台后暂停；并修复首页表单居中留白和输入框提示文字对比度问题。

2026-10-24 使用有效 Web 服务 Key 在真机完成「望京地铁站 → 解放军总医院第一医学中心（复兴路28号）」真实搜索、选点、规划、路线切换和 2 / 3 条指引预览。验证了 Key 格式错误提示、搜索无结果，以及修改终点后清除旧路线并禁止规划。修复了选点后输入框回调误清除选中地点、搜索后键盘遮挡候选项的问题，修复包已重新签名安装。无网络及权限/配额错误等异常流程仍待设备验证；**真实导航或真实多路口车道尚未接入验证**。北京测试路线的 OSRM 字段覆盖核查另见接入说明。

## 接入真实数据的边界

核心模型见 `entry/src/main/ets/navigation/Guidance.ets`。每个物理路口关联沿选定路线的累计距离、转向和独立车道信息；车道按驾驶员视角从左到右排列。车道未知使用 `undefined`，不会补造推荐。到达最后一个路口不等于到达终点。

真实进度必须来自当前路线的地图匹配结果。重规划后路线 ID 必须同时更新，旧路线的进度与车道应立即失效。不能用 GPS 到路口的直线距离替代沿路线距离，也不能直接将三条转向指令当作三个物理路口。

目前尚未验证国内供应商能在实际路线中提前返回三个物理路口的完整车道信息；后续先验证数据再集成。鸿蒙 SDK 的能力需要独立确认，Android SDK 的能力不能直接套用。高德 Web 路线规划与当前车道回调都不能替代这个验证，详见本项目的接入说明。
