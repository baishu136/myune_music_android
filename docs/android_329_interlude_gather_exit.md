# 329：间奏圆点独立聚拢、上漂消隐

2026-09-26。实际基线 0.9.9+328，更新至 0.9.9+329；保留已有未提交成果，不改音频文件、歌词真实时间、解析规则、主题或公开设置。已阅读 README、328/327 记录、相关实现与测试；未找到适用 AGENTS.md。

## 查明的问题与实现

- 原来 reverse 进场控制器，会把 Offset(0,.22) 作为退场方向，向下移动。
- 更关键的是，活动间奏套 ValueListenableBuilder，失焦时却改为直接 Align：原 State 被销毁，新的非活动 State 从透明开始，正常退出根本不能完整执行。新增测试在修改前复现 State 变为 defunct；独立 240ms 终点测试也复现旧 reverseDuration=280ms 未到零（残余透明度 .01785）。日志 `interlude-before.log`。
- 移除按 active 切换的监听包装。间奏始终挂载相同结构，内部监听位置、实际输出、倍率、seek 意图和完成位置；生产环境共享 LyricFrameClock，无播放位置逐帧全列表或圆点组件 setState。独立使用时按需创建可复用 ticker，不使用 DateTime。
- 正常失焦冻结进度、颜色、呼吸和未完成的入场位移，停止媒体推进/呼吸，启动专属退出控制器。入口不 reverse；退场进行中收到预览时间或样式变化不覆盖冻结姿态。短暂 keepAlive 直到控制器完成，销毁时清理所有监听/控制器。
- 默认 **240ms 墙钟、Curves.easeOutCubic**。中心间距由 20px 收到 10px（8px 原始直径，原始边缘空隙 12→2px），整体缩放 **1→.15**、中心上漂 **0→−8px**、alpha **1→0**。实际缩放后的距离也缩小，不能将最终可见空隙称为仍有 2px。选 .15 对齐本次目标描述，不采用示例里不同的 .2 终点。
- 固定 60×8px 画布，与旧三个 8px 点及各 6px side padding 的布局一致。Canvas 标量 translate/scale 控制绘制，FadeTransition 合成 alpha；没有动态 Padding、宽高、行高或 Row relayout。保留固定绘制溢出范围，不给布局增加空间，防止上漂/呼吸在缓存边缘裁切。
- 缓存三个 Paint、Float64List 与一次创建的 repaint listenable。退出帧只做标量运算和绘制，不新建 Paint、List、Map、Rect、Offset 或颜色对象，不排版、不发性能 pulse。颜色仅在正常进度/样式更新时混合，退出前冻结。Flutter 合成层/原生 Canvas 开销仍存在，**不宣称整个 Flutter 引擎零分配**。
- 正常退出保留焦点 alpha/scale/清晰度，避免切行第一帧再叠加 .68 降亮或 blur。保留一个最后退出的间奏索引，快速正文二次换行不提前改变退出样式；解析器间奏大于 8 秒，无需每行退出 Timer 或不断增长的列表。真正 seek/内容变更清除标记。
- Seek 意图立即停止退出并隐藏未知目标的旧圆点；完成位置判断 [start,end) 后直接定位端点，无入场/退出补播。返回间奏时取消旧完成回调的影响。普通位置突变触发已有列表 seek 判定时同样取消退出；暂停/缓冲冻结进度与呼吸，恢复重建媒体锚点，倍率改变不改变退出的墙钟时长。

进场保留旧 340ms/.22 行为；改动仅作用于等待圆点与必要的状态传递。逐字正文位移、渐变、翻译、328 的 500ms 列表缓出及普通歌词动效不变。

## 自动化验证

新增 test/interlude_animation_widget_test.dart：9 项，覆盖 60/90/120Hz 位移/间距/scale/alpha 单调与曲线、冻结颜色/进度、固定 painter/布局尺寸、构建/布局计数不增长、240ms 消隐、State 跨源移除保留、暂停/缓冲/倍率、快速前后 seek/旧完成不回写、快速二次换行与推断 seek、软件像素质心上移/宽度收缩/溢出无裁切。

Flutter controller 在 time==duration 已显示精确端点，status completed 在 time>duration 才发出；完成重置测试额外推进 1µs，视觉终点仍为 240ms，不伪称生命周期回调比框架更早。

最终完整 `flutter test --no-pub`：**308 项通过**，1 项原有可选导出跳过；`flutter analyze --no-pub` 无问题（9.8秒）。`git diff --check` 通过。软件测试不是 Android 120fps 的观感证明。

## 最终真机 profile 结果

设备 V2352A，ADB 10CEB70TQE001E2。请求60Hz轮不录屏，请求120Hz轮同时录制36秒；两轮均开启 Performance Overlay，顺序测量/录屏开销/温度有影响，**不是新旧对照**。最终数据如下，单位ms：

