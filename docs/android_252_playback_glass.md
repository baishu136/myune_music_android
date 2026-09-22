# Android 252：恢复播放功能区毛玻璃

日期：2026-09-11  
版本：`0.9.9+252`

## 改动

- 流体背景下重新启用播放控制区、均衡器按钮和底部功能栏的真实局部模糊。
- 三个互不重叠的功能区通过同一个 `BackdropGroup` 共享背景采样，避免分别重复抓取流体背景。
- 流体背景使用 `sigma=5`，原模糊封面背景继续使用 `sigma=7`；不增加全屏模糊。
- 页面进出期间关闭模糊并使用稳定的半透明填充，路由完成且交互空闲后再启用。
- 应用进入后台时关闭模糊；返回前台后等待 1150 ms，再通过空闲任务许可恢复，避免与 Surface、流体 Shader 同时抢占恢复首帧。
- 大型播放设置弹层继续使用无实时模糊的透明表面，避免恢复已测得的弹层持续合成开销。

## 验证

- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub`：186 项测试全部通过。
- arm64 profile 与 release APK 均构建成功。
- 发布 APK：`F:\AGENT\1\myune_music_android\dist\Myune-Music-0.9.9-android.252-arm64-v8a.apk`
- APK：`versionCode=2252`、`versionName=0.9.9`、仅含 `arm64-v8a` 原生库，并包含流体背景 Shader。
- APK Signature Scheme v2 验证通过；沿用项目现有 Android Debug 证书。
- APK SHA-256：`9C298AC8538DEEE273F52069330399519A09D11889490B02C7E699BD54D4D441`
- 留档目录：`F:\临时文件夹\备份\Myune-Music-0.9.9+252-20260911-091656`

本轮构建时 ADB 设备列表为空，因此没有把 251 的真机数据直接复制为 252 结论。需要设备重新连接后补测进入播放页、播放稳态和后台恢复三组 profile 数据。
