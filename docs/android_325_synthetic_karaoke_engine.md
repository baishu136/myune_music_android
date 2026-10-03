# 325：Synthetic Karaoke 合成逐字歌词引擎

日期：2026-09-26。工作区起始版本实际为 `0.9.9+324`，本轮为 `0.9.9+325`，显示版本 `0.9.9-android.325`。保留原有未提交成果；不重置工作区，不修改无关播放器、原生桌面歌词或主题页面。

## 入口与职责

沿用已有「逐字歌词 → 全部歌词」模式。普通 LRC 在该模式下合成时间轴；「仅逐字歌词」仍只处理有真实词元时间的歌词。没有新增设置，低配回退复用已有「歌词模糊」开关，关闭后移除 `ImageFiltered`，保留透明度阶梯。

| 部分 | 文件 | 职责 |
| --- | --- | --- |
| 合成时间轴 | `lib/widgets/synthetic_karaoke_timing.dart` | 字素安全的分词、权重分配、弱引用缓存；保留原始真实时间 |
| 播放时钟 | `lib/widgets/karaoke_media_clock.dart` | 实际倍率、暂停/缓冲、位置修正、seek 防旧数据回闪 |
| 动效 | `lib/widgets/karaoke_motion.dart` | 由媒体时间确定高亮与小幅上浮；独立退出曲线 |
| 缓存与绘制 | `lib/widgets/karaoke_paint_cache.dart` | 同一份完整字形排版、几何蒙版、物理折行接力、数值缓冲及局部绘制 |
| 列表与交互 | `lib/widgets/mobile_lyrics_list.dart` | 焦点/景深、行几何、浏览、seek、局部重绘和缓存生命周期 |
| 列表弹簧 | `lib/widgets/lyric_scroll_motion.dart` | 保留速度的重定向、解析阻尼弹簧、明确 seek 清空动量 |

移动端实际入口 `lib/mobile/mobile_shell.dart` 已传入真实 `rate`、输出状态、位置、seek 意图与完成事件。本轮检查并复用该传递链，没有为本任务改写播放器或新增另一条生产绘制路径。

## 时间模型与默认运动

- 按完整 Unicode 字素遍历。汉字（含扩展区）、假名、韩文按字素拆分；西文词保留尾随空格。Emoji 家庭、组合重音、假名浊点不拆坏。语言正则作用于完整字素，优于直接对 UTF-16 码元切分。
- 权重 `max(0.25, 非空白字素数^0.72)`；可用时间 `clamp(下行时间差 × 0.92, 650 ms, 8000 ms)`；按累积权重切分，首 Token 从行时间戳开始，末 Token 精确结束于可用时长。没有下一行时采用 4 秒基准，即 3.68 秒合成窗口。
- 合成是视觉估算，不能从 LRC 推断实际演唱字时序。已有可用词元时间始终优先，不覆盖、不挪动原始边界。原始词元、旧有视觉补偿、估算字素时间与合成时间在调用路径中区分；合成路径不使用真实逐字路径的预启动补偿。
- 上浮沿用 324 的独立缓出默认值：行高的 **4.5%**，限制 **1.2–4 px**；**760 ms 媒体时间**，`smoothTop` 到顶缓冲；正常换行冻结旧行姿态，再 **240 ms 实际时间** 退出。2 倍速的 760 ms 上浮实际观看时长为 380 ms，不累计逐帧位移。合成西文按完整词/物理折行片段上浮，中文按字素上浮，不重新拆开连字。
- 合成模式统一使用可重定向行弹簧 `ζ=0.90`、`ω=11 rad/s`，即使旧「弹性滚动」开关打开，也不再走先跳到目标后逐行弹性回放的路径。正常重定向保留位置与速度，解析解在 60/90/120 Hz 的相同媒体时刻一致。
- 从静止启动采用与距离成比例的峰速初值；200 px 移动时约 1222 px/s，随后减速。极短位移不强行达到 1000 px/s，否则必然制造过冲。聚焦透明度/缩放采用 **520 ms**、`Cubic(0.2, 0.72, 0.24, 1)`；弹簧实际入位时间随距离/阈值变化，并非硬性定长。
- 扫光与滚动在行时间戳并行开始，不等滚动结束。羽化宽度按行高计算并限制 **12–18 px**。词元跨物理折行时按实际字形宽度分配扫光进度；之前的物理折行完成后持续白亮，不能退回灰色。
- 当前行缩放 1.1、不透明度 1、无模糊；非焦点透明度距离 1/2/3 为 **0.68/0.52/0.40**，更远 0.32；模糊距离 1/2/3/更远为 **0.9/1.65/2.35/3.0**。模糊原缓存的 .25 量化会改变这些数值，改为 0–3、步长 .05、共 61 个预热过滤器，包含所有精确阶梯。

