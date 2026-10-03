# Android 349：歌词入场、首句跳转/重播与空白扫光

基线：实际工作区 0.9.9+348；本轮版本 0.9.9+349。保留既有未提交成果，不重置工作区，不改变默认/动感/弹性三种滚动预设。

## 查明的问题与修复

1. 封面→歌词的旧时序在歌词淡入结束后约 245 ms 才接入真实歌词行索引与播放时钟。保留的行级隐式动画在 `TickerMode` 静音时未完成，`Duration.zero` 也不能保证旧 tween 到终点。重新启用后会出现焦点补跳、拉开姿态补算和旧弹性运动复活。
2. 新增内部 `entryPreparing`：歌词完全透明时先接入当前索引/时钟、撤销旧弹性脉冲及退出状态、直接校准既有行属性，经过两次绘制准备回调后开始原淡入。保留缓存与 State，不通过更换 key 重建整个组件。切歌、路由尚未完成及快速反向切页均用修订号取消过期回调。
3. 明确 seek 时同步焦点缩放、景深/拉开姿态与目标扫光状态；等待解码器确认期间保护目标时钟，拒绝过期的位置回报。正常换行仍使用原有预设与亮度出入场，不套用 seek 的立即定位。
4. seek 原本销毁有效的单槽预热缓存；现在只取消未完成预热任务，字体/宽度/语言/内容变更仍按原缓存匹配规则失效。缓存仍有界。
5. 同曲重播原本清空并重新加载歌词，首次重播可导致整首排版重做。现在保留已加载的同曲歌词，在原播放器装载完成后发布归零事件。`LyricSeekNotifier` 把 seek 当作事件，连续两次同目标（例如零）均能通知视觉时钟，不通过空值脉冲触发。
6. 扫光改用 `KaraokeSweepPath`：布局阶段缓存非空白字素的并集与累计可见推进距离，合并连字/重叠簇几何并剔除正字距；逐帧使用预分配 Float64 缓冲区与二分定位跳过空白。实际文本、空格、折行及字形蒙版不变，没有新增裁切。

真实词元边界与既有视觉补偿保持不变；无逐字时间的估算仍是估算。真实词元之间的时间停顿**不**因“忽略间隙”而被压缩。软边羽化、y/g/p 完整墨迹、透明度合成、翻译弱化与复杂文字回退保留。超过 256 个空白分隔组的病态超长词元保持完整段落回退，不为跳过所有空白引入无界逐字几何。

## 本轮文件

- `lib/mobile/mobile_shell.dart`：透明阶段准备与路由/快速切换时序。
- `lib/widgets/mobile_lyrics_list.dart`：行状态校准、seek 目标保护、保留有效预热。
- `lib/widgets/lyric_phase_transition.dart`：显式校准目标，不改变正常运动曲线。
- `lib/widgets/interlude_animation_widget.dart`：隐藏准备时定位现有圆点状态，保持原退出设计。
- `lib/widgets/karaoke_paint_cache.dart`、新增 `karaoke_sweep_path.dart`：缓存空白无耗时扫光路径。
- `lib/page/playlist/playlist_content_notifier.dart`、新增 `lib/services/lyric_seek_notifier.dart`：同曲重播保留歌词与独立 seek 事件。
- 新增 `test/lyric_entry_handoff_test.dart`、`test/karaoke_sweep_path_test.dart`；扩充 `test/karaoke_paint_regression_test.dart`。
- 新增 `integration_test/lyric_entry_seek_performance_test.dart`；版本、项目变更记录与版本测试更新。

## 验证方法

先写入场复现测试，未使用准备机制时，动感/弹性 × 逐字开/关四种组合全部失败（隐藏时焦点缩放还停在 1.0，而不是目标 1.1）。启用修复后通过；再按 60/90/120 Hz 采样确认揭示后不补跳，并验证随后正常换行仍有原动画。

首句测试覆盖焦点尚在运动时跳转、旧解码器位置回报、连续两次归零、缓存未重新整首排版。路径测试覆盖 LTR/RTL、重叠几何、空白跨越和真实帧间隔；真实排版测试覆盖阿拉伯语词组空白、源时间不变及 120 次 paint 无新增 layout。完整测试 419 通过、1 项可选环境测试跳过；Flutter analyze 与 Dart analyze 无问题；打包审计工具 6 项测试通过。

设备：vivo V2352A / Android 15。Profile 使用实际曲库中的《Moth To A Flame》，40 行歌词，原文首段 3619 ms，对照位置 61858 ms；逐字“全部”、歌词模糊开启；两种滚动模式分别测试两轮入场、隐藏期间换行再入场、跳转首句及实际单曲循环。最后恢复所有设置、播放模式及测试前进度，未卸载或清空曲库。

