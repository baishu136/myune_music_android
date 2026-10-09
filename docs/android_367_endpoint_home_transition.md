# Android 367：直接目标页切换与主页模糊减负

日期：2026-10-05。基于实际366脏工作区，版本递增至 `1.0.0+367` / `1.0.0-android.367`（ARM64 split versionCode 2367）。保留此前源码、APK、全部性能诊断和失败证据，不提交/推送或发布GitHub Release。

## 用户本轮选择

- 主页点击导航直接衔接当前页和目标页，不显示/构建中间页；过渡延长至600ms。
- 按需加载新目标，保留已访问页面状态，不预加载无关邻页。
- 移除主页按键、歌单卡片/分栏条目的实时背景模糊，保留半透明填充、尺寸、点击范围、配色和歌单内容动效；底部导航和播放状态栏参数原样保留。
- 自定义图片/封面主题的背景配置、歌词模糊、逐字歌词/流体引擎不在这次删除范围内。

## 实现

- `HomeTabController` 表示目标和已落位页，不再把目标索引当作必须经过所有中间页的物理 PageView 位置。删除 `homePageAnimationBridge` 与 jump-to-neighbor 路径。
- `HomeTabViewport` 只在请求时新增目标；先在视口边缘完成目标的布局，下一绘制帧开始600ms运动。自定义场景仅对当前两个端点执行导航布局/绘制；有界缓存最多5个已访问页面。
- 位移直接监听 AnimationController 并 markNeedsPaint，动画帧不 setState/完整排版。隐藏页 TickerMode 关闭、焦点排除，语义仅暴露主导的可见页。滚动位置、组件State和RepaintBoundary保留。
- 返回正在退出的起点，立即从当时位置反向接续。连点第三个不相关页面，只保留最新待导航目标；当前两页落位后再衔接，避免替换半屏页面或瞬间扩展到多页合成。此情况下最终目标可能需等待当前过渡结束，再执行自己的600ms。
- 横向手势仍跟随手指，垂直列表手势及多选时的横向禁用保留。手势取消回到起点，明确 snap/控制器更换/卸载完成待处理Future。
- 页面与顶部标题/操作区统一600ms；保留easeOutCubic页面曲线。全局性能控制器仅收到导航意图与落位通知，不再由物理ScrollController每帧触发。
- `HomeGlassSurface` 仅navigation/playback角色启用BackdropFilter。其余角色仍有70%填充、原圆角/Material/InkWell及两个有界滤镜对象，但disabled过滤不参与合成。底部sigma14/sigma4、alpha70%、尺寸与SafeArea不变；右上角仍完全透明。
- `_TopEdgeFade` 用稳定 `OptionalShaderMask`，disabled/alpha零时直接绘制child，不创建ShaderMaskLayer，不替换子Element。

## 基线和软件验证

修改前新增三项红测，分别实测复现首屏构建0和1、远跳构建0至4、四个实时模糊层而非只保留两底栏。证据 `home-target-367/baseline-red.txt`。

相关45项通过；完整Flutter **499项通过、1项既有跳过**。包含60/90/120Hz软件时间采样下的刚性两页位移、布局/全局通知计数、600ms端点、反向姿态连续、第三目标合并、列表位置/State保留、隐藏ticker、控制器更换/卸载、横/纵手势及RTL/语义。600ms曲线在该时间到位；Flutter插值模拟完成通知在下一次ticker采样，测试没有把此误当额外视觉尾巴。软件采样不代表真机120fps。

静态分析无问题；工具6项单测通过，diff检查通过。开发过程中运动Future误用函数tear-off、严格完成时刻断言及语义测试句柄清理均被测试发现并修正，失败日志保留。没有改变原生行为，因此不冒称本轮重跑原生测试。

## 真机、构建、留档

### 真机 Profile

vivo V2352A / Android15，USB供电，采样结束电池温度29.7°C。独立ARM64 Profile包 `com.myune.music.benchmark`，日志确认Impeller/Vulkan，真实 `app.main()` / `MobileShell` / 歌单 / 设置生产路径；没有使用简化UI或integration_test测试壳。每种歌单布局三轮、每轮六条路径 `0→1、1→0、0→2、2→3、3→4、4→0`，共36次切页，全部到达目标、报告complete=true/error=null。测量时不录屏。

100个音频文件路径、9个自身测试歌单、与366诊断相同生成方式的静态自定义背景。**本轮实际解析95首，366为100首**，因此并非逐内容完全相同的A/B；不改正式曲库来强行对齐。软件/系统API报告120Hz，实际vsync间隔中位数16.59ms，约60Hz；没有验证真正120fps。

热运行排除每种布局首轮。680ms窗口覆盖600ms完整动画和准备余量：

| 布局 | 有效帧 | UI P95 | Raster P95 | UI或Raster >16.67ms |
| --- | ---: | ---: | ---: | ---: |
| 卡片 | 478 | 4.603ms | 8.755ms | 1 |
| 分栏 | 476 | 4.463ms | 8.721ms | 1 |

这两个超预算帧均来自UI，Raster最大分别11.214ms和10.395ms。首轮首次访问歌单/歌手/专辑/设置仍有25.968/31.178/24.356/39.502ms构建尖峰；目的页准备放在运动开始前，但**仍是用户点击之后的负载**，不能说已经完全消除首次进入的卡顿。设置→音乐库热切换UI最大16.794ms（卡片）/14.680ms（分栏），不能承诺每次均低于预算。

与此前366基线都截取首420ms，仅作近似趋势对照：