## 修复与边界处理

1. 原逐帧路径包含临时分组/几何和首次字符蒙版排版。现在在初始化或尺寸/字体变化时一次准备缓存，帧内只算标量并消费缓存；移除旧动画生产分支，避免继续叠加接力算法。
2. 实现期间软件复核发现：透明 TextSpan 分段蒙版会改变长英文的折行，甚至裁掉翻译。最终只排版一个完整段落，所有单元几何蒙版都裁取同一份完整字形；不会通过重新排字破坏 Arabic、Indic 连字或混合文字。斜体/复杂脚本/过长词元采用完整字形片段回退。
3. 翻译/音译始终静态弱化，不合成时间、不高亮、不微浮。原文与翻译共同排版，但蒙版几何分别缓存。
4. 明确 seek 立即使用**目标行内时间**，而非行首时间；选择目标时间之前最近的 LRC 行，不选择未来最近行。清空弹簧速度并 Snap。当前行有短期旧 native 位置保护，非当前行仍保持预备姿态，避免远处整行提前上浮。
5. 普通更新用实际倍率计算预期时间差，再按 >160 ms 误差或 >20 ms 倒退识别不连续；不是将 2 倍速正常进度误当作 seek。明确 seek 事件不需要等待阈值。暂停/缓冲时预期推进为零，输出恢复时重设锚点。先补测试复现「暂停后 20 ms 解码器修正误判 seek，提前退出浏览」的问题，再修复。
6. 快速歌词从接近行尾的 seek 恢复后，合法前进到下一行立即释放确认锁，避免被旧确认窗口卡住。普通确认窗口缩为 120 ms；旧 native 位置保护与正常换行锁独立，后续明确 seek 始终能立即覆盖。
7. 手指触碰即解除追踪并清空列表动量；已处于浏览时保留目标，避免第二次触碰破坏点击跳转。松手并结束滚动后 **3.5 秒** 重定向回当前行，复用时间基准线。

## 性能证据与未验证项

- 每个挂载的歌词绘制缓存只执行 **一次完整 TextPainter.layout**；列表的高度测量是另一个已有的布局缓存阶段，不包含在该计数里。颜色变化不使字形缓存失效；宽度、字体/字号/字重、语言、方向、对齐、缩放、歌词及时间轴变化正确失效。
- 记录全白完整字形 Picture，再构建可复用几何蒙版。图片归挂载行所有，Sliver 剔除/内容替换后明确 dispose；弱时间轴缓存不强行保活旧歌词。过长/复杂词元不生成无限细粒度字形缓存。
- 绘制复用 Paint、Shader、ColorFilter、Rect、Picture 与 Float64List。帧内没有应用层的 Map/List/字符串分组键、几何对象、渐变构造、字形查询、首次字形排版。已完成/未开始的整词合并绘制；正确 `srcIn` 同时处理 RGB 与透明度，不用双层高亮造成变暗或重影。
- 缓存回归测试在 **60/90/120 Hz 共 270 个采样帧** 后，完整排版次数和存活 Picture 数均不增加；行卸载后存活数恢复基线。这证明缓存复用及所有权，不等于真实设备内存/GPU占用测量。
- 当前行独立 RepaintBoundary，媒体时间 ValueListenable 驱动局部 painter；普通进度不重建歌词列表。正常行切换、布局变化及浏览等离散 UI 状态仍可 setState。
- 一个 CustomPainter 处理合成着色路径，但透明蒙版合成仍需 saveLayer；不是「只有一个 GPU 绘制指令」。Native Canvas/display-list、离屏合成、模糊栅格化仍有开销，不能宣称整个引擎零分配或 GPU 功耗已下降。已有可选整行辉光为独立缓存层，没有新增视觉效果。
- 本轮 ADB 设备列表为空。**未安装真机、未录制新旧同曲连续录屏，未取得 60/120 fps、峰值 GPU 内存、温度或功耗数据；不承诺已实测满帧。** 数学连续性和自动化通过不能替代实际观感验收。

## 验证

环境：Windows，Flutter 3.44.9，Dart 3.12.2。

