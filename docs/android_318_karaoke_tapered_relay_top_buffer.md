# 318：逐字歌词递减接力与到顶缓冲

## 修改

- 恢复字母和中文文字之间的连续跟随上浮；后续字符可在自身高亮开始前延迟跟随前一字符。
- 每一级跟随高度相对前一级依次降低 20%、15%、10%、5%、2%、0%；对应高度保留比例为 80%、85%、90%、95%、98%、100%，之后不再继续降低。
- 字符自己的高亮仍推动其完成全高上浮；跟随分量和自身分量平滑合成，不在交接时回落。
- 在原有平滑曲线的顶端加入额外减速缓冲，起点和终点速度仍为零；保留 9% 最终上浮高度。
- 跨相邻短词和中文单字时间片继续接力，超过 220 ms 的停顿断开接力。

## 保留行为

- 保留跳转目标行预热与布局缓存、短词和中文字符处理，以及翻译行静态不高亮。
- 不改动歌词时间戳、播放页其他动画或普通歌词模式。

## 验证

- 专项测试：76 项通过。
- 完整 Flutter 测试：238 项通过。
- 涉及文件静态分析：无问题；`git diff --check` 无空白错误。
- 仅执行 `flutter build apk --release --target-platform android-arm64 --split-per-abi`；APK 包内原生 ABI 仅 `arm64-v8a`。
- APK 元数据：`versionCode=2318`、`versionName=0.9.9`；16 KiB zipalign 与 Android v2 签名验证通过。
- APK SHA-256：`F1904F0E69A635C1B835F5E39FC9B919FF17B846347EBAEE8E821290D94D666C`。
- 已覆盖安装至 V2352A（arm64-v8a）真机并启动，设备安装信息报告 `versionCode=2318`。
- 真机定位到逐字歌词播放区间，完成 12 秒录屏及 15 fps 细节抽帧；英文逐字高亮、字符跟随上浮与换行过渡持续可见，未见字形消失或明显跳帧。
- 播放后 logcat 未发现应用相关 `FATAL EXCEPTION`、`E/flutter` 或异常错误。

## 产物

- APK：`dist/Myune-Music-0.9.9-android.318-arm64-v8a.apk`
- 真机录屏：`F:/AGENT/1/video_karaoke_318_review/device_318_synced.mp4`
- 抽帧联系表：`F:/AGENT/1/video_karaoke_318_review/contact_318_synced.png`
- 动画细节联系表：`F:/AGENT/1/video_karaoke_318_review/detail_318_synced.png`