| 布局 | 366 Raster P95 | 367 Raster P95 | 超16.67ms：366 → 367 |
| --- | ---: | ---: | ---: |
| 卡片 | 15.791ms | 8.993ms | 9/283 → 1/291 |
| 分栏 | 26.485ms | 9.254ms | 44/265 → 1/293 |

366正文320ms/标题380ms，本轮600ms；首420ms不含新版动画尾段。数据为不同时段、内容计数有差异的组合改动实验，不能把下降归因于单项、宣称严格百分比加速或把预算计数当实际呈现掉帧数。原始1300ms窗口完整保留，汇总及限制在 `profile-comparison.json` 和 `home-target-367-summary.json`。Profile启动仍有已有桌面热键插件不支持Android的警告，36次采样没有因此中断；没有扩展任务去改热键。

RSS由384.48MiB至402.43MiB（+17.95MiB），366诊断为355.83→362.48MiB；本轮并没有实测内存下降。页面缓存最多5个，但保活、图片/Provider缓存和短时运行无法证明长期内存/GPU/功耗稳定。仍需长时、真实动态背景、其他机型及120Hz测试；隐藏页可继续接收自身数据通知，禁止的是导航引发的全页排版/逐帧ticker，并非承诺所有后台工作为零。

### 正式 Release 与视觉检查

正式ARM64 Release已覆盖安装并启动，版本2367。保留原曲库、歌单、自定义背景及《A Lonely Night》暂停状态。录屏 `release-home-transitions.mp4`（540×1200，17.32s、无音频）检查音乐库↔设置、音乐库↔歌单及水平手势：可见场景仅源/目标，未出现中间歌手/专辑页；底栏保持原位，歌单分栏及背景配置正常。`release-contact-sheet.png`为4Hz抽样接触表，只辅助验证页面/几何，**不是全帧观感或无冻结证明**。screenrecord为可变帧率，文件平均18.59fps含长静止段，不是应用帧率。正式包未同时采集有效Flutter FrameTiming，性能数来自上述Profile。

按程序登记技能，用已核对的原ADB命令成功启动后更新原入口 `55597a6477880f94`，未新建入口。完成时正式应用前台音乐库、歌曲仍暂停，实验包已停止但保留。

### 必须保留的安装异常

第一次Profile构建使用Gradle环境属性，但实际APK沿用了**正式包名**。安装前漏检身份，导致覆盖正式程序文件；随后启动的是旧366实验包，旧日志不计入367结果。检测到版本不符后立即停止旧实验，已向用户说明。Profile入口在写测试曲库前有包名/目录保护，且错误包的测试入口未被我们启动；没有卸载、清空正式数据或改写正式曲库。

修正只在独立实验目录：将Profile专用applicationId明确为 `com.myune.music.benchmark`；重新构建并在安装前断言包名、2367和ARM64。再安装本轮**正常正式Release**恢复应用，成功启动并验证曲库/背景/暂停状态。错误包 `Myune-Music-1.0.0-android.367-home-profile-arm64.apk` **仅失败证据，不可作为正式交付或再安装**。失败/错启动/恢复/正确安装日志及两份Profile APK均留档。生产Gradle与366基线相同；未来测试包安装必须先审计身份，不能只信构建环境变量。

### 构建、源码和留档

仅构建android-arm64、split ABI。正式Release 32,368,224 bytes，SHA256 `CFFE6650F9E12AE1CA45A08DD78FFA3B7EA9887619AFA9CC6C050C03EF41FCDD`；包名/2367/ABI、CRC、native压缩、ELF LOAD ≥16KiB、v2签名、16KiB zipalign审计通过。签名仍为项目既有debug签名，不擅自换密钥。

生产源码ZIP包含本轮新part、测试和记录，不包含隔离测试入口/本机配置/缓存；隔离Profile源码单独保存。ZIP逐条CRC及与对应源码精确比对、备份SHA256验证执行后，结果保存在 `archive-audit.json`、`scope-verification.json`、`artifact-manifest.json`。与366全680项基线逐文件核对，无无关文件删除；完整播放页尾段、逐字和流体源码不变。

- 基线366源码：`F:/AGENT/1/test-artifacts/home-target-367/source-baseline-366.zip`。
- 软件检查/隔离测试/原始帧数据：`F:/AGENT/1/test-artifacts/home-target-367/`。
- 正式安装包：`dist/Myune-Music-1.0.0-android.367-arm64-v8a.apk`。
- 源码：`dist/Myune-Music-1.0.0-android.367-source-20261005.zip`。
- 独立Profile：`F:/AGENT/1/test-artifacts/home-target-367/Myune-Music-1.0.0-android.367-benchmark-arm64-profile.apk` 与 `Myune-367-profile-source.zip`。
- 备份：`F:/临时文件夹/备份/Myune-Music-1.0.0+367-20261005/`。

## 修改范围与回退

运行实现：`home_tab_viewport.dart`及新 `home_tab_controller.dart` / `home_tab_scene.dart`、`home_glass_surface.dart`、新 `optional_shader_mask.dart`、`mobile_shell.dart`。版本/更新日志、导航/磨砂/蒙版/版本测试及主页Profile集成窗口同步更新；AGENTS和父索引更新当前快照。没有新用户设置，没有改歌词/播放页/流体算法，也没有推送GitHub。

回退对照依据为完整366源码ZIP；未来若用户要求回退，用限定补丁恢复导航/主页滤镜，仍递增版本，不reset脏工作区、不覆盖其它361–366成果。保留页状态会占内存；连续点第三个目标的最多约1.2s等待属于本版明确取舍，不误称每次新点均600ms内完成。
