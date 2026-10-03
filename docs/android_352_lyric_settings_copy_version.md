# Android 1.0.0（352）：精简歌词设置说明

日期：2026-10-03。基于当前 351 工作区升版为 `1.0.0+352`；Android 显示版本为 `1.0.0-android.352`。保留原有未提交文件，不重置或覆盖其他修改。本轮遵照要求，未进行真机测试。

## 修改

根据用户标注，移除歌词设置中三处解释性副标题：

- “歌词滚动效果”下方的默认、动感、弹性模式说明。
- “逐字歌词”下方的高亮动画说明。
- “逐字歌词范围”下方的仅适配范围说明。

保留三个标题、滚动模式按钮、逐字开关和范围选项；不改变歌词行为或设置默认值。

`pubspec.yaml` 升为 `1.0.0+352`，应用内更新记录和版本测试同步更新。ARM64 Release 命名沿用项目格式：`Myune-Music-1.0.0-android.352-arm64-v8a.apk`。

## 验证

- `test/app_version_test.dart` 与 `test/project_changelog_test.dart`：8 项通过。
- `flutter analyze --no-pub`：无问题。
- 构建仅使用 `android-arm64 --split-per-abi`；本轮没有连接、安装或操作手机。

## 文件与留档

- `lib/mobile/mobile_shell.dart`：移除三条副标题。
- `pubspec.yaml`：主版本号 1.0.0，构建号 352。
- `lib/page/setting/project_changelog.dart`、`test/app_version_test.dart`、`test/project_changelog_test.dart`：同步更新版本记录及验证。
- ARM64 APK：`dist/Myune-Music-1.0.0-android.352-arm64-v8a.apk`。
- 源码包：`dist/Myune-Music-1.0.0-android.352-source-20261003.zip`。
- 版本备份：`F:/临时文件夹/备份/Myune-Music-1.0.0+352-20261003/`。

此前 351 及工作区其他成果均保留；此记录和版本源码包包括当前未提交与未跟踪源码，但不包含本地构建缓存、APK 或私钥。
