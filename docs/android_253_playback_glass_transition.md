# Android 253：播放功能区毛玻璃过渡

日期：2026-09-11  
版本：`0.9.9+253`

## 问题与修复

- 252 在取得交互空闲许可后只注册 `addPostFrameCallback`。当歌曲暂停且动态背景静止时，Flutter 可能没有下一帧，导致回调一直不执行，表现为毛玻璃偶尔不生效。
- 253 改为在空闲许可内直接更新状态，由 `setState` 主动请求下一帧，确保静态页面也会启用模糊。
- 三个功能区共用一个 220 ms、`easeOutCubic` 的透明度控制器，从稳定半透明底交叉淡入真实模糊，不创建三套 ticker。
- 页面退出、应用离开前台时立即停止动画并切回半透明底，不让淡出动画参与路由合成。
- 延续 252 的单一 `BackdropGroup`、流体模式 `sigma=5`、限定局部裁剪和大型弹层不启用实时模糊策略。

## 验证

- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub`：186 项测试全部通过。
- arm64 release APK 构建成功。
- 发布 APK：`F:\AGENT\1\myune_music_android\dist\Myune-Music-0.9.9-android.253-arm64-v8a.apk`
- APK：`versionCode=2253`、`versionName=0.9.9`、仅含 `arm64-v8a` 原生库，并包含流体背景 Shader。
- APK Signature Scheme v2 验证通过；沿用项目现有 Android Debug 证书。
- APK SHA-256：`01D751384D4B426332AECDB970B03B867A92F42777CC3C27BA785934F50DF77F`
- 留档目录：`F:\临时文件夹\备份\Myune-Music-0.9.9+253-20260911-093932`

构建完成时 ADB 设备列表仍为空，因此未记录 253 真机逐帧数据；需要设备重新连接后补测进入播放页、暂停播放和后台恢复三种状态。
