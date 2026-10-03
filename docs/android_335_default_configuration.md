# 335：首次使用默认配置调整

2026-09-27。实际工作区为 0.9.9+334，更新 0.9.9+335 / 0.9.9-android.335。先查找适用 AGENTS.md（未发现），核对项目说明、334 记录、SettingsProvider、ThemeProvider、Android 设置控件与相关测试。保留现有未提交及未跟踪成果，不重置或覆盖无关文件。

## 默认配置

仅改变没有保存值时的默认配置，不在升级时强制覆盖用户选择。SettingsProvider 的构造字段与 SharedPreferences 缺省值同步修改；ThemeProvider 在异步加载前后都默认深色，已保存的 light / dark / system 仍按原选择恢复。

| 分类 | 默认值 |
| --- | --- |
| 歌词源 | 网络获取关闭；翻译关闭；自动回退关闭；首选网易 |
| 备用源 | QQ，与网易优先的现有回退顺序一致，不开启自动回退 |
| 歌词显示 | 左对齐，W800（FontWeight.values 的索引为 7），高亮歌词开启 |
| 逐字/动效 | 弹性滚动关闭；逐字关闭；范围为“仅适配”；行模糊关闭；外发光关闭 |
| 封面背景 | 应用到主界面关闭；应用到播放页开启；播放页样式为流体色彩 |
| 模糊封面预设 | 遮罩 30%，模糊 40；切换样式不重新赋值或覆盖已有调节值 |
| 自定义图片 | 主界面及播放页均默认关闭，遮罩各 20%，模糊各 0（关闭） |
| 个性化 | 深色模式；动态主题配色开启 |
| 播放 | 被占用自动暂停开启；优先外置 LRC 开启；忽略错误、音频分析、响度平衡、ReplayGain、无缝队列均关闭 |

“左侧侧边歌词”对应已有的 TextAlign.left；现有侧边安全内边距不变。“外置 lrcg”按当前界面的“优先读取外置 LRC 歌词”实现，优先读取同名 .lrc，不声称新增 .lrcg 文件格式解析。播放器已默认关闭独占模式，不改该开关；“其余全部 N”按本次播放设置范围理解，不将音量、倍率、自动音频设备或其他页面的开关一律归零。沉浸模式与睡眠计时播完本曲等已有可选开关保持默认关闭。

没有修改歌词动画、播放页布局、自定义背景绘制路径或新增用户设置。没有清空或迁移已有有效配置。未知/缺失背景样式及歌词对齐回退到本轮默认值，类型错误的设置项仍沿用原有安全读取机制。

## 验证

- 新 test/default_configuration_test.dart：空配置构造时及异步加载后全量核对；切换模糊封面再加载保持 30% / 40 预设；保存与新默认不同的值后检查实际恢复值以及持久化键没有被重写；部分/非法配置回退但保留有效键；默认深色且已有 light / system 不被覆盖。
- 修改前新测试 3 项失败、1 项已有配置保留通过，证据 defaults-before.log。修改后新测试 4 项通过。
- 调整原歌词显示、翻译、模糊封面默认断言，保留恢复、边界钳制及独立控制测试。开关持久化测试改为实际切换到非默认值，避免默认值相同时 setter 合法 no-op 导致检查空键。主题路由测试在新增默认展开的流体控件后滚动到下方图片卡片，继续验证独立页面与返回行为。
- 开发中的主题测试曾同时执行构造初始化与第二次 initialize，导致 fixture 过早 dispose；改为等待构造初始化完成，不修改生产初始化架构或掩盖异常。
- 最终相关测试 60 项通过。完整 flutter test --no-pub --reporter expanded：332 通过，1 项原有可选图像导出跳过。
- flutter analyze --no-pub：No issues found（11.2s）。10 个 Dart 文件格式检查 0 改动，git diff --check 通过（保留原有 CRLF 提示）。

本轮未安装或运行手机测试，未覆盖/卸载正式应用，也没有重置手机配置。无新增动画或绘制性能改动，不宣称性能提升。更新旧安装后已保存的设置不会自动变成这份默认表；新安装或此前未保存的项采用新默认。

## 文件与产物

生产代码：lib/page/setting/settings_provider.dart、lib/theme/theme_provider.dart。版本与说明：pubspec.yaml、lib/page/setting/project_changelog.dart、本记录。测试：新增 test/default_configuration_test.dart；调整 test/lyric_display_settings_test.dart、test/network_lyric_fallback_test.dart、test/custom_theme_background_test.dart、test/custom_theme_settings_section_test.dart、test/fluid_background_test.dart、test/project_changelog_test.dart。

证据：F:/AGENT/1/test-artifacts/defaults-335/。仅构建 Android ARM64 Release，不构建其他 ABI 或 Profile/Debug。Release 构建通过（Gradle 69.0s）。APK：F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.335-arm64-v8a.apk，32,549,334 字节（31.04MiB）。SHA256：88D2304F82B43DF161A50AD9569281236F197E8B396BFF524E048392A2E4CFF4。

versionCode 2335 / versionName 0.9.9，minSdk24 / target36，无 DEBUGGABLE，仅 arm64-v8a。v2 签名、zipalign 16KiB、APK CRC/ABI/原生库压缩与 ELF 对齐审计通过。未安装到手机。

留档：F:/临时文件夹/备份/Myune-Music-0.9.9+335-20260927-075756/，完整当前工作区源码含未跟踪成果、正式 APK、本记录及验证日志；排除 .git/.dart_tool/build/dist/.gradle/.cxx/target 等编译缓存及 local.properties。不删除或覆盖 334 及此前留档。源码包不包含手机私有配置、曲库或歌单，不用它宣称恢复手机数据。
