# Android 1.0.0（353）：更新日志、Star 入口与 GitHub 发布

日期：2026-10-03。Android 显示版本为 `1.0.0-android.353`。本轮在用户明确授权后，将当前工作区自 0.99 以来的有效项目修改与本轮变更一起发布至 GitHub；保留历史记录及已有未提交成果，不进行真机测试。

## 修改

- 设置 → 常规 → 其他中的更新日志现在完整展示 0.99 汇总记录及其后的所有版本有效更改；更早的版本记录和全局发布统计仍保留。
- 移除原“赞助”内容，改为 GitHub Star 支持入口，显示“如果您喜欢此软件，请在GitHub留下star”及项目仓库链接。
- README 软件截图更新为音乐库、播放页和全屏歌词三张当前截图。
- `pubspec.yaml` 升为 `1.0.0+353`，同步应用版本及日志范围测试。

## 验证

- `flutter test --no-pub`：440 项通过，1 项跳过。
- `flutter analyze --no-pub`：无问题。
- 已针对更新日志过滤边界、支持项目文案/链接和应用版本添加测试。
- 按要求未连接、安装或操作真机。

## 发布产物

- ARM64 Release APK：`dist/Myune-Music-1.0.0-android.353-arm64-v8a.apk`
- APK 大小：32,301,884 bytes（30.81 MiB）；SHA-256：`952DEAAB186DCC5CB84FA4E858B96DACBF15E492199F525A3CA074754B72DAEE`
- 源码归档：`dist/Myune-Music-1.0.0-android.353-source-20261003.zip`
- GitHub Release：<https://github.com/baishu136/myune_music_android/releases/tag/v1.0.0-android.353>

APK 已通过 v2 签名验证和 16 KB ZIP 对齐检查，包内原生库仅含 `arm64-v8a`，版本为 `1.0.0` / `2353`。源码归档包含应用源码、测试、文档及本轮 README 截图，不包含 Git 历史目录、构建缓存、安装包、签名私钥或本机 SDK 配置。
