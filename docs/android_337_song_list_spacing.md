# 337：缩小普通歌曲列表的行间距

2026-10-01。实际工作区版本 0.9.9+336，本轮更新 0.9.9+337 / 0.9.9-android.337。查找适用 AGENTS.md（未发现），核对 README、336 变更、截图对应的移动端音乐库列表、封面预取与现有测试。保留大量未提交和未跟踪成果，不重置、不覆盖无关修改。

## 实际问题与修改

截图圈出的空隙来自普通歌曲列表的 ListTile，而不是在相邻歌曲之间单独插入的分隔组件。48dp 的封面与两行文字处于实测 78dp 行高之中，导致相邻封面间约 30dp 的视觉空隙。

在 lib/mobile/mobile_shell.dart 中将普通歌曲列表专用的行布局抽为可直接测试的 buildMobileSongListTile；将最小行高、文字垂直内边距与封面周边留白一起收紧。Flutter 实际布局测试在默认字号下测得新行高 56dp，相邻 48dp 封面之间留 8dp。48dp 操作区仍可点击；文字缩放增大时 ListTile 允许自然扩高而不是裁切。同步将手机与窄屏平板列表的封面预取行高估算从 72dp 更新到 56dp，避免使用明显偏大的旧估算值。

同一个普通列表组件也服务于复用它的歌单/合集列表，因此这些普通行一并收紧。索引网格、平板网格和歌单分栏 compact 样式的 ListTile 参数保持原样；歌曲数据、排序、封面解码及播放动作不变。

## 验证与限制

- 新 test/mobile_song_list_density_test.dart：修复前默认行高 78dp，预期 56dp 明确失败。修复后验证连续行位置、48dp 封面、8dp 封面间隙、至少 48dp 点击区域和点击回调；较大系统文字比例无布局异常；网格和分栏仍保留其原 ListTile 规则。
- 相关 14 项测试通过，包含列表进场、预取规划及版本记录。
- 完整 flutter test --no-pub --reporter expanded：336 通过、1 项原有可选图像导出跳过。flutter analyze --no-pub：No issues found（15.6s）。Dart 格式与 git diff --check 通过（原有换行符提示保留）。
- 本轮未向持有用户曲库数据的正式 applicationId 安装测试包，未清理或修改手机数据；没有本轮真机视觉/帧耗时对照。组件布局测试确认尺寸，不能替代实际设备观感与性能测量。较大系统文字比例下，封面预取行高仍是估算值，列表本身会随文字自然增高。

## 文件与产物

修改 lib/mobile/mobile_shell.dart、pubspec.yaml、lib/page/setting/project_changelog.dart、test/project_changelog_test.dart；新增 test/mobile_song_list_density_test.dart 与本记录。仅构建 ARM64 Release，不构建 Profile/Debug 或其他 ABI。验证证据：F:/AGENT/1/test-artifacts/song-spacing-337/。

Release 构建通过（Gradle 74.3s）。APK：F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.337-arm64-v8a.apk，32,547,994 字节（31.04MiB）。SHA256：595C4B622AC1B09986D660DD167D4F4BF8F376B749E01E936A6BEE332AA8CB84。versionCode 2337 / versionName 0.9.9，minSdk24 / target36，无 DEBUGGABLE，仅 arm64-v8a。v2 签名、zipalign 16KiB、APK CRC/ABI/原生库压缩与 ELF 对齐审计通过。未安装到手机。

留档：F:/临时文件夹/备份/Myune-Music-0.9.9+337-20261001-203342/，包含完整当前工作区源码（含未跟踪成果）、正式 APK、本记录及验证日志；排除 .git/.dart_tool/build/dist/.gradle/.cxx/target 等编译缓存和 local.properties。保留此前版本留档；源码包不包含手机私有曲库和设置。