- 最终完整 `flutter test --no-pub`：**276 项通过**，跳过 1 个仅用于输出审查图片的用例，该用例已另行显式运行。
- 最终完整 `flutter analyze --no-pub`：**无问题**；`git diff --check`：通过，仅有工作区原有 LF/CRLF 提示。
- 测试包括分词/权重/真实时间优先/缓存失效、折行已唱部分实际白色像素、翻译像素静态、首字与滚动同步、0.75/1/1.5/2 倍速、暂停恢复浏览、正反 seek、快速换行确认锁、弹簧实际帧率采样、逐字确定性及直接 seek 等价、复杂字符和排版复用。
- 软件图像输出：`flutter test --no-pub --dart-define=KARAOKE_EXPORT_FRAMES=true test/synthetic_karaoke_test.dart --plain-name "export software-rendered multilingual review frames"`。四份接触表为 `F:/AGENT/1/test-artifacts/synthetic-325/fixture_0.png` 至 `fixture_3.png`，采样 0/0.9/1.9/3.7 秒；已检查中文混排、长英文折行、Emoji/日/韩及 Arabic/Indic 字形和静态翻译。Windows 审查图片加载本机可用系统回退字体，不打包进应用；不能替代 Android 字体回退与连续帧实测。
- 增加 `integration_test/synthetic_karaoke_performance_test.dart` 真机 **profile** 基准，采集各倍率、正反 seek、拖拽/回中时 Flutter build/raster 的 p95、超预算帧数、刷新率和暖机前后进程 RSS。未执行该基准；RSS 不是 GPU 内存。设备连接后执行：

```powershell
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/synthetic_karaoke_performance_test.dart -d <device>
```

在设备设置分别锁定 60/120 Hz，保留报告与 timeline，并用同一歌曲片段对比 324/325 的 **release** 录屏；重点观察快速中文、长英文词、折行、拖音及进度拖动。Profile 基准用于管线耗时，release 连续录屏用于实际观感，不能混称为同一测量。

## 已知限制与回退

- 按任务公式保留 650 ms 下限；当下一行早于 650 ms 到来，旧行不会被强行瞬间唱完，而是冻结当前姿态退出。这是估算模型与超快换行的已知边界。8 秒上限也可能让长间隔/长拖音提前全亮；纯 LRC 无法知道真正停顿与拖音。
- 字体是否包含某字取决于选择字体与 Android 系统回退；本方案保留完整字形 shaping，不凭算法生成缺失字形。
- 本轮不保留多套生产动画分支。可在独立目录解压 324 源码基线做对照，不覆盖当前脏工作区：`F:/临时文件夹/备份/Myune-Music-0.9.9+324-20260917-074017/source-0.9.9+324.tar.gz`。原 APK 位于该目录或项目 dist。另有整理后的全工作区源码包 `F:/AGENT/1/artifacts/source-packages/Myune-Music-0.9.9+324-source-20260917-092556.tar.gz`。

## 构建与留档

仅构建 **release ARM64**，使用 `flutter build apk --release --target-platform android-arm64 --split-per-abi`；最终增量构建添加 `--no-pub`，不改变模式/ABI。继续使用项目现有签名配置，不更改签名密钥。产物命名 `dist/Myune-Music-0.9.9-android.325-arm64-v8a.apk`。

- 最终 release ARM64 构建成功；APK 53,363,258 字节，`versionCode=2325`、`versionName=0.9.9`，原生 ABI **仅 arm64-v8a**，16 KiB `zipalign` 与 v2 签名校验通过。
- APK SHA-256：`110D90F83A09EFC615CABB86EA6BF4CB48956773E0947617BAE39A3482455F76`。
- 留档目录：`F:/临时文件夹/备份/Myune-Music-0.9.9+325-20260926-105106/`，包含 `source-0.9.9+325.tar.gz`、同名 APK、本记录、README 与 `software-review/fixture_0.png` 至 `fixture_3.png`。
- 源码快照包含当前工作区所有源码、资产、测试和记录，包括已有未提交成果；不使用 git archive 漏掉未跟踪文件。排除 `.git`、`.dart_tool`、build/dist、Gradle/Kotlin/CXX/Rust target 缓存、自动插件依赖文件和本机 `local.properties`，未删除或改写原文件。

本轮修改文件（不是相对 Git HEAD 的全部脏文件）：

```text
lib/widgets/mobile_lyrics_list.dart
lib/widgets/synthetic_karaoke_timing.dart                 新增
lib/widgets/karaoke_paint_cache.dart                      新增
lib/widgets/karaoke_media_clock.dart
lib/widgets/karaoke_motion.dart
lib/widgets/lyric_scroll_motion.dart
lib/page/setting/project_changelog.dart
pubspec.yaml
test/synthetic_karaoke_test.dart                         新增
test/mobile_lyrics_list_test.dart
test/karaoke_media_clock_test.dart
test/lyric_scroll_motion_test.dart
test/project_changelog_test.dart
integration_test/synthetic_karaoke_performance_test.dart 新增
docs/android_325_synthetic_karaoke_engine.md             新增
```

`lib/mobile/mobile_shell.dart`、播放器状态提供者与其他原生/主题文件已有未提交修改，本轮只检查相关调用，不覆盖它们。
