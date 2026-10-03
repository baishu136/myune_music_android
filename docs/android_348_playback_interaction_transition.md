# Android 348：跳转反馈、全屏双击与页面转场排版治理

日期：2026-10-03。以实际工作区 `0.9.9+347` 为基线，交付 `0.9.9+348`。
保留原有未提交成果，不重置 Git，不提交/推送；旧留档均保留。本轮只构建 ARM64。

## 功能及边界

- 歌词浏览点选跳转播放、进度条提交 seek 增加局部缓冲指示。实际 seek 立即执行，不人为等待动画；播放器位置确认后消隐。最短显示 200ms、淡入淡出 160ms，只有 24×24 的指示器，不遮挡整页、不改变歌词高度。新拖动、失败、换曲或销毁取消旧状态；未确认的位置最多等待约 1.55s，暂停时也不会永久轮询。隐藏后关闭指示器 ticker。
- 全屏沉浸歌词双击切换播放/暂停。使用 Flutter 手势竞争取消同次单击，不使用全局触摸监听或逐帧计时。单击返回封面，保留纵向浏览、横向切歌、长按及双指缩放。异步播放/暂停串行防重入，不改变歌词/封面显示状态。
- 歌词字体上限统一为 36：设置滑块、播放页长按/捏合、加载旧配置及设置写入统一校验。旧的超大字号只在加载该项时限幅，不重置其他配置。主歌词下限保留 12，桌面歌词下限保留 16；桌面设置及 Android 悬浮歌词字号按钮同样限制为 36。
- 未更改已有三种歌词滚动模式、逐字高亮时间、字形墨迹处理、行退出和流体背景算法。

## 已查明并修改的开销

### 1. 全屏高度动画反复使整首歌词排版失效（确认）

`NowPlayingImmersiveLayout` 的 chrome 使用高度过渡，视觉区域每帧收到不同的高度。
原 `_ensureLayoutMetrics` 把视口高度与字体/宽度一起当成文字布局缓存键：每次高度变化均重测所有歌词的 `TextPainter`，清空逐字预热并安排滚动重定位。高度改变并不改变文字宽度、字形和折行，因此该工作不必要。

本轮将文字度量与视口几何分开：仅高度变化时复用行高、字形/逐字缓存，只更新上下 padding 和锚点几何；通常上下锚点差抵消，无需遍历偏移。只有极小视口发生 padding 限幅时修正偏移。正常高度动画不再逐帧重定向现有滚动。宽度、字体、字号、字重、语言、文本缩放、方向、DPR 和歌词变化仍使文字缓存失效。

新增 `MobileLyricsListController.fullTextLayoutCount` 只统计完整文字度量次数，不逐帧发送通知。回归测试连续改变高度 20 帧仍只度量一次；改变宽度后正确重新度量。最终真机两轮全屏入口也均为 **1 次**，不是每个动画帧重测整首歌。

### 2. 主页构建重复生成页面子树（确认代码路径；收益只按实测报告）

主页最多缓存 5 个输入一致的页面 Widget。查询、主题背景开关、选择模式和选中的歌曲变化会更新相应输入键；各子页自己的 Provider 订阅仍实时工作。保留已有相邻页预布局、keep-alive 和 RepaintBoundary，没有复制第二套主页。

### 3. 页面转场与非必要背景工作竞争（确认缺少全局保护）

新增 `PageTransitionWorkObserver`，所有新页面 push/pop 及交互返回均复用现有空闲工作控制器，按真实路由时长加 32ms 保护窗口；初始路由不伪造转场。它不添加每帧监听或全局 setState。

播放页入场期间，封面准备/封面通知不再重复触发整页重建，待路由结束再提交背景输入；实际前景封面仍由已有局部图片监听刷新。此项不延迟解码和 seek，也不冻结播放器。

### 4. 仍未消除的冷帧（明确限制）

最终 profile 仍记录到首次页面构建和 Raster 尖峰。首次进入歌手页 Build 峰值 84.72ms；源码中分组排序会首次初始化拼音词典，属于可疑同步开销，但未取得该帧的 CPU 栈，因此**不能把全部 84.72ms 归因于拼音**。未冒险改动中文分组/排序语义。

首次图层合成、文字图层上传及新页面 Raster 峰值仍需更细的 CPU/Perfetto 帧关联追踪。本轮 FrameTiming 能区分 UI/Raster 阶段，不能独立测 GPU 执行时间，也不能证明系统合成无丢帧。

## 撤回的实验

曾在播放页进入后通过空闲租约预构建一个透明、静音的歌词列表，试图把首次排版移出全屏入口。该方案虽然降低全屏 Build 峰值，但两次同组实测超 16.67ms 帧分别增加到 21/23，Raster 尖峰仍在，部分开销转移到播放页。

