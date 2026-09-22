# Android 263：流体背景摩尔纹修复

日期：2026-09-11

## 原因与处理

- 262 版在横向和纵向坐标上分别叠加两组不同周期的波形；经过屏幕缩放、录屏压缩或八位颜色量化后，重复弯曲与渐变色阶可能形成明显的干涉纹。
- 本版将每个方向收敛为一组低频波形，保留 Salt Player 风格的横向宽色带和柔和弯曲，但不再生成周期相近的重复纹理。
- 输出前加入幅度低于一个八位色阶的静态抖动，打散大面积渐变断层。抖动不随时间变化，因此不会产生闪烁。

## 性能约束

- 仍使用单遍 Fragment Shader、四个色域和既有 24/30/60 FPS 档位。
- 没有新增纹理采样、绘制层或动画控制器。
- 坐标弯曲的三角函数计算从四次减少到两次；静态抖动只使用点积与小数运算。

## 验证

- `flutter analyze --no-pub`：通过，0 个问题。
- `flutter test --no-pub`：通过，195 项测试全部成功。
- Android arm64 release 构建通过，新 FragmentShader 已编译并打入 APK。
- APK：`com.myune.music`，`versionName 0.9.9`，`versionCode 2263`，包含 `lib/arm64-v8a/libapp.so` 与 `assets/flutter_assets/shaders/fluid_background.frag`。
- APK v2 签名验证通过；SHA-256：`F304DFA9EA6EFA96783DA4C216051CE4C4F5334F2814612BC9A282B5C741C734`。
- 验证时 ADB 未检测到设备，未执行自动安装、真机录屏与 GPU 帧耗时采样。
