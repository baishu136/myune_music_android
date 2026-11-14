# Attribution / 来源与修改说明

本项目是 [Myune Music](https://github.com/xiaobaimc/myune_music) 的 Android 移植与手机端适配版本，基于上游 `0.9.2` 源码构建。

- 上游项目：`xiaobaimc/myune_music`
- 上游地址：https://github.com/xiaobaimc/myune_music
- 上游许可证：Apache License 2.0
- 本项目性质：非官方派生版本，与上游作者不存在隶属或官方背书关系

本派生版本保留了上游的 `LICENSE` 文件，并继续使用 Apache License 2.0。原始代码版权及署名归上游作者和贡献者所有。

## 本版本的主要修改

- 增加适合手机触控操作的 Android 界面与导航结构
- 支持导入单曲或整个文件夹中的歌曲
- 增加 Android 音频元数据与内嵌封面读取
- 增加 Android 通知栏媒体播放器与耳机媒体按键控制
- 修复播放进度同步、暂停状态拖动进度和歌词自动滚动
- 调整播放页、设置页、主题取色器和均衡器操作体验
- 移除托盘、独占输出设备等不适用于手机的桌面功能入口

如需了解原始项目、提交上游问题或支持原作者，请访问上游仓库。

插件脚本运行时包含 Fabrice Bellard、Charlie Gordon 等作者的 QuickJS
2026-06-04，使用 MIT 许可证。未修改的引擎源码及许可证位于
`third_party/quickjs/`；仅编译核心引擎，不编译标准文件/系统模块。
来源：https://bellard.org/quickjs/quickjs-2026-06-04.tar.xz
上游压缩包 SHA256：`b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`。