**已撤回该额外预构建代码**，最终源码和 `current-348-delivery-arm64-profile.apk`、正式 Release 均不包含它。此前已有的有限逐字字形预热不变。保留实验 JSON/APK 作为失败实验记录，不作为交付包。

## 自动验证

- `flutter test --no-pub --reporter expanded`：**407 通过，1 个既有可选导出测试跳过**。
- `flutter analyze --no-pub`：No issues found。
- `python -m unittest discover -s tool/tests`：6 通过。
- 新增测试：全屏双击不触发单击退出、单击/纵向拖动和非全屏正常点击；跳转反馈确认/连续请求/销毁；字号加载/写入/非有限值限幅；全局路由空闲工作保护；高度动画缓存复用及宽度失效。
- 真机集成用生产 `app.main()`，实际打开播放页、切入/退出全屏、主页切页、主题配置/桌面歌词新页面；断言真实双击播放/暂停、保持全屏、单击返回及 seek 确认/提示收回。`featuresVerified=true`。
- 最终日志：`F:/AGENT/1/test-artifacts/pages-348/all-tests-accepted.log`、`analyze-accepted.log`、`tool-tests.log`。

## 真机性能（Profile，非录屏同时采样）

- vivo V2352A / Android 15，设备 `10CEB70TQE001E2`，Impeller Vulkan。
- Flutter 报告屏幕能力约 120Hz，但 `dumpsys display` 当时实际合成为 **60Hz**。未修改手机全局刷新率设置，**120Hz 满帧未验证**。
- 使用现有已导入曲库，曲目《10cmヒール》，24 行、带翻译/折行。页面转场计时期间暂停音频以减少时间位置差异；交互断言再实际播放。临时逐字/沉浸配置在集成测试 finally 恢复；不卸载、不清空曲库。
- 每阶段采集 Flutter FrameTiming，过预算定义为 Build 或 Raster 任一超过 16.667ms。测试有实时动态背景；窗口包含动作及后续约 1.1s，**不是仅动画关键帧的精确掉帧率**。
- 347 基线因手机 VM 服务发现日志不可用，采用一次人工连接测试；348 使用正常 profile 启动并导出到应用外部文件目录。测试方式和热缓存状态存在差异，只能作为同设备探索性对照，不作统计显著性结论。

### 所有轮次（不只展示最佳结果）

| 记录 | 同组阶段数 | 帧数 | 超 16.67ms 帧 |
| --- | ---: | ---: | ---: |
| baseline-347-manual.json | 16 | 979 | 20 |
| current-348-final.json（初次接受方案） | 16 | 1001 | 13 |
| current-348-prewarm.json（撤回实验） | 16 | 976 | 21 |
| current-348-prewarm-r2.json（撤回实验复测） | 16 | 984 | 23 |
| current-348-delivery.json（最终接受代码，同组子集） | 16 | 996 | 21 |
| current-348-delivery.json（含另 4 个主页切页） | 20 | 1234 | 23 |

最终同组总超预算帧 21 对基线 20，**不支持“整体满帧”或“总掉帧显著下降”的表述**。乐库↔歌单四阶段从基线 5 个超预算帧降至最终 2 个，但样本有限。

### 最终接受代码的各阶段

单位 ms；“超预算”统计整个窗口。原始帧时间戳、Build/Raster 微秒值均在 JSON 中。

| 阶段 | Build P95 | Raster P95 | Build 最大 | Raster 最大 | 超预算 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 乐库→歌单 0 | 2.85 | 6.46 | 23.99 | 11.61 | 1 |
| 歌单→乐库 0 | 1.80 | 5.54 | 6.96 | 6.76 | 0 |
| 打开播放页 0 | 4.85 | 8.07 | 33.37 | 10.94 | 1 |
| 进入全屏歌词 0 | 3.47 | 11.47 | 34.23 | 29.24 | 3 |
| 退出全屏歌词 0 | 3.14 | 10.94 | 9.21 | 14.62 | 0 |
| 关闭播放页 0 | 3.63 | 9.84 | 50.77 | 10.52 | 2 |
| 乐库→歌单 1 | 3.98 | 8.83 | 21.04 | 11.71 | 1 |
| 歌单→乐库 1 | 3.62 | 9.06 | 11.32 | 12.92 | 0 |
| 打开播放页 1 | 5.05 | 8.87 | 27.24 | 9.30 | 1 |
| 进入全屏歌词 1 | 4.79 | 9.65 | 17.36 | 29.11 | 3 |
| 退出全屏歌词 1 | 2.95 | 8.67 | 17.63 | 10.64 | 1 |
| 关闭播放页 1 | 3.78 | 10.32 | 32.21 | 10.73 | 2 |
| 主页→歌手 | 4.03 | 5.87 | 84.72 | 8.03 | 2 |
| 主页→专辑 | 4.37 | 7.39 | 15.89 | 8.99 | 0 |
| 主页→设置 | 4.69 | 6.29 | 12.59 | 11.45 | 0 |
| 主页→音乐库 | 5.07 | 8.19 | 15.75 | 8.51 | 0 |
| 打开主题配置 | 1.78 | 10.12 | 37.92 | 20.68 | 2 |
| 关闭主题配置 | 2.51 | 10.31 | 10.75 | 17.01 | 1 |
| 打开桌面歌词 | 1.76 | 12.49 | 39.47 | 36.03 | 3 |
| 关闭桌面歌词 | 3.53 | 10.08 | 10.37 | 15.23 | 0 |

