# 332：切歌封面同步、沉浸歌词与设置独立页面

2026-09-26。以实际工作区 331 为基线更新为 0.9.9+332（显示 0.9.9-android.332，Android versionCode 2332）。已阅读项目说明、近轮变更、相关源码与测试；未发现适用 AGENTS.md。保留已有大量未提交/未跟踪成果，不重置、不回退。只实现本轮三项需求，不修改逐字歌词算法、导入、音效或 Android 原生桌面歌词服务。

## 1. 切歌灰封面

查明旧 `_AtomicNowPlayingCover` 主要监听预准备信号，却依赖父组件捕获的 fallback 字节；实际歌曲封面异步到达不一定更新该快照。同时待准备的 ArtworkImage 使用渐进 Stack，准备完成后切成 Image，替换渲染节点，gaplessPlayback 无法跨不同节点保留已解码帧。这与“点一下才恢复”的现象吻合；本轮有限的旧版暖缓存真机对照未稳定复现该现象，不能声称取得可重复的灰封面 A/B 实测。

- 新 NowPlayingCoverImage 直接监听当前歌封面、预准备和解码恢复信号，每次读取最新有效来源，不依赖点击/父组件重建。
- 全分辨率图准备前后保留同一个 Image 元素，让 gaplessPlayback 真正生效；快速 A→B→C 切换时，迟到 B 不得覆盖 C。
- 保留已有 220ms 有界旧封面交接，当前歌实时字节优先；确定无封面的歌曲立即清除，不长期借用上曲封面。
- 已准备图片受歌曲路径、缓存代次和实时字节身份校验，避免应用自定义封面后继续用旧准备图。
- 解码失败只在帧后报告**实际失败 provider 的字节**，不误伤随后更新的封面；恢复仍走原有数据源机制。

## 2. 沉浸模式

- 播放页顶部，歌曲详情前新增全屏图标开关；默认关闭，使用 SettingsProvider 持久化，跨切歌/重新进入页面保留选择。
- 开启且处于歌词视图时隐藏标题、返回按钮、播放控制和底部功能区，歌词扩展到应用 SafeArea。点击歌词使用原有手势返回封面，所有控件淡入回原位置。
- NowPlayingImmersiveLayout 独立管理 280ms easeInOutCubic 淡入/收拢；仅维护一个 visual 元素，不复制歌词树或再次挂载 Hero；快速往返可逆。
- 隐藏的按钮不接收点击，也不暴露无效语义。手机纵向、平板纵向/分栏保留原有控件包裹、间距和 6:5 比例。
- 没有接管系统全屏模式：Android 状态栏/导航栏仍在。这里“仅显示歌词”指应用内容区，未变更全应用系统栏策略。

## 3. 主题配置 / 桌面歌词

- 两项改名为“主题配置”“桌面歌词”，从原位进入独立 MaterialPageRoute，不再使用 ExpansionTile 向下展开。
- 主题配置保留全部封面跟随、主界面/播放页图片、历史选择、编辑及模糊/暗度控制。启用且文件存在时，页面显示主界面的自定义图片背景；未启用则保留正常主题背景。
- 桌面歌词路由使用完全不透明的主题 surface（AppBar 同色），不加载自定义图片；“纯色”随浅/深主题变化，并非写死某个颜色。
- 样式预览放在 Column 顶部，只有下面的控制区 ListView 滚动，颜色、字号、粗细、透明度与描边继续实时同步。保留权限申请、锁定和恢复默认功能。

## 验证

- 完整 flutter test --no-pub --reporter expanded：**321 项通过，1 项原有可选导出测试跳过**。本轮新增 8 项有意义测试，原主题展开测试迁移为页面导航测试；版本记录断言更新为 332。
- 封面测试使用真实 ui.Image/RawImage 帧，覆盖异步到达无需点击、父组件不重建、保留旧帧、迟到结果与无封面清空，而非只断言某个布尔值。
- 沉浸测试覆盖设置默认/持久化、手机/分栏实际几何、过渡中间透明度、同一个 visual Element、禁用隐藏按钮、返回后原矩形和快速反向切换。
- 设置测试覆盖真实 push/pop、纯色不透明、启用自定义图片背景、预览滚动固定及字号 38/描边变更。另导出实际字体与图标的桌面页 Widget 截图人工检查；主题页可选测试截图导出曾超时，旧导出不作为验收证据，使用后续真机主题页截图。
- flutter analyze --no-pub：**No issues found（最终复查 8.2s）**；git diff --check 通过（仅原有 CRLF 提示）；APK 审计工具 6 项测试通过。
- 与 331 完整源码留档逐文件 SHA256 比对：已有文件仅变动本轮列出的 8 个文件；其他已有成果保持不变。另新增 5 个 Dart 文件与本记录。

