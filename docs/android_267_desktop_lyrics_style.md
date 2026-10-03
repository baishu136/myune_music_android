# Android 267：桌面歌词样式与关闭动画

## 改动

- 在“设置 → 播放 → 桌面歌词设置”中新增歌词透明度调节，范围为 20%–100%。
- 新增字体粗细调节，范围为 300–900，并以 100 为步进。
- 两项设置均持久化保存，预览和 Android 原生悬浮窗实时同步。
- 将歌词内容透明度与悬浮窗淡入淡出透明度分层，样式透明度不会破坏开关动画。
- 关闭开始后拒绝迟到的歌词同步重新挂载窗口；淡出完成后先隐藏视图，再立即移除窗口，避免部分系统合成器显示最后一帧而闪烁。

## 性能

- 透明度使用原生 View alpha，字体粗细仅在设置或字体变化时创建 Typeface，不增加歌词逐帧绘制或定时任务。
- 关闭流程没有增加等待时间或额外图层。

## 验证

- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub --reporter compact`：197 项测试全部通过。
- arm64-v8a Release APK：构建成功。
- 包信息：`com.myune.music`，`versionName 0.9.9`，`versionCode 2267`，仅包含 `arm64-v8a`。
- APK Signature Scheme v2：验证通过。
- SHA-256：`BCB6B4A5303E5E874C57F16DDAE700FD006DEBC29FE663B4F96E7E712C51A1BF`。
- ADB：当前未检测到已连接设备，因此未执行真机安装与视觉回归。