| 退场后300ms窗口 | 请求60Hz | 请求120Hz（录屏） |
| --- | ---: | ---: |
| 窗口帧数 | 144 | 144 |
| Build P95 / 最大 | 1.470 / 7.721 | 1.305 / 5.649 |
| Raster P95 / 最大 | 17.372 / 22.867 | 17.065 / 22.937 |
| Build >16.67ms / >8.33ms | 0 / 0 | 0 / 0 |
| Raster >16.67ms / >8.33ms | 8 / 107 | 10 / 109 |
| 全段 vsync 间隔 P95 / 最大 | 16.553 / 16.559 | 16.554 / 33.099 |

**严格满帧验收未通过。** 两轮 display 属性都报告120.000Hz，但有效回调间隔约16.55ms，不能说真机实际120fps；即使按60Hz预算，仍有Raster超预算帧。没有为了通过而关闭模糊、调低字号或修改预算。不将软件无重排证明等同于GPU零开销；保留完整 FrameTiming、失败预算和原始录屏。

进程RSS（不是GPU内存）请求60Hz为324,186,112→326,504,448字节；请求120Hz为305,655,808→306,626,560字节。只有短时一次测量，不宣称长期内存/功耗稳定。早期绘制边界补全前的数据单独标为 preliminary，不混进最终比较。

录屏 `interlude329-profile-request120.mp4` 为无音频fixture。已检查原始帧中的等待圆点与正文入位过程；录屏编码采样不提供精确120fps观感证明，也没有用某个静态截图替代完整时序验收。

正式 Release 另录制真实歌曲《其实》从 0:00 开始的 32 秒连续片段 `interlude329-qishi-release.mp4`（720×1600，Android screenrecord 无音轨）。检查 17.60–17.95 秒的原始相邻时序：圆点先保持姿态，随后间距和尺寸收缩、亮度降低，并随列表同向上移直至消失；没有观察到旧 reverse 的向下撤出。此歌曲正文很快再次换行，退出圆点仍能完成消散。该片段不提供精确墙钟240ms或零丢帧证明；没有有效的同曲旧版间奏 A/B，不把无间奏的旧版试录列为对照证据。

## 产物与验证范围

证据目录 F:/AGENT/1/test-artifacts/karaoke-329/。ARM64 profile 的 integration_test/interlude_exit_performance_test.dart 使用真实 MobileLyricsList、2秒间奏与2秒折行/翻译轮换，暖机4秒采集30.5秒；采集 exit 后300ms 窗口的原始 FrameTiming，预算失败仍写出 JSON。它是无音频 fixture，不代表完整播放页/GPU 显存或同曲 A/B。

最终正式包按项目命名 Myune-Music-0.9.9-android.329-arm64-v8a.apk，构建命令仅 android-arm64 --split-per-abi。Profile 测试包使用独立 target/build-number，不能当正式播放器分发；测试完成恢复正常 release 与原屏幕刷新率设置，不卸载、不清曲库。

正式 APK：F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.329-arm64-v8a.apk；53,363,258字节，versionCode=2329、versionName=0.9.9，ABI仅arm64-v8a，16KiB zipalign与v2签名校验通过，原有项目签名不变。SHA256：EE6E335DB513DA5840A734F63DCF26639EDE8CE7397993285D42A8173B742720。

Profile 单独使用 build-number=1329，ABI偏移后versionCode=3329、DEBUGGABLE，目标为测试fixture。测试完成 `adb install -r -d` 从可降级的profile测试包覆盖回正式2329，返回Success；正式包无DEBUGGABLE。没有卸载/清数据，也没有用提高正式版本号来掩盖测试包。恢复系统原peak_refresh_rate=144.0、min_refresh_rate=null。

正常release已实际启动到音乐库，收藏仍146首；依 register-generated-program 技能，仅在真实启动验证之后更新既有本地入口，返回ok=true、ID=55597a6477880f94。

验证结束后恢复《Die For You》（VALORANT/Grabbitz）1:57 暂停，保留 `release329-restored.png`；再次读取系统刷新率为144.0/null。未卸载、清数据或修改音频/歌词文件。

本轮修改文件：

- lib/widgets/interlude_animation_widget.dart：独立退出、固定画布、内部监听、生命周期/seek防护；
- lib/widgets/mobile_lyrics_list.dart：稳定挂载、状态传递、退场外层样式保护；
- test/interlude_animation_widget_test.dart：新增9项；test/mobile_lyrics_list_test.dart：进退场复合alpha断言；
- integration_test/interlude_exit_performance_test.dart：新增失败仍保留原始时间线的profile采集；
- pubspec.yaml、lib/page/setting/project_changelog.dart、test/project_changelog_test.dart：329版本；本记录。

留档：F:/临时文件夹/备份/Myune-Music-0.9.9+329-20260926-153424/。完整当前脏工作区源码、正式APK、记录与有效验证证据；排除Git/工具缓存/build/dist/local.properties。328源码与APK仍保留；回退比较须在独立目录解压，不覆盖当前未提交工作区，不通过卸载清数据绕过正式APK降级限制。
