# 319：修复逐字歌词提前整行上浮

## 根因

318 的跟随计算将前一字符的「自身上浮 + 跟随上浮」总位移继续传给下一字符。第六级起的衰减比例为 0%，等于不再降低高度，跨相邻词元传播时会把尚未高亮的整行文字提前抬起。

## 修改

- 跟随只由字符自身的高亮上浮发起，不再转发从别的字符接收到的跟随位移。
- 一个字符最多影响后续五个字符，预上浮上限依次为完整高度的 20%、15%、10%、5%、2%；第六个及更远的字符保持静止，直到自身高亮或附近字符的有效接力开始。
- 后续字符依距离延迟启动；自身高亮仍可将字符平滑推至完整 9% 高度，保留顶端减速缓冲。
- 相邻词元可接力，停顿超过 220 ms 时继续断开；翻译行不参与上浮和高亮。

## 额外检查

- 回归覆盖：长行后续字符静止、接力不二次传播、跨词停顿、短词与中文、连续性和终点高度。
- 保留 316 的行跳转预热与布局缓存，未改动普通歌词及其他播放页功能。

## 验证

- 逐字歌词与版本记录专项测试：77 项通过；完整 Flutter 测试：239 项通过。
- 涉及文件静态分析无问题；`git diff --check` 无空白错误。
- 仅执行 `flutter build apk --release --target-platform android-arm64 --split-per-abi`；APK 仅含 `arm64-v8a` 原生 ABI。
- APK 元数据：`versionCode=2319`、`versionName=0.9.9`；16 KiB zipalign 和 Android v2 签名校验通过。
- APK SHA-256：`B2ED10A810524DC809E864214B923D2BFB1EF249454AB88EE4AB323BB9684C0F`。
- 已覆盖安装并启动于 V2352A（arm64-v8a）真机；设备报告 `versionCode=2319`。
- 定位到长英文逐字歌词区间，完成 12 秒真机录屏、4 fps 联系表及 15 fps 细节抽帧；未高亮的后半段保持原位，逐字高亮与换行过渡正常。
- 播放后 logcat 未发现 `FATAL EXCEPTION`、`E/flutter` 或应用异常错误。

## 产物

- APK：`dist/Myune-Music-0.9.9-android.319-arm64-v8a.apk`
- 真机录屏：`F:/AGENT/1/video_karaoke_319_review/device_319_synced.mp4`
- 长行联系表：`F:/AGENT/1/video_karaoke_319_review/contact_319_synced.png`
- 动画细节联系表：`F:/AGENT/1/video_karaoke_319_review/detail_319_synced.png`