Flutter 报告可用刷新率约 120 Hz，但 SurfaceFlinger 实际周期为 16666666 ns（60 Hz）；不能声称真机 120 Hz 满帧。FrameTiming 是 Flutter Build/Raster 耗时，不是独立 GPU 功耗或端到端显示耗时。录屏与性能采样分开，不混用编码负载下的数据。

对照脚本使用生产播放页根手势的切页回调，避免全屏中央落在另一歌词行时被识别成浏览/跳转，并断言实际进入全屏。最初未断言切页的探索性数据和录屏保留但不作为最终切页对照结论；启动未就绪的首轮也不计入结果。

最终无录屏负载对照：`F:/AGENT/1/test-artifacts/lyrics-entry-349/baseline-348-handoff.json` 与 `current-349-handoff.json`，各 1488 个 FrameTiming 样本。

| 场景 | 348 超 16.67 ms / 样本 | 349 超 16.67 ms / 样本 |
| --- | ---: | ---: |
| 两种模式入场/隐藏换行再入场 | 15 / 528 | 17 / 525 |
| 跳转第一段 | 2 / 253 | 4 / 256 |
| 两种模式自动重播及首段演唱 | 0 / 707 | 0 / 707 |
| 合计 | 17 / 1488 | 21 / 1488 |

348 首次重播的整首排版计数从 1 到 2，歌词引用改变；349 两种模式重播均保留引用与计数 1。349 重播的 Build/Raster 最大耗时分别为 11.89/8.35 ms（动感）和 11.51/8.58 ms（弹性）。但总体超预算数量没有减少，冷入场/个别跳转仍出现 18–33 ms 的尖峰；**不能宣称整体性能实测提升或全部满帧**。此次验证支持的是状态校准与避免重复整首排版，不替代不同歌曲/背景/机型的长期帧率验证；不提供孤立 GPU 内存或功耗结论。

## 产物与回退

ARM64 Release：`dist/Myune-Music-0.9.9-android.349-arm64-v8a.apk`，32606182 字节，SHA-256 `6D1AF91AB972BB9A20027BF9ACA27C09B96F66B8A2BC27AB97BB920D0C7FB1CD`。APK 原生库只含 arm64-v8a，签名/16 KiB 对齐通过；与 348 比较的 11 项原生库、字体及着色器内容完全相同（应用 libapp.so 除外）。不为本轮改动删字体、解码器或 shader。

正式 Release 已覆盖安装并实际启动，版本码 2349（现有 ARM64 分包偏移约定），曲库未清空。另补录实际手势从封面进入全屏歌词、播放首段及随后换行，检查连续录屏与抽样联系表；未观察到揭示后再补算旧焦点的明显姿态跳变。联系表只用于目视抽样，不据此断言每个 60 Hz 帧无冻结，也不作为无录屏负载的 FrameTiming 数据。首次短录屏没覆盖实际切页时刻，仅保留为探索记录。

证据目录：`F:/AGENT/1/test-artifacts/lyrics-entry-349/`：

- 最终 Profile 对照安装包：`baseline-348-verified-handoff-profile.apk`、`current-349-verified-handoff-profile.apk`。
- 同曲连续 Profile 录屏：`baseline-348-handoff-profile.mp4`、`current-349-handoff-profile.mp4`；对应 `baseline-entry-continuous.png`、`current-entry-continuous.png`。
- 正式 Release 实际手势与首段播放：`current-349-release-verified-entry.mp4`、`release-verified-entry.png`、`release-verified-overview.png`。
- 失败复现、完整测试、静态分析、构建与 APK 审计日志保留在同目录。测试后暂停播放、返回主页。

源码留档：`F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.349-source-20261003.zip`；版本备份：`F:/临时文件夹/备份/Myune-Music-0.9.9+349-20261003/`，包含源码包、正式 APK、本记录和有效对照证据。不包含构建缓存、密钥和探索性失败包。与 348 源码包比较的 639 个既有文件均保留，10 个本轮文件有差异；另有 Flutter 自动生成的 `GeneratedPluginRegistrant.java` 在开发依赖检测后加入测试插件注册，不手工改写生成文件。正式 349 与 348 APK 的 `classes.dex` SHA-256 完全一致，未把该开发注册变化引入 Release 原生代码；新增文件单独纳入留档。

依照 `register-generated-program` 技能，在正式包实际启动后更新已有本地 LLMPET 启动入口（同一 ID，不另建重复入口），只更新快捷索引，不发布应用。

348 源码/APK 留档不删除。回退通过对照源码恢复本轮列出的差异，不重置整个 dirty 工作区，不卸载应用。未满足全部满帧前不进行 Git 提交。
