# Android 418：输出管理器关闭时序

版本 `1.0.0+418`，正式 ARM64 versionCode `2418`。本轮在自行质量检查中复现退出边界缺陷，保留 417 的后台播放、同步、DSP、歌词、背景和全部已有数据。没有提交、推送或发布 GitHub。

## 原因与处理

应用根返回调用 `shutdownForAppExit()`，其中会先调用输出管理器的 `releaseResources()`，随后销毁实际播放器；拥有该管理器的 ChangeNotifier 则稍后才 dispose。旧实现只等待串行操作队列，没有等待初始化，也没有在 release 时取消错误订阅和恢复计时器。因此初始化设置可能在释放之后迟到，已经排队或随后到达的错误可再次触发设备重载，退出后的输出操作也仍会抵达播放器与原生通道。

`releaseResources()` 现在立即停止接收新工作、取消输出事件/参数/错误订阅及计时器，等待初始化和在途命令，再清理混音器、还原透明输出与独占状态。`dispose()` 复用同一停止入口，仍由拥有者负责释放 notifier。资源释放 Future 保持幂等。初始化刷新之后重新检查关闭状态，USB 标识请求和系统输出选择器也阻止退出后的调用；关闭期间失败的旧命令不再额外启动恢复重载。

已发出的平台操作仍需等待其回执，不声称能强行取消系统 IPC 或瞬间退出。正常播放、设备恢复策略和音频数据处理不改变。

## 验证

- 新增 7 项生命周期测试，其中最初 5 项在旧实现下复现 4 项失败，原始失败记录保留。
- 覆盖初始化阻塞时释放等待、释放前已排队的恢复、释放后迟到错误、释放后的全部公开输出操作、重复释放/先释放后 dispose、初始化之前退出、在途操作排空与后续排队选择取消。
- 定向初次 26 项通过；新增最后两项后全量 882 项通过、1 项既有跳过，约 68 秒。静态分析无问题，13.4 秒；Python 工具 22 项通过。
- 688 项运行/构建/测试输入在构建前冻结，构建后逐文件 SHA256 保持。仅 ARM64 split Release 构建成功，278.4 秒。
- APK `dist/Myune-Music-1.0.0-android.418-arm64-v8a.apk`，32,356,379 bytes，SHA256 `7F6140624D6D7A9CF1B120363AC7EA0C0DA9FD8CEB666B43386A52EADF7E3253`。包名 `com.myune.music`、2418、v2 签名和与 417 相同证书通过；16 KiB ZIP/ELF、CRC 和压缩原生库通过。与 417 比较，7 个非 libapp 原生库及 19 个 Flutter 资源逐字节一致。

证据：`F:/AGENT/1/test-artifacts/audio-lifecycle-418/`。优先检查 `shutdown-red.txt`、`all-tests.txt`、`analysis.txt`、`verified-code-hashes.json`、`apk-audit.json`、`apk-comparison.json`、`apk-signature.txt` 与最终 `artifact-manifest.json`。同一会话此前的构建工具/CI修复也包含在源码中，详见 `quality_audit_20261023.md`；这些工具差异不等于本轮新增音频行为。

ADB 未连接设备，没有安装、实际应用启动、真机退出或听感测试，没有进行 Launcher 登记。自动化时序测试与 APK 检查不等同于真机验收。413～418 开发变更仍待下一次获授权的 GitHub Release 统一归并，不新增虚假的已发布日志条目。

完整源码使用 `dist/Myune-Music-1.0.0-android.418-source-20261023.zip`；标准备份使用 `F:/临时文件夹/备份/Myune-Music-1.0.0+418-20261023/`。文件清单、ZIP CRC、差异范围和备份逐字节校验见最终外部清单；417 与以前的交付产物保持不变。
