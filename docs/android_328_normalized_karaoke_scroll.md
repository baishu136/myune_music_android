# 328：逐字歌词统一行位移与 500ms 归一化缓出

2026-09-26。以实际 327 工作区为基线更新 `0.9.9+328`，显示 `0.9.9-android.328`，保留全部已有未提交成果及歌曲导入修复。只重构逐字模式的行级位移，不改无关页面、歌词真实边界、翻译高亮规则、公开设置或绘制缓存策略。未发现适用 AGENTS.md；已阅读项目 README、327 记录、源码及相关测试。

## 查明的问题

1. 327 `_LyricLineItem._lyricLineOffset` 没有检查 `karaokeLyricsEnabled`，逐字模式也在每行施加 +.22/0/−.16 的 AnimatedSlide。同时外层 LyricScrollMotion 滚动，两个不同相位的位移共同改变文字行距。
2. 旧 `_usesRowElastic` 只排除了 synthetic/all 模式；timedOnly 模式仍可被旧弹性设置导向逐行弹性，不能保证统一的全列表位移。
3. 327 的 8/.92 弹簧确实有从零速度加速的前段和长尾；约 520ms 只是 95% 行程，不是本轮要求的纯缓出、500ms 结束。
4. 外层滚动还有 .05px 更新门槛，会使已连续计算的尾部数帧不写入 scroll offset，再一起补跳。

先补实际帧率下的渲染中心测试：旧代码在 **60Hz 第一帧** 相邻行距即从 153.142px 变为 151.609px，差约 **1.533px**（`rigid-spacing-before.log`）。新模型集成后，将位置断言收紧到 .01px 又复现旧更新门槛造成 **.0318px** 尾部滞后（`tail-quantization-before.log`）。两项均有修复前失败记录，不仅断言配置常数。

## 改动与职责

### 单一行级垂直驱动

`mobile_lyrics_list.dart`：

- `_lyricLineOffset` 在逐字开启、浏览高亮或模糊抑制时返回 Offset.zero。
- 逐字模式**直接移除 AnimatedSlide controller**，改为无变换的 KeyedSubtree。只将目标改成零不足以阻止从旧普通模式偏移继续插值，因此连动画包装也旁路。
- `_usesRowElastic` 在所有逐字模式下返回 false，合成与真实逐字都走一个列表 offset。普通歌词关闭逐字时仍保留原来的 AnimatedSlide、弹簧与可选逐行弹性。
- 逐字滚动逐帧写入精确亚像素位置，不使用 .05px 过滤；到终点同步精确目标。
- 模式切换重新同步当前列表坐标，避免新驱动继承旧轨迹；切换不强制结束用户正在进行的浏览。

保留焦点缩放、景深和透明度；缩放以文字框中心为锚点，不改变 sliver 行高度。本轮的“刚性行距”指**歌词行布局框/绘制框中心的距离恒定**，不意味着不同长度折行的行高相同，也不意味着焦点字号缩放或已有逐字微浮的墨迹边缘不动。

### 归一化运动

新增 `lib/widgets/lyric_normalized_motion.dart`，实现共享 `LyricScrollDriver` 接口。普通模式选择旧 `LyricScrollMotion`，逐字模式只选择 `LyricNormalizedMotion`，两个驱动不叠加。

普通静止后的换行：

```text
t = elapsedWallSeconds / 0.5，限制在 [0, 1]
p(t) = 1 - (1 - t)^3
x(t) = startOffset + distance * p(t)
v(t) = distance / 0.5 * 3 * (1 - t)^2
```

- 默认 **500ms 墙钟时间**，不随 .75/1/1.5/2 倍速变短。播放倍率仍决定媒体时钟与歌词何时切行，不改变这条列表曲线。
- 150ms/250ms/400ms 分别完成约 65.7%/87.5%/99.2%；500ms 精确到顶，速度归零，无弹簧尾巴、欠阻尼回弹或距离/速度阈值提前截断。
- 首帧即按缓出曲线移动并开始减速，不再先等待弹簧受力加速。初始曲线速度由距离和时长决定，不承诺任意长行的绝对 px/s 峰值相同，也不是给弹簧额外注入峰速。
- 相同目标的每帧 retarget 是 no-op，不重新开始 500ms。
- 使用实际 elapsed 时间，不把延迟帧一律截成 .05 秒，避免模型因掉帧而永久拖慢；卡顿/后台长间隔后按已经经过的墙钟定位，不由本模型掩盖掉帧。

