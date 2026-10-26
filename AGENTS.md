# 项目开发约定

本文件适用于整个仓库。应用包名为 `com.laneahead.app`，入口为 `EntryAbility`。页面使用原生 ArkTS / ArkUI；Node.js 用于构建脚本和宿主机逻辑测试。

## 代码入口

| 路径（相对 `entry/src/main/ets/`） | 职责 |
| --- | --- |
| `pages/Home.ets`、`navigation/HomeMap.ets` | 首页地图、授权、当前位置与终点选择 |
| `pages/SearchDestination.ets`、`navigation/DestinationSearchSession.ets` | 独立目的地搜索页、内存中的页面结果交接 |
| `navigation/SearchCity.ets`、`navigation/SearchScope.ets`、`navigation/SearchCities.ets` | 定位城市的异步状态、关键词城市前缀解析、公开城市索引 |
| `navigation/VisitedCities.ets`、`navigation/DestinationPlaceSearch.ets` | 从已到达导航历史提取城市、当前城市无名称匹配时的逐城搜索与结果排序 |
| `navigation/SearchHistory.ets`、`navigation/SearchHistoryStore.ets` | 搜索关键词历史与本地存储 |
| `navigation/NativeNavigation.ets`、`navigation/LaneLookAheadSession.ets` | 原生导航会话、SDK 监听与清理 |
| `navigation/LaneSdkData.ets`、`navigation/LanePreview.ets` | SDK 数据适配、引导点距离、实时车道与历史匹配 |
| `navigation/LaneHistoryStore.ets` | 应用私有目录中的车道缓存 |
| `navigation/NavigationHistory.ets`、`navigation/NavigationHistoryStore.ets`、`pages/My.ets` | 导航历史模型、会话持久化与「我的」页面 |
| `navigation/LaneCollection.ets`、`navigation/LaneCollectionStore.ets`、`pages/LaneDiagnostics.ets` | 采集状态、诊断摘要持久化与查看 |
| `components/LaneLookAheadPanel.ets` | 顶部车道面板与原生悬浮层 |
| `navigation/DrivingG.ets`、`navigation/DrivingGSession.ets`、`components/DrivingGReadout.ets`、`pages/DrivingG.ets` | 水平 G 值计算、传感器生命周期、导航读数与独立测量页 |
| `pages/PlanRoute.ets`、`navigation/RoutePlanning.ets` | Web 地点搜索和指定起点规划 |
| `pages/Index.ets`、`navigation/Guidance.ets`、`navigation/DemoRoute.ets` | 完整物理路口模型与虚构演示 |

## 导航与数据约定

- 以原生导航页面实际选中的路线为准，由 SDK 获取并匹配当前位置。搜索终点使用 GCJ-02，经纬度顺序按对应 API 处理；不要直接传入原始系统 GPS 坐标或 Web 路线 ID。
- SDK 路线选择键和原生 path ID 属于不同标识，须分别解析；大整数 ID 保持字符串精度。不能确认属于当前路线的回调不参与提示和学习。
- SDK step 是导航引导点，并非全部物理路口。缺失车道明确显示未知；保持演示、实时与历史来源可区分，不根据转向指令猜测车道数量或填入演示数据。
- 车道历史只保存确认有红绿灯的路口；无红绿灯、标注缺失或相互矛盾时默认不保存，也不复用该点历史；收到的实时车道仍可显示。历史车道按进口/出口几何、方向和转向严格匹配，仅供参考。只关联唯一信号灯与引导点末端，允许两者之间存在总长不超过 60 米、几何连续的路口内部道路（SDK road type 2），进出口必须相连；多灯、普通道路或连接不明不学习。车道结构和推荐转向相同、仅推荐车道位置变化时可更新；结构或推荐转向变化仍按歧义撤销。保留连续越点确认、7 天过期、500 条上限及损坏文件保护；调整规则时补充相关逻辑测试。
- 混合车道仅突出推荐分支，各引导点独立推荐。定位失效、偏航、重算和路线切换时及时撤下旧提示，模拟导航不写入真实历史。
- 采集诊断区分回调、通过确认和文件写入；学习保存与冲突撤销分别报告，不把文件写入次数当作路口数。撤销不存在的记录不触发空写入，面板显示本机有效历史条数；保留未保存原因。诊断仅保留最近一次导航的计数及原因，最多 60 条事件，不写入坐标、道路名、路线 ID 或 Key；定期节流保存，结束时强制保存。
- 导航历史在真实 GPS 导航开始时创建，仅在本机保留最近 200 次目的地、时间、结束状态及出发时规划里程。选路取消和模拟不创建记录；到达不被退出覆盖，旧回调不能修改新会话。异常退出恢复为中断，不编造结束时间或实际行驶里程；导航历史与车道缓存、采集诊断独立清除，不上传真实历史。
- 首页城市根据地图 SDK 的有效 GCJ-02 定位识别，不硬编码默认城市。重新定位恢复自动城市；手动改城市、离页或重新定位时取消并忽略旧城市响应。城市识别与地点搜索使用独立请求；默认限定当前选择城市，关键词中的明确城市优先，仅对本次搜索生效。支持“北京 望京花园”和“北京市望京花园”；简称须用空格分隔，避免把“北京路”“南京饭店”误判为跨城。城市索引来自高德公开行政区划，不含个人位置；更新时保留来源与日期。未指定且无法识别城市时提示补充，不悄悄使用旧城市或全国搜索。
- 搜索历史只在有效搜索响应且请求未过期时记录完整关键词（包括输入的城市），保留最近 20 条并去重置顶；重搜再次解析明确城市，否则使用当前选择城市。仅在本机原子保存，不记录查询坐标或 Key，读写失败不阻断搜索；损坏文件保留，用户显式清空后可重建。清除搜索记录不清除导航历史或车道数据，不上传真实搜索记录。
- 默认搜索当前城市，成功返回但没有名称匹配时，按最近到达时间搜索导航历史中已到达的城市，去重并跳过当前城市，第一个有名称匹配的城市即停止。名称忽略空白和英文大小写，全等优先于包含完整关键词，同等匹配优先已到达目的地；不将分词模糊相关或地址命中当作名称匹配。各城都无名称匹配时优先保留当前城市相关结果，当前城市为空才保留首个历史城市相关结果。明确城市或手动范围不扩大搜索；网络、权限和配额失败不当作空结果，补查失败时保留已有结果并显示未完成。每次请求前后检查会话有效性，取消后不继续查询其他城市。导航记录可含目的地城市摘要，兼容旧记录；旧数据只从明确行政区地址前缀提取城市，不猜店名或实际到达。导航历史删除或清空后，下次打开搜索重新计算去过城市，不另存独立城市足迹；目的地名称仅在本机排序，不随搜索上传。
- 目的地搜索在独立原生页面进行，默认隐藏城市；跨城搜索显示实际搜索城市，结果地址保留服务返回的城市与区县。修改关键词或城市、离页或进入后台时取消旧搜索；取消返回保留原终点，只有当前搜索会话的选择结果可回填首页。Key 与坐标仅在内存交接，不放入路由参数或持久化页面状态。
- SDK 初始化须在隐私同意与位置授权之后。处理过时异步请求，释放地图定位、监听、定时器与悬浮层；退出导航后回到首页，再次进入使用新会话。
- 顶部面板避开转向卡片、速度表和路况条。悬浮层的全屏原生容器使用透明触摸模式，面板外的地图与导航按钮应可操作；不要用默认拦截触摸的全屏自定义组件包装它。
- 驾驶 G 值使用去重力的线性加速度传感器，不再次扣除重力，不用 GPS 速度差冒充传感器读数；重力传感器仅用于停车校准车身水平坐标。屏幕须朝向车尾，不能平放；无法推断安装朝向的正反或绕竖直轴转动。校准要求连续静止约 2 秒且不少于 40 个样本，姿态明显变化撤下读数并提示停车重校。显示值与峰值均为滤波后的水平 G，不当作碰撞或完整三轴过载测量。采样请求 50 Hz、发布 10 Hz；时间戳乱序、两类传感器相差超过 200 ms 或数据超过 500 ms 未更新时不产生新有效读数。未校准、过期或不可用时当前值显示未知。
- G 值仅在真实导航或独立测量页前台订阅；结束、离页或进入后台时释放自身回调和定时器，不移除 SDK 的其他监听。旧回调不能影响新会话。校准仅在应用内存保留，新次测量重置峰值，后台恢复保留本次峰值。原始样本、校准与峰值不持久化、不上传；相关限制与验证范围维护在 `docs/driving-g.md`。

