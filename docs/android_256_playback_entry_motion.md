# Android 256：播放页入场动画调整

日期：2026-09-11

## 改动

- 播放页入场时间由 700 毫秒调整为 620 毫秒。
- 移除 40% 至 100% 的透明度渐变，页面不再额外创建透明度合成层。
- 保留 Cupertino 位移动画和封面 Hero 动画。
- 255 版的流体背景色板、运动相位及 Shader 连续性修复保持不变。
- 路由性能保护窗口同步覆盖新的 620 毫秒入场过程，动画结束后再恢复歌词实时效果和流体运动。

## 验证

- `flutter analyze --no-pub`：通过，0 个问题。
- `flutter test --no-pub`：190 项测试全部通过。
- 已验证播放页入场常量为 620 毫秒；透明度动画及额外透明度合成层已从路由实现中移除。
- arm64-v8a release APK：构建成功，包名 `com.myune.music`，versionCode `2256`，versionName `0.9.9`。
- APK 仅包含 `lib/arm64-v8a/libapp.so`，流体背景 Shader 已随包打入。
- APK Signature Scheme v2 校验通过；当前沿用项目既有 Android Debug 证书。
- SHA-256：`073424A5FD4A058C55435D3013DF41F5260862D05557D370311245F3174CE42F`。
- 构建后 ADB 未检测到连接设备，因此本轮未执行真机帧耗时采样。
