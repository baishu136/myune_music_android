# 321：修复逐字歌词缓慢连续上浮未生效

## 根因

320 将非词尾字符的完整上浮压缩在“当前字符起亮 → 下一字符起亮”的单个字符间隔内。长词中间隔很短，虽然到顶时点准确，但肉眼看到的是快速抬升而不是缓慢连续运动。

## 修改

- 非首字符从前一个字符开始高亮时缓慢起步，仍在后一个字符开始高亮时到顶，使主要上浮时长约增加至原来的两倍。
- 首字符从本词元高亮前有限预启动：最多 80 ms、一个字符间隔或短词可视时长的 35%，不会让远处整行歌词提前上浮。
- 词尾、句尾仍以当前字符的高亮完成时点作为到顶终点；紧邻中文单字时间片继续按下一字起亮衔接。
- 保留 319 的最多五级有限跟随、9% 最终高度和到顶减速缓冲；歌词高亮时间轴与其他页面不变。

## 验证

- 专项测试 81 项、完整 Flutter 测试 243 项通过；覆盖两倍上浮时间窗口、首字符限幅预启动、下一字符起亮到顶、词尾与中文边界。
- 涉及文件静态分析无问题；`git diff --check` 无空白错误。
- 仅执行 `flutter build apk --release --target-platform android-arm64 --split-per-abi`；APK 原生 ABI 仅 `arm64-v8a`。
- APK 元数据：`versionCode=2321`、`versionName=0.9.9`；16 KiB zipalign 和 Android v2 签名校验通过。
- APK SHA-256：`863B9FA61F2E3E8AF358A3587ADC463D6482466EEFFA841941A051172021C3F8`。
- 已覆盖安装并启动于 V2352A（arm64-v8a）真机，设备报告 `versionCode=2321`。
- 定位到长词逐字歌词播放区间，完成 12 秒真机录屏、4 fps 联系表及 15 fps 细节抽帧；高亮推进、有限预上浮和换行过渡正常，未见整行提前抬起。上浮持续时间和到顶边界由数值测试验证。
- 播放后 logcat 未发现 `FATAL EXCEPTION`、`E/flutter` 或应用异常错误。

## 产物

- APK：`dist/Myune-Music-0.9.9-android.321-arm64-v8a.apk`
- 真机录屏：`F:/AGENT/1/video_karaoke_321_review/device_321_synced.mp4`
- 播放联系表：`F:/AGENT/1/video_karaoke_321_review/contact_321_synced.png`
- 动画细节联系表：`F:/AGENT/1/video_karaoke_321_review/detail_321_synced.png`