## 构建与验证

在仓库根目录使用 PowerShell 7。默认 DevEco 路径为 `D:\programs\DevEcoStudio`，可用 `-DevEcoHome` 覆盖：

```powershell
pwsh -NoProfile -File .\scripts\build.ps1 -TestOnly
pwsh -NoProfile -File .\scripts\build.ps1
```

- `scripts/build.ps1` 同步版本、准备本机 Key、运行 `tests/*.test.cjs` 中已列入脚本的测试，再进行 ArkTS 编译和打包。新增测试文件时同步更新脚本列表。
- `tests/load-ets.cjs` 在 Node 上转译纯 ETS 逻辑，不能代替 ArkTS 类型检查或 ArkUI 验证。页面、SDK 接口或生命周期变更须完成完整构建；有已授权且连接的手机时检查相关页面和退出流程。
- 纯文档修改检查内容、链接和 `git diff --check` 即可，无需重建或安装应用。
- 将单元测试、真机界面检查和实车验证分开报告，不将模拟样本或弱定位下的界面启动描述为真实道路验证。

## 本机数据与版本

- 实际 Key 位于 `.local/gaode`、`.local/gaode-harmony`，由 `scripts/prepare-local-config.cjs` 生成 `entry/src/main/resources/rawfile/map-keys.json`，安装后自动使用。设置页不提供 Key 编辑；更换本机配置后重新构建安装。不要打印、提交或写入文档；检查设备布局前也须脱敏。
- `build-profile.json5` 可能含本机签名配置、证书路径及密码。保留现有本机改动，提交使用明确文件列表，避免将签名配置一起暂存。
- `.local/`、Key 资源、HAP、日志和设备截图/布局保持被 Git 忽略。设备产物放 `artifacts/device-*`，日志使用 `.log`，不上传真实轨迹或缓存。
- 应用版本仅从 `VERSION` 修改，构建脚本同步 `AppScope/app.json5` 和根 `oh-package.json5`，版本变化时递增 `versionCode`。保留 entry 包独立的模块版本；纯文档修改无需升版。
- 按用户请求提交与推送；提交前检查差异和暂存文件，确保没有实际 Key、签名凭据或个人设备数据。

## 真机调试与交付

本机 HDC 默认路径为 `D:\programs\DevEcoStudio\sdk\default\openharmony\toolchains\hdc.exe`，先用 `list targets` 确认可用设备，不固定设备序列号。签名包位于 `artifacts/LaneAhead-<VERSION>-signed.hap`。

已授权调试时可检查启动、布局、面板交互与退出；本机如有 `.local/phone-debug.cjs` 可辅助操作，但它不是仓库依赖。测试结束退出导航回到首页。交付说明改动、验证结果及未验证范围；详细数据限制维护在 `docs/lane-data-integration.md`，README 保持简短。