最终 RSS 单点 485,031,936 bytes（含测试框架及整个 20 阶段缓存），不是长期内存稳定性/泄漏测试。未声称 GPU、功耗或 120fps 达标。

## 正式 Release 复核

仅 ARM64 Release，覆盖安装成功，实际启动截图确认主页和原曲库可用；系统 versionCode=2348（项目 Android 版本码偏移规则），versionName=0.9.9。

- 全屏双击：系统 media_session 观察到 PLAYING → PAUSED；保持歌词界面。
- 单击返回封面、纵向浏览正常；点击浏览目标从暂停恢复播放，再选 2:06 的歌词目标，系统位置约 127.17s，保持歌词页。
- 进度条从约 2s 跳到约 100s，截到局部圆环，确认后消失；不强迫原本暂停的进度条 seek 开始播放。
- 连续录屏：`F:/AGENT/1/test-artifacts/pages-348/release-interactions.mp4`、`release-seek.mp4`。截图 `release-seek-feedback.png`、`release-browse-later.png` 等。录屏只用作交互/视觉复核，**不作为满帧证明**，没有混入上述无录屏 FrameTiming 采样。
- 按本地 `register-generated-program` 技能，在真实启动后更新原快捷项 `55597a6477880f94`，返回 ok=true，没有创建第二个快捷项。

## 修改文件

- `lib/widgets/mobile_lyrics_list.dart`：文字度量与视口几何分离、诊断计数。
- `lib/mobile/mobile_shell.dart`：主页有限复用、入场封面更新保护、seek 反馈及全屏双击接入。
- `lib/widgets/playback_jump_feedback.dart`、`fullscreen_lyrics_double_tap.dart`：局部提示及手势职责。
- `lib/services/page_transition_work_observer.dart`、`lib/main.dart`：全局路由空闲工作保护。
- `lib/page/setting/settings_provider.dart`、`lib/widgets/lyrics_settings_drawer.dart`、`lib/page/setting/tabs/playback_page_tab.dart`、`android/app/src/main/kotlin/com/myune/music/DesktopLyricsOverlayManager.kt`：字号边界。
- `test/mobile_lyrics_list_test.dart`、`lyric_display_settings_test.dart`、`settings_detail_pages_test.dart`、`playback_interaction_test.dart`、`page_transition_work_observer_test.dart`、`project_changelog_test.dart`。
- `integration_test/page_transition_performance_test.dart`：可重复的实际页面/手势/缓存验证及原始 FrameTiming 导出。
- `pubspec.yaml`、`lib/page/setting/project_changelog.dart`、本记录。

## 构建与留档

- 正式包：`F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.348-arm64-v8a.apk`。
- 大小：32,596,258 bytes（31.09 MiB）；SHA256：`1AA7CE1151D24ABD5A823A9B32EF0F379B08253E3B7CBB79C4BD8F867911FA79`。
- 内容审计/ZIP CRC、ARM64-only、完整 MiSans、所有所需 native library、ELF 16KiB 对齐通过；apksigner v2 和 zipalign -P16 检查通过。
- 与 347 比较，27 个受保护字体/资源/引擎/音频 native 项字节哈希一致，新增代码使包增大 10,852 bytes。本轮不是包体积优化，旧审计的“必须比基线小”比较选项不适用，单独检查受保护内容一致性。
- 源码：`F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.348-source-20261003.zip`（包含当前未提交成果，排除构建缓存、Git、安装包和本机签名密钥）。
- 独立备份：`F:/临时文件夹/备份/Myune-Music-0.9.9+348-20261003/`。
- 原始数据/各轮产物/日志：`F:/AGENT/1/test-artifacts/pages-348/`。只有文件名含 `delivery` 的最终 profile 包与正式 dist Release 对应；实验包不应替代交付包。

## 已知限制与后续边界

功能和布局回归通过，但页面冷帧未全部消除；不宣称 60/120fps 全程达标，未达到此前“全部满帧再提交”的条件，因此没有 Git 提交。
未对大规模曲库、所有主题/分屏尺寸或长期播放进行系统性能验收。后续应针对冷帧补 CPU 栈/系统帧时间线，再决定分组排序、首次页面合成或滤镜工作是否值得迁移；不以移除原有动画和字形正确性换取漂亮数字。
