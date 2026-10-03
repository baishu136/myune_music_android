# Android 250：播放页流体色彩背景实施与验收记录

日期：2026-09-10  
版本：`0.9.9+250`

## 完成范围

- 保留原有“模糊封面”作为默认值；在“设置 → 个性化 → 播放页背景样式”新增可选“流体色彩”。
- 提供自动、节能、流畅三个质量档位，目标刷新率分别为 30、24、60 Hz；只驱动背景 `CustomPainter` 重绘，不触发前景组件逐帧重建。
- 使用单遍 Flutter runtime fragment shader 绘制四组柔和色块；shader 未加载、编译失败或系统开启减少动态效果时立即使用静态渐变，不显示空白帧。
- 封面色板优先从已缓存缩略图异步提取，使用最多 64 项 LRU 缓存、进行中请求合并、封面代次与内容指纹键，防止快速切歌的旧结果覆盖新背景。
- 色板切换从当前显示状态开始，900 ms 平滑过渡；播放暂停时 200 ms 内减速并停止，不维持空闲帧循环。
- 进入/返回播放页、页面被弹窗覆盖、应用退至后台、`TickerMode` 不可见、系统减少动态效果开启时停止 shader 调度；恢复后从原相位继续。
- 流体模式不使用全屏 `BackdropFilter`，播放页面板与弹出层改为半透明实色；旧模糊模式保持既有视觉参数。旧模式面板模糊延后到路由结束后的空闲帧恢复，降低进入首帧的 raster 压力。
- 修正调试帧监视器：分别记录 build/raster 的 P95、最大值和超预算帧，不再把总跨度误判为渲染卡顿。

## 主要实现文件

- `lib/models/fluid_background_state.dart`：背景样式、质量档位、固定四槽色板与档位参数。
- `lib/services/artwork_palette_cache.dart`：色板提取、过滤、稳定排序、LRU 和并发合并。
- `lib/services/fluid_background_controller.dart`：单 ticker、相位、色板过渡、状态暂停与刷新节流。
- `lib/widgets/playback_background/`：背景选择器、流体组件与 painter。
- `shaders/fluid_background.frag`：单遍 runtime shader。
- `lib/mobile/mobile_shell.dart`：播放页接入、缩略图取色、路由状态和玻璃层延后。
- `lib/page/setting/settings_provider.dart`、`lib/page/setting/tabs/custom_theme_settings_section.dart`：设置、持久化和未知值安全回退。
- `test/fluid_background_test.dart`：迁移、色板、缓存键、控制器停止条件及静态首帧覆盖。

## 已完成验证

- `flutter analyze --no-pub`：通过，0 个问题。
- `flutter test --no-pub --reporter compact`：通过，186 项测试全部成功。
- arm64 release 构建通过，runtime shader 已打入 APK；`aapt` 核验包名为 `com.myune.music`、`versionCode=2250`、`versionName=0.9.9`、唯一 native ABI 为 `arm64-v8a`。
- `apksigner` 核验 v2 签名有效。当前项目仍沿用本地可安装的 Android debug 证书，不应直接作为商店正式签名。
- 设置缺失或存在未知枚举值时回退到旧“模糊封面”模式，升级不会自动改变用户外观。
- 流体模式在 shader 准备前同步绘制静态首帧；路由动画期间不启动 shader 或色板解析。

构建产物：`F:\AGENT\1\myune_music_android\dist\Myune-Music-0.9.9-android.250-arm64-v8a.apk`  
APK SHA-256：`4FEFF44D467E7E4A32A850C8EA039D148ED5B31AF82BD1A762498264B7D674F4`

源码与 APK 留档：`F:\临时文件夹\备份\Myune-Music-0.9.9+250-20260910-091935\`  

## 性能基线与本轮限制

2026-09-09 在 vivo V2352A（Android 15，约 60 Hz）保存的原始 A/B 基线：

| 场景 | 进入 raster P95 | raster 最大值 | 超 16.67 ms |
| --- | ---: | ---: | ---: |
| 原效果 | 18.91 ms | 26.32 ms | 10 / 93 |
| 仅关闭面板毛玻璃 | 12.52 ms | 15.45 ms | 0 / 94 |
| 同时关闭背景和面板模糊 | 10.55 ms | 13.09 ms | 0 / 94 |

原始数据与复测说明保留于 `F:\AGENT\1\test-artifacts\entry-jank-20260909\`。本轮执行时 `adb devices -l` 没有连接设备，因此这些数据仅作为既有基线，不能当作 250 流体模式的真机验收结果。需要在真机上补测冷/热进入、返回、切歌、歌词滚动、前后台切换，以及至少 10 分钟的温度、内存和帧耗时；在完成前流体模式保持非默认。

## 回滚方式

用户可在“播放页背景样式”选择“模糊封面”，立即回到旧路径。代码级回滚可删除 `shaders/fluid_background.frag`、`lib/widgets/playback_background/`、流体模型与两个服务，并把播放页背景调用恢复为 `CustomThemeBackground`；设置读取器对缺失值已有旧模式回退，不需要清除用户数据。
