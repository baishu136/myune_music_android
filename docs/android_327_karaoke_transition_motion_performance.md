# 327：逐字歌词换行运动与绘制负载修正

2026-09-26，实际工作区从 `0.9.9+326` 更新至 `0.9.9+327`（显示 `0.9.9-android.327`）。保留已有未提交源码及 326 的导入修复；未重置工作区，未修改无关页面、主题、歌词真实时间边界或新增公开设置。

## 结论及验收状态

已实施自然启动、低频长尾弹簧、下一行有限预热、滚动期非焦点静态模糊、共用 vsync 和未起唱文字合并绘制；自动化回归通过。**真机性能验收尚未通过**：同场景 profile 录屏测得换行 Raster P95 从 326 的 21.730ms 降至 327 的 17.064ms，但仍有超过 12ms 的 Build/Raster 帧。不能宣称 60/120fps 满帧、首帧 CPU 小于 0.5ms、消除所有冻结或降低 80% 离屏开销。

## 实际问题与修改依据

1. `launchFromRest` 原本直接设置与距离成比例的峰速；判停阈值 4px/s，会让短途行程快速结束。新版保留调用 API，但不注入任何速度，从静止自然加速，重定向继承当前位置和速度。默认逐字滚动 `frequency=8rad/s`、`dampingRatio=.92`，判停要求距离小于 .35px 且速度小于 1.2px/s。解析解保持不同帧率一致。
2. 新挂载行此前在构建时准备字形缓存；通常下一行已在视口缓存中，但超长折行使下一行完全离屏时，首次激活仍会排版。新增当前行 80% 或边界前 400ms 的预热入口：当帧结束后的宏任务构建一个离屏备用缓存，真正挂载时转移所有权。已挂载行不重复预热，迟到任务、浏览、切歌、样式/宽度/语言变化均作废。宏任务不是后台线程，仍有主线程成本；不保证任何突发 seek 的目标都提前缓存。
3. 非焦点行在弹簧移动期间不再逐帧插值 sigma，直接采用缓存的目标模糊阶梯，停止隐式模糊 controller；运动结束时已在目标值，不人为再播放一次模糊补偿。当前行进入清晰状态仍保留其过渡，透明度与既有焦点缩放保留。
4. `_onMotionTick` 原本每帧发性能 pulse。改为开始时发一次、结束时释放。新增 `LyricFrameClock` 共用 vsync：先推进列表弹簧，再通知活动歌词媒体时钟。新行开始滚动以已有 clock.elapsed 作锚点，避免继承整首歌的 elapsed 当作第一帧 dt；无运动/监听者时停止 ticker。正常退出仍使用独立墙钟动画，不伪装成媒体 seek。
5. 第一轮真机数据提示主要瓶颈是 Raster，而非已证明的 15ms 激活 CPU。检查发现未来行和当前行未唱尾部仍按每个词元建立着色 saveLayer。新增整段未起唱原文蒙版和有限后缀蒙版，在相同颜色、零位移时合并绘制；翻译独立弱化。额外后缀只用于最多 64 个词元的行，超长行回退原路径。预计算后缀最早运动时间，兼容非按时间排序的真实词元；未起唱缓冲状态也清零，避免 seek 回退遗留姿态。静态 CustomPaint 标记允许 raster cache，活动/退出行仍标记 willChange。

绘制保留完整已整形段落、字素映射、复杂文字/连字回退和透明度合成。paint 没有新增排版、字符串键、List/Map 或懒生成 Picture；Canvas/saveLayer 的原生分配和 GPU 成本仍然存在，**不是整个 Flutter 引擎零分配**。

## 运动时长的明确含义

- 列表滚动按**墙钟/vsync 秒**积分；倍率不缩短列表弹簧本身，快句可在移动中重定向。
- 8/.92 从静止出发，150ms 约完成 35%，520ms 约完成 95%；剩余亚像素尾部自然收敛，完整判停约 1 秒且与距离有关。它不能同时满足“无峰速启动”和“150ms 完成 60%”，也不能把 95% 到达时间称为完全停稳时间。
- 60/90/120Hz 实际帧采样的首次 95% 到达分别约 533.3/522.2/525ms，60Hz 多一个采样周期；250ms 不再硬停。没有为了凑 520ms 人为剪掉长尾。真机录屏不等于精确的数学时长测量，本轮未完成每种实际行距的感知时长标定。
- 字符微上浮维持既有配置：行高 4.5%、760ms **媒体时间**、smoothTop，错开 .15，最多 35ms 预启动；高亮羽化 12–18px、正常退出 240ms 墙钟。本轮没有将逐字高亮边界移动以匹配弹簧。
- 非逐字列表保留原来随字号调整的频率与 .90 阻尼，而不是全部改为 8/.92。

## 职责与文件