快速连续换行的**同向新目标**在当前姿态与速度处接续单调 Hermite 段：`p(t)=m*t+(3−2m)*t²+(m−2)*t³`。m 在 0–3 内，终点速度为零；很近目标按当前速度缩短剩余时长，以免超调。更远目标在保持初速度与最多 500ms 接续的条件下可能需要再次加速，这是真正的目标重定向，不宣称每次中途改变目标后都严格全程减速。静止后的普通换行仍是固定纯缓出。

明确 seek 继续立即 snap 并清空轨迹，不播放上述重定向；正常反向回中从当前坐标开始负向缓出。新接口不改变普通模式弹簧数学模型。

### seek 回归保护

按真实 400ms 推进后，原有“短暂回报上一行仍保持 seek 目标”测试失败。旧弹簧把大 dt 截为 .05 秒，曾让该用例实际尚未走远而误通过。确认窗口从 120ms 改为 500ms，避免解码器先确认目标、随后又回报旧行时启动反向运动；已有“真实下一行时间戳已到”分支仍立即解除锁，快句不会等待 500ms 确认。该项由原有短行边界和正反 seek 回归测试共同验证，不移动高亮边界。

## 不改的部分

- `mobile_shell.dart` 的播放倍率、实际输出/缓冲、位置、seek 意图/完成传递链未改。
- `karaoke_media_clock.dart`、逐字时序、渐变高亮和正常退出语义未改。
- 原有字符微浮仍为行高 4.5%、760ms 媒体时间、smoothTop；没有将它再换成新的行级物理模型。
- 保留 327 的字形缓存、单个备用预热、复用滤镜、复杂文字回退、透明度合成和共用 vsync。新标量运动计算不创建逐帧容器、不排版、不触发全列表 setState。

## 自动化验证

最终完整 `flutter test --no-pub`：**299 项通过**，原有可选软件图导出跳过 1 项。`flutter analyze --no-pub` 无问题；相关 8 个 Dart 文件格式检查无改动；`git diff --check` 通过（保留原工作区 LF/CRLF 提示）。

- 新 `test/lyric_normalized_motion_test.dart` 7 项：60/90/120Hz 单调位置与递减速度、500ms 终点、不同推进分段同状态、反复同目标不重启、中途接续位置/速度、近目标无超调、负向移动、seek 清空、延迟帧墙钟推进、非法输入防护。
- `test/lyric_transition_performance_test.dart` 新增两项：synthetic/all 和真实词元/timedOnly 在 60/90/120Hz、混合文本/折行/翻译、旧弹性设置开启的 324 个帧样本内，两组相邻绘制中心间距和正常列表曲线均在 .01px 容差内；运动中开启逐字后立刻无 AnimatedSlide，无旧偏移残留。明确是 Flutter 软件几何测试，不是 Android 实测 .01px 光栅精度。
- 更新原有局部位移断言，增加普通模式开关给旧弹性专属用例；没有删掉普通模式弹性验证来隐藏回归。
- 原有高亮、暂停/恢复、倍率、前后 seek、正常换行退出、浏览回中、缓存失效及复杂字符绘制测试继续通过。

## 真机 release 验证记录

设备 V2352A，ADB `10CEB70TQE001E2`。正常正式 release 的同曲《其实》，总时长 4:02，从进度条落点 **59.942 秒**开始，连续 25 秒录屏；720×1600、6Mbps。327 基线先录，再 `adb install -r` 覆盖为最终 328，未卸载或清空数据。两个版本使用现有同一曲库/歌曲/歌词和设置，不换成无音频 fixture。

证据根目录 `F:/AGENT/1/test-artifacts/karaoke-328/`：

- `baseline327-real-qishi-60s.mp4`、`updated328-real-qishi-60s.mp4`：release 同曲连续对照。
- `baseline327-seek60.png`、`updated328-seek60.png`：相同进度起点与歌词片段；
- `flutter-test.log`、`flutter-analyze.log`、`related-tests.log`、修复前失败日志和 `release-build-final.log`；
- 录屏抽样及帧分析文件见同目录。

