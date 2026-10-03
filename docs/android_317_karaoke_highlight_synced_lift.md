# 317：逐字歌词上浮与高亮同步

## 修改

- 取消 315/316 的跨字符、跨词元连续接力与提前上浮。
- 每个字母或文字只读取自身的高亮进度：开始高亮时开始上浮，高亮完成时上浮完成。
- 保留 smootherstep 位移曲线与 9% 最终上浮高度，使起止速度柔和且时间边界与高亮严格一致。
- 单字、短词与中文字符使用同一套自身高亮驱动逻辑，不会被前一个字符提前带起。

## 保留行为

- 保留 316 的歌词行跳转预热与排版缓存，避免跳转目标行时集中塑形造成卡顿。
- 翻译行继续保持静态未播放样式，不参与逐字高亮、上浮或高亮外发光。
- 手动浏览整行候选高亮、普通歌词模式及其他播放页功能不变。

## 验证

- 专项测试：`flutter test test/mobile_lyrics_list_test.dart test/project_changelog_test.dart`，74 项全部通过。
- 完整测试：`flutter test`，236 项全部通过。
- 静态分析：`flutter analyze lib/widgets/mobile_lyrics_list.dart lib/page/setting/project_changelog.dart test/mobile_lyrics_list_test.dart test/project_changelog_test.dart`，无问题。
- 仅执行 `android-arm64` 的 split-per-ABI release 构建；APK 只包含 `arm64-v8a`。
- APK 元数据：`versionCode=2317`，`versionName=0.9.9`；通过 16 KiB zipalign 校验及 Android v2 签名校验。
- APK SHA-256：`7F946BBE22123D2932EDCB8A835BBB92AB8E463949D2365C690A5D6BFD3B01AC`。
- 已在真机 V2352A（arm64-v8a）覆盖安装并启动；系统报告 `versionCode=2317`、`versionName=0.9.9`。
- 真机定位到逐字歌词播放区间录屏并逐帧复核：字符只随自身高亮开始上浮、随自身高亮完成到达终点，后续字符不再提前跟随上浮；换行播放连续。
- 播放后检查 logcat，未发现应用相关 `FATAL EXCEPTION`、`AndroidRuntime`、`E/flutter` 或异常错误。

## 产物

- APK：`dist/Myune-Music-0.9.9-android.317-arm64-v8a.apk`
- 真机同步区间录屏：`video_karaoke_317_review/device_317_synced.mp4`
- 真机同步区间联系表：`video_karaoke_317_review/contact_317_synced.png`
- 30 fps 动画细节联系表：`video_karaoke_317_review/detail_317_synced.png`