### 真机（实际 Release，不是 Profile）

Vivo V2352A，ADB 10CEB70TQE001E2；screenrecord 720×1600、6Mbps。初期设备未连接，后重新连接，执行 adb install -r 成功并启动 MainActivity，保存曲库/设置，不卸载或清除数据。

- 同队列对照：331 与 332 的“前前前世 (movie ver.) → 情歌 → 秦皇岛”切歌留有连续录屏和截图；332 封面自行显示，无需点击恢复。旧版本次暖缓存对照未稳定出现灰封面，未假装已取得可复现性能/故障率对照。
- 332 开启沉浸进入歌词，应用顶部/底部控件消失，点击返回封面恢复；专门录制 18 秒带时间日志的往返，检查关键连续帧及手机截图。两次较早的录屏只覆盖进入过程，不能冒充退出验证，以 immersive-roundtrip-verified332.mp4 为往返证据。
- 主题配置进入新页，控件完整；设备原有主界面自定义图片未启用，未为了截图更改用户主题。启用自定义图片背景的路径由 Widget 测试覆盖，尚未在该机启用图片实测。
- 桌面歌词实际使用用户原有 32px/描边样式，纯色背景；滚动前后预览语义矩形均 [135,342][945,564]。没有重置或改动用户桌面歌词样式。
- 测试结束恢复原歌曲“前前前世 (movie ver.)”、暂停状态与沉浸关闭，播放位置约 0:50。
- 没有本轮 Profile/Perfetto 帧耗时数据或 120Hz 设备对照；screenrecord 编码约 60fps **不代表应用实际每帧耗时达标**，不宣称零掉帧或性能提升。平板几何由自动测试覆盖，未用真平板验证。

## 构建与留档

只构建 **ARM64 Release**：tool/build_android_release.ps1，继续保留 331 的原生库压缩与完整多语言字体。构建成功，签名 v2 验证、zipalign -c -P 16 4、APK CRC/ABI/ELF 审计通过。versionName=0.9.9、versionCode=2332、无 DEBUGGABLE；7 个库只有 arm64-v8a，全部 DEFLATE，LOAD 对齐至少 16KiB。不以这些检查替代 16KiB 页设备实测。

正式包：F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.332-arm64-v8a.apk

大小：32,546,994 字节，32.55MB / 31.04MiB（比 331 增加 14,640 字节，正常代码和图标变化）。完整 MiSansVF 与 6 个非应用原生库不变。

SHA256：1AFC97C469A1455C9C6C381FBE5A30A3F4EF017AFCD13254FE2CE7C023EC3325

验证目录：F:/AGENT/1/test-artifacts/ui-332/。主要证据：flutter-test-delivery.log、flutter-analyze-delivery-final.log、apk-audit.json、signature.log、build-release.log；baseline331-cover.mp4、new332-cover-immersive.mp4、immersive-roundtrip-verified332.mp4、roundtrip-events.log；theme332.png、desktop332.png、desktop-scrolled332.png、immersive332.png、return332.png。

完整留档：F:/临时文件夹/备份/Myune-Music-0.9.9+332-20260926-201500/。包含 source-0.9.9+332.tar.gz（当前全部源码，包含未跟踪成果）、正式 APK、本记录与有效验证证据；排除 .git/.dart_tool/build/dist/release/编译缓存/__pycache__/local.properties，不覆盖 331。未将其他播放器截图和失败的可选导出当作有效验收证据。

按 register-generated-program 技能，在实际安装/启动确认后更新原有本地入口 55597a6477880f94；处理命令路径斜杠差异生成的本轮重复入口，仅撤销该临时快捷索引，不移除旧入口或任何项目文件。

修改文件：lib/mobile/mobile_shell.dart；lib/page/setting/settings_provider.dart；lib/page/setting/tabs/custom_theme_settings_section.dart；lib/page/setting/tabs/playback_page_tab.dart；pubspec.yaml；lib/page/setting/project_changelog.dart；test/project_changelog_test.dart；test/custom_theme_settings_section_test.dart。

新增：lib/widgets/now_playing_cover_image.dart；lib/widgets/now_playing_immersive_layout.dart；test/now_playing_cover_image_test.dart；test/now_playing_immersive_layout_test.dart；test/settings_detail_pages_test.dart；本记录。

回退对照：可在独立目录解开 331 源码和使用原留档 APK，不通过 git reset 回退脏工作区；Android 降版本安装可能被拒绝，不建议卸载清库。