实际解码：327 为 1508 帧 / 24.900 秒，328 为 1507 帧 / 24.893 秒，容器平均均约 60.5fps；编码时间戳间隔 P95 分别 19.833/20.147ms，最大 23.111/27.933ms。它们是录屏容器数据，**不是应用帧率或耗时**，不支持宣称性能提升。启动录屏与恢复播放存在小量命令/编码器启动偏差，比较应按歌词内容或播放器进度对齐，不能把同一个视频秒数当作同一个音频采样点。

逐帧歌词 ROI 差分：327 没有完全相同 ROI，328 有 3 次（视频 0.938/1.547/2.758 秒，均在首个观察到的换行之前）。静态驻留、编码量化及背景变化影响此值，因此既不将其直接判定为换行冻结，也**不声称零重复帧验收已经通过**。已保留原始视频和 `real-recording-review.json`，不以更低的平均帧差作为“更流畅”的证据。

检查原始抽样帧与 6.5–8.0 秒每 100ms 的过渡序列：首个换行约在视频 7.2 秒附近，全列表向上移动后入位，高亮同时推进；未在这些样本中见缺字、重影或上一折行变暗。这个有限的人工检查不替代全部连续帧的位移拟合，也未实测每次换行均恰好 500ms。录屏工具没有录入音轨，使用的是真实歌曲播放链路，视频自身不能用来听音同步验收。

最终 328 正式包覆盖安装返回 Success，真实启动与播放成功；收藏页仍为 **146 首**。测试后恢复《Die For You》（VALORANT/Grabbitz），定位约 1:58 并保持暂停，不宣称恢复到此前暂停的精确采样点。依据 register-generated-program 技能，在确认真实启动后更新已有本地启动入口（注册返回 ok=true）；未新建重复入口。

本轮未新建 profile 包或重新采集 Flutter FrameTiming/DevTools；release 录屏不能测量 Build/Raster P95、GPU 内存或证明 120fps 满帧。因此 **327 已记录的 Raster 超预算问题不能在本轮宣称解决**，也不把软件运动模型通过等同于真机每一帧都无异常。真机《其实》片段覆盖中文、折行与拖音；英文/复杂文字主要由回归测试覆盖，未在本轮为所有语言逐一录制同曲对照。

## 文件、产物与留档

本轮修改文件：

```text
lib/widgets/lyric_normalized_motion.dart                   新增模型
lib/widgets/lyric_scroll_motion.dart                       通用接口，普通弹簧算法不变
lib/widgets/mobile_lyrics_list.dart                        唯一行级驱动及状态集成
test/lyric_normalized_motion_test.dart                      新增 7 项
test/lyric_transition_performance_test.dart                 行距、轨迹、模式迁移
test/mobile_lyrics_list_test.dart                          seek/普通模式/移除局部位移
test/synthetic_karaoke_test.dart                           新模型对应注释与用例名称
pubspec.yaml                                              0.9.9+328
lib/page/setting/project_changelog.dart                    328 记录
test/project_changelog_test.dart                           当前版本
docs/android_328_normalized_karaoke_scroll.md               本记录
```

仅构建正式 ARM64 release：

```powershell
flutter build apk --no-pub --release --target-platform android-arm64 --split-per-abi
```

APK：`F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.328-arm64-v8a.apk`；53,297,722 字节，versionCode=2328、versionName=0.9.9，原生 ABI 仅 arm64-v8a，16KiB zipalign 与 v2 签名校验通过。SHA-256：`05C03802488AF0254FD00CD7C8868FE167864D241445AB59B3E342B539E47D4C`。

留档目录：`F:/临时文件夹/备份/Myune-Music-0.9.9+328-20260926-143912/`，完整当前工作区源码、正式 APK、本记录、README 与有效验证证据。排除 Git、编译/工具缓存、build/dist 和本机 local.properties，保留未提交源码，不操作原音频文件。

旧 327 正式 APK 仍在 dist，327 完整源码在相邻 327 留档；回退/比较时在独立目录解压，勿覆盖当前脏工作区。正式 Android 降级受系统限制，不用卸载/清数据规避，不新增永久的新旧生产双轨切换设置。
