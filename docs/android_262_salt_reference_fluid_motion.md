# Android 262：参照 Salt Player 优化流体背景

日期：2026-09-11

## 录屏对照结论

- `1.mp4`（Salt Player）在约 60 秒内呈现宽阔色带连续横向掠过，蓝、青、绿区域在同一画面中始终保有明显但柔和的空间差异。
- `2.mp4`（Myune Music 261）的大半画面长期由相近绿色覆盖，颜色主要表现为整屏缓慢变化，局部流向和空间层次不足。
- 两段录屏帧率及长度接近，因此本次只调整 Shader 内的空间分布与运动轨迹，不提高刷新率。

## 实现

- 将接近全屏大小的椭圆色团收窄为纵向大半径、横向中等半径的柔和色带。
- 四个色带中心使用不同低频相位横跨屏幕边缘，避免同向、同步移动。
- 用两层低频纵向弯曲改变色带边缘，使横向流动保持自然，不形成笔直分界或孤立圆斑。
- 提高边缘基础权重并减轻暗角，避免色带离开屏幕时出现亮度抽动或突然色块。
- 保持单遍 Fragment Shader、四次指数色域计算以及 24/30/60 FPS 三档刷新策略不变。

## 验证

- 已分别按 5 秒间隔抽取 `1.mp4` 与 `2.mp4` 的全程画面，对照确认 Salt Player 的横向宽色带特征以及 261 版空间变化不足的问题。
- `flutter analyze --no-pub`：通过，0 个问题。
- `flutter test --no-pub`：通过，195 项测试全部成功。
- Android arm64 release 构建：通过，新 FragmentShader 已由 Flutter 运行时效果编译器编译并打入 APK。
- APK：`com.myune.music`，`versionName 0.9.9`，`versionCode 2262`，包含 `lib/arm64-v8a/libapp.so` 与 `assets/flutter_assets/shaders/fluid_background.frag`。
- APK v2 签名验证通过；SHA-256：`31CD4BDDC2885DCC5DBE82E0495B8F3B35A856D3153B67C50C81FC8BDB0E4E2A`。
- 构建时 ADB 未检测到设备，未执行自动安装、真机录屏及 GPU 帧耗时采样。
