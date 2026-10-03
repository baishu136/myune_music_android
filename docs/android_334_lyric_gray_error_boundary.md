# 334：首句边界越界导致的歌词灰块修复

2026-09-27。以实际工作区 0.9.9+333 为基线，更新至 0.9.9+334 / 0.9.9-android.334。查找适用 AGENTS.md（未发现），阅读 README、330/333 逐字记录、播放器歌词索引逻辑、歌词列表、相位组件、间奏生命周期及相关测试。保留已有未提交和未跟踪成果，不重置，不修改无关功能。

## 根因与修复依据

播放器 PlaylistContentNotifier.updateLyricLine 的二分查找在首个时间戳之前合法返回 -1。列表原有 build 会把此值钳制到首行供预览，但 didUpdateWidget 的正常换行退出条件只有 `newActive == oldActive + 1`，因此 -1 → 0 被误认为存在上一行，并执行 `widget.lines[-1].isInterlude`。

新增回归在修复前明确捕获 RangeError，栈定位 mobile_lyrics_list.dart:1088。此异常发生在父组件更新子树期间，Flutter 用 ErrorWidget 替换受影响子树；本机 Flutter RenderErrorBox 在非 Debug 模式使用 0xF0C0C0C0 背景，播放页 ClipRRect 将其裁成大面积圆角灰块。这与用户截图及 330 记录中的偶发灰块相符，不是正常景深、浏览遮罩或扫光背景。

**已确认并修复这一可复现故障路径；没有手机异常日志，不能断言截图中的所有灰块必定只有这一原因。** 没有通过透明 ErrorWidget、吞掉异常或移除模糊遮掩问题。

mobile_lyrics_list.dart 仅增加正常退出的索引有效性条件：上一行和当前行必须都在当前歌词范围内，才允许正常退出并读取上一行。-1 是无当前行状态，不作为退出行。实际 0 → 1 的间奏/正文接力、240ms 圆点退出、420–480ms 统一换行、逐字时钟和高亮语义均保留。mobile_shell.dart 不需要改动。

## 验证

- 新 test/lyric_index_boundary_test.dart，四种组合：普通/逐字模式 × 首行正文/间奏。保留同一个歌词列表对象，按 -1 → 0 → 1 → -1 → 0 → 1 反复跨首句边界；启用边缘 ShaderMask、景深与播放页同类圆角裁切；每次切换及后续 32 个约 60Hz 帧检查无异常、无 ErrorWidget、目标行仍挂载。验证生命周期而非只断言某个固定参数。
- 修复前 boundary-before.log 失败，明确 -1 越界；后续测试受到首次异常破坏的子树影响，产生连带框架异常，不作为独立根因。
- 修复后边界、相位和间奏专项合计 17 项通过。
- 完整 flutter test --no-pub --reporter expanded：328 通过，1 项原有可选图像导出跳过。
- flutter analyze --no-pub：No issues found（85.9s）。格式检查及 git diff --check 通过；原有 LF/CRLF 提示不改变。
- APK 审计工具的 6 项 Python 单元测试通过。

## 真机与性能限制

本轮 adb devices 无可用设备，未读取到手机 logcat，未安装或运行真机测试；没有操作正式包、卸载、清除数据或重新导入曲库。遵守 333 事故后的测试隔离要求，不运行正式 applicationId 上的 flutter drive。

此修复只在组件更新边界增加整数范围检查，没有新增每帧排版、绘制或动画分配。软件回归通过不等于真机观感或 60/120fps 验收，没有本轮性能实测数据，不宣称帧率提升。

## 修改范围与留档

修改 lib/widgets/mobile_lyrics_list.dart、pubspec.yaml、lib/page/setting/project_changelog.dart、test/project_changelog_test.dart；新增 test/lyric_index_boundary_test.dart 和本记录。已有全部未提交修改保留。

验证证据：F:/AGENT/1/test-artifacts/lyrics-334/。仅构建 ARM64 Release，沿用项目版本、ABI、原生库压缩和命名约定。不构建 Profile/Debug 或其他 ABI。

Release 构建通过（Gradle 264.7s）。APK：F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.334-arm64-v8a.apk，32,549,290 字节（31.04MiB），SHA256：0E49D60754C24F1B63907FEC15DFC08CB7473ADD0D799361A296AF9FE402710E。versionCode 2334 / versionName 0.9.9，minSdk24 / target36，无 DEBUGGABLE，仅 arm64-v8a。v2 签名、zipalign 16KiB 校验、APK CRC/ABI/原生库压缩与 ELF 对齐审计均通过。没有安装到手机。

留档：F:/临时文件夹/备份/Myune-Music-0.9.9+334-20260927-073034/，包含完整当前工作区源码（含未跟踪成果）、正式 APK、本记录和验证日志；排除 .git/.dart_tool/build/dist/.gradle/.cxx/target 等编译缓存及 local.properties。保留此前留档。源码留档不包含手机私有数据；不用于宣称恢复手机曲库。回退或对照请在独立目录解开 333 留档，不重置当前脏工作区，不卸载正式应用绕过降级限制。