| 部分 | 文件与职责 |
| --- | --- |
| 媒体同步 | 既有 `karaoke_media_clock.dart`，保留倍率、暂停、实际输出、seek 锚点；检查 `mobile_shell.dart` 实际传递链，本轮未再改播放器 |
| 帧节奏 | 新增 `lyric_frame_clock.dart`，一个按需 vsync 同步列表和歌词绘制 |
| 字形准备 | `karaoke_paint_cache.dart` 与新增 part `karaoke_prewarm.dart`，整形几何、蒙版、有界预热及原生 Picture 生命周期 |
| 运动 | `lyric_scroll_motion.dart` 列表弹簧；既有 `karaoke_motion.dart` 确定性逐字位移与高亮，未改变时间语义 |
| 集成/绘制 | `mobile_lyrics_list.dart` 缓存转移、共享时钟、静态模糊、局部 CustomPaint，不通过每帧 setState 重建列表 |

其他本轮文件：`pubspec.yaml`、`lib/page/setting/project_changelog.dart`、`test/project_changelog_test.dart`；测试/采集文件见下文。`karaoke_prewarm.dart` 是缓存层的 part，未重写整个歌词组件。

## 自动化验证

- 完整 `flutter test --no-pub`：**290 项通过**，原有可选图片导出用例跳过 1 项；另以 `KARAOKE_EXPORT_DIRECTORY` 指定新目录运行合成歌词图片导出组，14 项通过并检查 4 张图。
- 完整 `flutter analyze --no-pub`：无问题。`git diff --check` 通过，工作区原有 LF/CRLF 提示不作无关改写。
- `test/lyric_scroll_motion_test.dart`：60/90/120Hz 同时刻位置一致、自然起步、250ms 不判停、95% 到达窗口、尾部小位移判停、重定向速度连续、seek 同步及长帧稳定。
- 新增 `test/lyric_transition_performance_test.dart`：超长首行使下一行离屏，在边界前预热；激活不追加布局计数；宽度改变失效；卸载 Picture 数量回归；运动 25 帧期间非焦点行使用相同静态滤镜实例。
- 新增 `test/lyric_frame_clock_test.dart`：两个消费者获得相同帧时间、停滚动仍继续播放、最后监听者退出后停表、再次启动无旧 elapsed、销毁后无 ticker 遗留。
- `test/synthetic_karaoke_test.dart`：静止原文和翻译仅两个 solid 层，未唱尾部合并且绘制不追加排版；非顺序时间不错误合并；80 词元行不建立额外后缀集合；相关原有 seek、速率、折行、复杂文字及透明度回归继续通过。调整旧短尾假设，不只改某个固定参数断言。
- 既有 `karaoke_media_clock_test.dart`、`karaoke_motion_test.dart`、`mobile_lyrics_list_test.dart` 等继续覆盖暂停/缓冲/恢复、倍率、正反 seek、换行姿态和浏览。**公式连续与软件图片通过不代替真机观感结论。**

## 真机 profile 对照

设备 V2352A，ADB `10CEB70TQE001E2`，ARM64 profile，Performance Overlay 开启。326 从已有完整源码留档解压到独立目录，加入同一测量 fixture 后构建；没有把当前工作区回退。通过 `adb install -r` / debug-profile 基线的 `-r -d` 覆盖测试，不卸载、不清空曲库。

fixture 使用同一组 48 行、两秒行间隔的快速中文、折行长英文、混合中日韩/组合字符、阿拉伯文/印地文及静态翻译，预运行 4 秒；采集 .75/1/1.5/2 倍、前后 seek 和拖动/回中。**这是可复现的无音频歌词组件场景，不是用户同一首真实歌曲/音频完整播放页的 A/B 测试。** 真实页面的封面/背景/GPU 叠加成本未由此排除。

同时连续录屏 35 秒（720×1600），automatic line-change 后 650ms 的窗口统计如下，单位 ms：

| 指标 | 326 同 fixture | 327 最终实现 |
| --- | ---: | ---: |
| 采集帧数 | 1248 | 1267 |
| 全段 Build P95 | 1.638 | 2.001 |
| 全段 Raster P95 | 19.830 | 17.237 |
| 换行窗口 Build P95 | 1.605 | 2.039 |
| 换行窗口 Raster P95 | 21.730 | 17.064 |
| 换行窗口 Build 最大值 | 11.938 | 39.434 |
| 换行窗口 Raster 最大值 | 44.946 | 46.322 |
| 换行窗口 Build >12ms | 0/614 | 4/635 |
| 换行窗口 Raster >12ms | 319/614 | 167/635 |
| vsync 间隔 P95 / 最大值 | 16.561 / 33.118 | 16.557 / 66.196 |
| RSS 前 / 后，MiB | 354.5 / 413.2 | 317.7 / 399.0 |

换行 Raster P95 本次约降 21.5%，但 Build 尖峰未消除，最大帧间隔未改善，不能只选 P95 宣称卡顿根除。单次顺序测量、温度/冷启动/录屏和不同初始 RSS 会干扰结果；RSS 为进程内存，不是 GPU 内存，不能据此宣称显存减少或长期内存平稳。

