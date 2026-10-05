# Android 354：桌面歌词锁定点击穿透兼容

日期：2026-10-04。版本：`1.0.0-android.354`。

## 原因

原生桌面歌词已在锁定时设置 `FLAG_NOT_TOUCHABLE`，但没有设置 `WindowManager.LayoutParams.alpha`，窗口级透明度一直是默认的 1.0。歌词控件的 `alpha`、背景透明像素及淡出动画的根 View `alpha` 都不等价于窗口级透明度。

Android 12 开始，对不可触摸的 `TYPE_APPLICATION_OVERLAY` 窗口检查点击遮挡透明度。单个同 UID 悬浮窗的窗口 alpha 必须小于或等于系统最大遮挡透明度，默认 0.8；超过后系统会丢弃穿过窗口矩形区域的点击。这是代码层面可确认的缺陷，与 Android 版本及 ROM 执行规则差异一致；没有本轮受影响机型日志，不能声称已确认每个机型的具体原因。

依据：[Android WindowManager.LayoutParams 官方说明](https://developer.android.com/reference/android/view/WindowManager.LayoutParams#FLAG_NOT_TOUCHABLE)、[Android 12 不受信任触摸拦截说明](https://developer.android.com/about/versions/12/behavior-changes-all#untrusted-touch-events)。

## 修复

- 新增 `DesktopLyricsTouchPolicy`，集中计算不可触摸标志和窗口 alpha。
- Android 12+ 读取 `InputManager.maximumObscuringOpacityForTouch`，采用不高于系统值及 0.8 的上限；服务不可用时回退到官方默认值。Android 11 及以下保留原有窗口 alpha 1.0。
- 锁定、应用前台抑制及关闭淡出期间同时应用安全透明度与不可触摸标志，避免只修改标志留下不受信任遮挡窗口。
- 所有窗口挂载和更新前同步应用策略，解锁且正常显示时恢复窗口 alpha 1.0 和交互标志。
- 歌词 payload 直接恢复锁定状态时也收起控制栏，避免残留不可点击的按钮。
- 版本递增至 `1.0.0+354`；更新应用日志和版本测试。

没有绕过或关闭系统触摸安全规则，也没有添加权限或无障碍服务。只有一个桌面歌词悬浮窗；若将来新增同 UID 重叠窗口，必须重新计算组合遮挡透明度。

## 视觉与验证限制

Android 12+ 锁定状态下，最终歌词不透明度是用户设置值乘以窗口安全 alpha（通常 0.8）；解锁恢复原亮度。窗口级限制不能通过增大文字 alpha 补偿至完全不透明。下层应用自行拒绝被遮挡触摸或要求隐藏悬浮窗时，其安全行为仍优先。

ADB 当前无已连接设备，本轮没有真机点击或多 ROM 实测。新增原生回归测试覆盖 Android 24–36、严格系统上限、锁定/解锁、前后台抑制与恢复、关闭淡出和异常上限。

## 产物与留档

- ARM64 Release：`dist/Myune-Music-1.0.0-android.354-arm64-v8a.apk`
- 源码留档：`dist/Myune-Music-1.0.0-android.354-source-20261004.zip`
- 版本备份：`F:/临时文件夹/备份/Myune-Music-1.0.0+354-20261004/`

## 检查结果

- `:app:testReleaseUnitTest --tests com.myune.music.DesktopLyricsTouchPolicyTest -Ptarget-platform=android-arm64`：5 项通过，无失败或跳过。
- `flutter test --no-pub test/app_version_test.dart test/project_changelog_test.dart`：9 项通过。
- `flutter analyze --no-pub`：无问题。
- `git diff --check`：通过。

本项目存在 Groovy/Kotlin 两份 app Gradle 文件，实际生效的是 `android/app/build.gradle`；测试依赖仅添加到该文件的 `testImplementation`，不会打入发布包。

- `tool/build_android_release.ps1`：ARM64 Release 构建成功，仅含 `arm64-v8a`。
- APK 包名 `com.myune.music`，`versionName=1.0.0`，分 ABI `versionCode=2354`。
- 原生库压缩与 ELF/ABI 检查通过；APK v2 签名验证及 16 KB ZIP 对齐通过。
- 安装包大小：32,304,416 bytes（30.81 MiB）。
- SHA-256：`7082A5C150BBF8010651C14A3DE32F4DDBA3449BE82C3089BE7B134ED85A91AA`。
- 原生测试 XML 和 APK 审计 JSON：`F:/AGENT/1/test-artifacts/desktop-lyrics-354/`。
