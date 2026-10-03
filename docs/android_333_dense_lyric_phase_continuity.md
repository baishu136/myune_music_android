# 333：快速换行的属性接续修复及真机测试事故

2026-09-26。实际工作区为 332，不假定仍为 328/329。先阅读项目说明、适用 AGENTS.md 查找结果（未发现）、330/332 记录、归一化模型、歌词组件、时钟和测试；保留全部已有未提交/未跟踪成果。版本更新 0.9.9+333 / 0.9.9-android.333，Android versionCode 2333。

## 现状核对与实际修改

332 已包含 330 的零初速微缓入解析曲线，而非旧 500ms 纯三次缓出。420ms 墙钟时长；峰速在 60ms；380ms 约 99.78%；终点精确归零。≤70px 行程 420ms，70–140px 线性增加至 480ms，更远仍 480ms 上限。当前/上一行缩放、透明度、文字样式、焦点景深已使用滚动模型同一 duration/curve；非焦点静态滤镜保护保留。间奏 240ms 退出与正文滚动同边界启动，正文落在既有 40% 阅读锚点，不提前修改歌词高亮时间。

本轮查明的是**快速连续换行时换曲线的瞬跳**。本机 Flutter ImplicitlyAnimatedWidgetState.didUpdateWidget 先替换 CurvedAnimation，再用新曲线采样旧 tween 起点；还在运动的属性会在没有时间推进的情况下改变显示值。新回归测试在修改前明确失败：上一行 alpha 从 0.9239009733 跳至 0.8961027854。不是依靠参数断言推断问题。

- 新 lib/widgets/lyric_phase_transition.dart：LyricPhaseRetarget 在换 curve/duration 前按**旧 animation**保存显示值，再从此值开始新段。仍在运动但目标未变的属性也按新段接续，避免旧缩放尾段滞后于已重定向的列表。仅更新边界采样，不在每帧增加此逻辑。
- LyricPhaseScale / Opacity / TextStyle 保留 Flutter ScaleTransition / FadeTransition 与固定子树，保留字体排版参数、透明度语义、滤镜参数等，不叠加额外位移、缩放或发光。
- mobile_lyrics_list.dart 使用这些局部组件，并让交接景深采用相同接续逻辑。preservePhase 只在逐字模式开启；普通歌词原有规则不变。远处非焦点模糊仍复用静态缓存，不恢复多行逐帧 GPU 模糊。
- seek 的零时长即使目标未变也立即收束，不留下原动画尾段。
- 保留 lyric_normalized_motion.dart 的既有正确曲线、同向速度接续和距离自适应，不为重复需求再添加第二套算法；不修改播放器、真实高亮时间、字素布局、间奏退出或 332 的新页面功能。

## 软件验证

- 完整 flutter test --no-pub --reporter expanded：**324 通过，1 项原有可选导出跳过**。
- 新增 3 项测试：实际列表 80ms 内再次换行，位移、1–3 行 scale/alpha 和交接行缓存 blur 在零时间边界不跳变；60/90/120Hz 实际采样逐帧比较各属性新段相位（包括仍在运动但目标未变的缩放）；seek 立即终止同目标旧尾段。
- 现有测试仍覆盖 60/90/120Hz 位移/速度、420/480ms 终点、折行、间奏接力、刚性行距、高亮/媒体时钟与缓存。原断言仅改查找方式以兼容 AnimatedScale/DefaultTextStyle 子类，未削弱容差或删除验证。
- flutter analyze --no-pub：No issues found（最终 13.2s）；7 个修改 Dart 文件格式检查 0 改动；git diff --check 通过（原有 CRLF 警告）。开发中测试工具的 Color 类型及浮点比较问题已修正，完整回归通过。

## 真机测试事故与限制（重要）

设备 Vivo V2352A / ADB 10CEB70TQE001E2。运行 ARM64 Profile 的真实 MobileLyricsList fixture（无音频、Performance Overlay、2s 间奏与混合歌词交替）。严格帧预算断言**失败**，见 profile-drive.log。不能宣布满帧、零掉帧或性能提升。首次生成的 JSON 被随后失败的 run-as 读取重定向覆盖为错误文字，不作为数值证据，不能凭 Performance Overlay 截图提供完整 P95/最大值表。

**该次 flutter drive 未设置 --keep-app-running。** 本机 Flutter DriverService.stop 会在测试结束后 stopApp 并 uninstallApp，而非仅停止进程；测试与正式应用共用 com.myune.music，导致正式包及应用私有曲库/歌单/设置被删除。这是不在用户授权范围内的误操作，不是用户要求清库，也不是本轮源码修复所需步骤。已即时向用户说明并承担责任，未隐瞒为“保留数据覆盖安装”。

随后重新安装正式 333 APK 成功并启动，实际显示初始空曲库及首次通知权限提示；bmgr list sets 返回 No restore sets，尚无可用系统恢复集。已停止继续写入手机数据，不自动扫描歌曲、导入文件或重建收藏，以免混淆“重建”和“恢复”。等待用户提供歌单导出/应用备份/系统备份的位置及类型。重新安装不等于恢复私有数据。测试脚本没有删除共享歌曲源文件，但尚未逐文件核验其状态，不能保证全部数据可恢复。

此前真实歌曲录屏准备阶段曲目被外部操作改变，baseline332-real-zenzen-release.mp4 名称不准确、没有严格同曲同状态对齐；不得将该视频冒称《前前前世》有效 A/B 对照。事故后不继续真实曲库录制，新版真实歌曲观感对照未完成。

后续安全要求：不得在持有用户数据的正式 applicationId 上直接执行会自动卸载的 flutter drive。优先独立测试 applicationId/备用设备；否则必须先验证数据备份、明确 --keep-app-running 并检查安装失败回退路径（也可能卸载），不要只依赖“停止应用”的命令说明。没有完成恢复与新的安全验证前，不重跑该流程。

## 交付与留档

正式 ARM64 Release 构建通过（79.9s）；安装并真实启动通过，但原用户数据未恢复。v2 签名、zipalign -c -P 16 4、APK CRC/ABI/ELF 审计通过；minSdk24 / target36，无 DEBUGGABLE，只有 arm64-v8a，沿用 331 原生库压缩。

APK：F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.333-arm64-v8a.apk

大小 32,549,214 字节（31.04MiB）。SHA256：2B73A2CCE8898764D1845E3BDE5EDC3E26D7EE193C4DF4735D275202D674E5A8。

证据：F:/AGENT/1/test-artifacts/karaoke-333/。有效软件/构建证据：phase-before.log、flutter-test.log、analyze-final.log、release-build.log、signature.log、apk-audit.json。真机事故证据：profile-drive.log、profile-check.png、data-status333.xml/png、install-status.png。失败/未对齐录制另标为诊断材料，不当成有效视觉验收。

留档：F:/临时文件夹/备份/Myune-Music-0.9.9+333-20260926-204000/，完整当前源码（含未跟踪成果）、正式包、本记录及诊断/验证材料。排除 .git/.dart_tool/编译目录和 local.properties，保留 332 留档。**源码留档不包含、不能恢复手机私有曲库或设置。**

修改：lib/widgets/mobile_lyrics_list.dart；test/lyric_phase_motion_test.dart；test/mobile_lyrics_list_test.dart；pubspec.yaml；lib/page/setting/project_changelog.dart；test/project_changelog_test.dart。新增：lib/widgets/lyric_phase_transition.dart；test/lyric_phase_transition_test.dart；本记录。

源码回退/对照可在独立目录解开 332，不重置脏工作区；安装旧 APK 也无法恢复已丢失私有数据，不以卸载绕过降级校验。