另对 326 请求 120Hz、不录屏重跑：换行 Build/Raster P95 为 1.734/21.102ms，vsync 间隔 P95 为 16.560ms，说明基线 Raster 超预算不单由录屏导致；对应新版不录屏一轮未取得有效完整报告，不作配对结论。

系统测试时 peak/min 分别请求过 60/60 与 120/120。Flutter `View.display.refreshRate` 均报告约 120，但有效 frame 间隔主要约 16.6ms；OEM 的主屏/虚拟显示/应用调度信息不一致。保留原始 display dump，不将显示器属性当成 120fps 实测。严格测试用其原始 8.33ms 预算并保持失败，不降低门槛掩盖问题；即使采用 60Hz 的 16.67ms，327 换行 Raster P95 仍超预算。

测试完恢复原系统 peak=144.0、min=null，正式 release 覆盖回应用。没有卸载或清空数据。

最终正式包安装返回 Success；`versionCode=2327` 且无 DEBUGGABLE 标记，正常启动到音乐库，歌单「收藏」仍为 **146 首**。`release327-startup.*` 和 `release327-playlists.*` 保存启动与数量证据。按 `register-generated-program` 技能，在真实 release 启动成功后更新既有 LLMPET 本地入口，返回 `ok=true`、ID `55597a6477880f94`；仅登记当前项目的 ADB 启动命令，不发布或复制项目。

### 录屏检查

`analyze_recordings.py` 对 5–20 秒原始解码帧、排除顶端 overlay 和系统栏的歌词 ROI 检查：

| 指标 | 326 | 327 |
| --- | ---: | ---: |
| 解码比较帧 | 898 | 901 |
| 完全相同帧 | 0 | 0 |
| 平均灰度差 <.05 的帧 | 167 | 128 |
| 录制时间戳间隔 P95 / 最大，ms | 19.58 / 35.34 | 18.92 / 34.98 |

低差帧可能来自非运动段、少量字符微动、编码和实际卡顿；Android screenrecord 为约 59fps 的可变采样，**不能证明没有冻结、平滑抛物线帧差或 120fps 满帧**。样帧显示长英文折行和双语行没有新增缺字/重影，阿拉伯文/印地文仍整形；混合行家庭 emoji 的 Android 字体回退仍显示占位框，这是已知原有字体限制，未在本轮贸然替换字体或拆分连字。

原始证据根目录：`F:/AGENT/1/test-artifacts/karaoke-327/`：

- `baseline-326-comparable.json`、`updated-327-batched.json`：完整 profile 时间线和指标，即使预算失败仍保存；
- `baseline-326-comparable-profile.mp4`、`updated-327-batched-profile.mp4`：连续对照录屏；
- `baseline-326-persisted-arm64-profile.apk`、`updated-327-final-arm64-profile.apk`：仅用于测试，不能当成正常播放器正式安装包；
- `recording-analysis.json`、`analyze_recordings.py`、对应 5/8/12/18 秒样帧；
- `flutter-test.log`、`flutter-analyze.log`、`software-review/fixture_0.png` 至 `fixture_3.png`；
- `baseline-326-norecord-120-requested.json`、`baseline-norecord-display.txt`、`updated-norecord-display.txt`：刷新率请求与调度限制证据。

失效的早期 DDS/采集尝试没有计入上述对照。新增 `test_driver/karaoke_performance_driver.dart` 用 writeResponseOnFailure 保留预算失败的数据；fixture 同时将 JSON 写入 app private 临时目录（本设备为 code_cache），避免 OEM 隐藏 VM-service 端口日志导致证据丢失，不关闭 VM-service 认证。

## 构建、留档及回退

正式命令：

```powershell
flutter build apk --no-pub --release --target-platform android-arm64 --split-per-abi
```

- 正式 APK：`F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.327-arm64-v8a.apk`，53,297,722 字节。
- 原生 ABI 仅 `arm64-v8a`，versionCode=2327、versionName=0.9.9；16KiB zipalign 和 v2 签名校验通过，沿用项目现有签名。
- SHA-256：`DED2D0EA1EA22B4ED86373840FCA8FAD061A73DE2706205CA3814FEEE7F4EE5C`。
- 留档：`F:/临时文件夹/备份/Myune-Music-0.9.9+327-20260926-134953/`，完整当前脏工作区源码 tar.gz、正式 ARM64 APK、本记录、README 和本轮有效验证证据；排除 Git/编译缓存/build/dist 和本机 local.properties。
- 回退基线保存在 326 留档 `F:/临时文件夹/备份/Myune-Music-0.9.9+326-20260926-111240/`；仅在独立目录解压对照，不覆盖当前未提交工作区。Android 正式版降级受系统版本限制，不建议卸载清数据作为回退手段；没有数据格式迁移。

下一步应针对有效 profile 时间线中剩余 Raster/saveLayer 与挂载/预热 Build 尖峰继续定位，并使用真实同曲同段重复 A/B、稳定 120Hz 调度和长期内存/GPU 采集完成验收。现有数据不足以把所有剩余问题归因于同一个组件。
