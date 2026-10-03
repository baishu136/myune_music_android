# 320：逐字歌词以上一字符的起亮作为当前字符上浮终点

## 修改

- 同一词元内，每个非末尾字母/文字从自身开始高亮的位置起步，并在下一个字符开始高亮的时点完全上浮。
- 词尾、句尾没有词内后继字符时，按当前字符的高亮窗口推进至终点；单字和短词也遵循这个规则。
- 相邻、无空格分隔的中文单字时间片，以后一字实际开始高亮的时点完成前一字上浮；若时间片停顿、重叠导致边界不可用，则退回前一字自身的推进速度。
- 保留 319 的有限五级预上浮、9% 最终高度和顶端减速缓冲；不调整歌词颜色高亮或播放时间戳。

## 验证

- 专项测试 80 项、完整 Flutter 测试 242 项通过；覆盖字符起亮边界、词尾速度、相邻中文时间片和有限接力。
- 涉及文件静态分析无问题；`git diff --check` 无空白错误。
- 仅执行 `flutter build apk --release --target-platform android-arm64 --split-per-abi`；APK 原生 ABI 仅 `arm64-v8a`。
- APK 元数据：`versionCode=2320`、`versionName=0.9.9`；16 KiB zipalign 和 Android v2 签名校验通过。
- APK SHA-256：`607F1EEEE58C4D04613DF67C8287B7B68C464B21D4F4790CFB019F8F80517BD3`。
- 已覆盖安装并启动于 V2352A（arm64-v8a）真机，设备报告 `versionCode=2320`。
- 定位到逐字歌词播放区间完成 12 秒真机录屏、4 fps 联系表及 15 fps 细节抽帧；高亮推进、有限预上浮与换行过渡正常。精确的字符到顶时点由数值测试验证。
- 播放后 logcat 未发现 `FATAL EXCEPTION`、`E/flutter` 或应用异常错误。

## 产物

- APK：`dist/Myune-Music-0.9.9-android.320-arm64-v8a.apk`
- 真机录屏：`F:/AGENT/1/video_karaoke_320_review/device_320_synced.mp4`
- 播放联系表：`F:/AGENT/1/video_karaoke_320_review/contact_320_synced.png`
- 动画细节联系表：`F:/AGENT/1/video_karaoke_320_review/detail_320_synced.png`
