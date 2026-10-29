# 432 无线设备后台播放输出修复

2026-10-29，1.0.0+432 / ARM64 versionCode 2432。用户反馈无线设备后台声音规律性或不规律断续，其他播放器正常；暂不能确认用户此前是否手动指定设备。

## 定位依据与修改

416 输出管理初始化把普通系统自动输出从原先 mpv 的 AudioTrack 优先顺序改成 AAudio 优先。AAudio 的回调供音路径与 AudioTrack 的阻塞写入路径不同，前者在部分无线设备及后台调度组合下存在兼容风险。这是确认的应用输出路径变化，不是本轮已测得的唯一声学根因；417 的短时零欠载测试不能排除长时间或特定音效组合的问题。

- 普通系统自动播放固定优先 `audiotrack,opensles`；不因后台/前台或设备清单通知反复切换后端。手动选择已经是系统媒体路由的非 USB 设备，同样复用此兼容路径。切换前重新读清单，不按名称猜测设备。
- 定向选择其他设备及 USB Bit-Perfect/独占请求继续走原 AAudio 验证链路；USB 专用能力不冒充普通系统输出。既有均衡器、音效、增益、队列、播放进度、歌词时钟及补偿符号保持。
- 切换准备阶段不再先写一次旧后端。mpv 的 `ao` 选项本身携带 `UPDATE_AUDIO`：后端发生变化时不再紧跟一次 `ao-reload`；同一后端内变更设备/格式才显式重载。重复点选健康的系统自动输出只刷新状态。
- Android 音乐属性在首次打开媒体前设定，保留原 500ms 软件缓冲。原 200ms AAudio 共享流缓冲策略、前台媒体服务、播放唤醒锁、正常暂停和音频焦点策略保留。
- Android 13+ 通过公开接口读取系统预期媒体路由，按唯一设备 ID 恢复原有歌词补偿配置；空结果、重复输出到不同设备或无法对应清单时不借用任意设备配置。Android 12 及更旧系统未提供此接口时保留全局补偿；定向 AAudio 有真实回执时仍使用真实设备配置。
- 系统预期路由和应用实际音轨分开显示、分开判断。兼容输出下没有持有 AudioTrack 对象，不能读回它的实际设备/硬件格式；界面明确标为系统媒体路由及未读回，不凭清单虚构确认，不据此报告独占或 Bit-Perfect。未增加持续轮询、音频回调处理或每帧工作。

## 自动验证与限制

修改前新增测试复现 5 项失败，保留原始记录。新回归覆盖启动后端、20 次重复自动选择、系统当前蓝牙选择、同后端定向切换、失效恢复、250 次清单刷新、40 条迟到断连事件、补偿配置往返与重复路由隔离。旧测试的模拟播放器补齐 `ao` 自动重建语义；修复后的首次旧用例失败是模拟重载未更新后端状态，记录同样保留，未放宽断言。

最终全量 940 通过、1 项既有跳过，101 秒；定向 41 项通过，最终全量包含最后补充的选择前刷新守卫；静态无问题，93.7 秒；Python 构建工具 22 项通过。Android 原生编译和 28 项 JVM 单测通过，114 秒，包括后台服务恢复、音频占用及原生桌面歌词旧回归。708 项非文档构建/代码/测试输入在验证、构建后保持；相对 431 只改 5 个运行文件，所选其余 412 项运行/依赖/资源文件保持，依赖锁不变。软件内更新日志仍按最后实际 GitHub Release 412 展示，413～432 留待下次明确授权发布时归并。本轮不提交、推送或创建 Release。

本轮 ADB 未检测到手机，未安装或实际启动，未测无线声学连续性、蓝牙长时熄屏/功耗、USB DAC 或特定厂商调度。不能把主机模拟和短时历史记录当成这些硬件验收。建议后续在相同歌曲/音效下对照 431 与 432，分别采集蓝牙熄屏和其他应用前台播放至少 15 分钟，读取属于 Myune 的音轨、欠载增量、服务/锁状态并结合实际听感；不能只看整个混音器累计数字。

## 参考与留档

- [mpv 0.41 输出默认顺序与 UPDATE_AUDIO](https://github.com/mpv-player/mpv/blob/v0.41.0/audio/out/ao.c)
- [mpv 0.41 AudioTrack 实现](https://github.com/mpv-player/mpv/blob/v0.41.0/audio/out/ao_audiotrack.c)
- [mpv 0.41 AAudio 实现](https://github.com/mpv-player/mpv/blob/v0.41.0/audio/out/ao_aaudio.c)
- [Android 系统预期媒体路由接口](https://developer.android.com/reference/android/media/AudioManager#getAudioDevicesForAttributes(android.media.AudioAttributes))

证据：`F:/AGENT/1/test-artifacts/wireless-background-432/`。历史 431 的 APK、源码 ZIP 和标准备份保持不可变。

正式 ARM64 Release：`dist/Myune-Music-1.0.0-android.432-arm64-v8a.apk`，32,381,731 bytes，SHA256 `9D18D33C62BA95EC3E919213878C5A384AAC2830F9966457D2C603A923EBB610`。构建 110.1 秒，包名 `com.myune.music` / versionCode 2432；原 v2 签名证书、16KiB ELF 与 ZIP 对齐、压缩原生库及 CRC 均通过。7 项非 libapp 原生库和全部 19 项 Flutter 资源与 431 逐字节一致。

完整源码：`dist/Myune-Music-1.0.0-android.432-source-20261029.zip`。标准备份：`F:/临时文件夹/备份/Myune-Music-1.0.0+432-20261029/`。源码清单、哈希、逐文件范围和备份副本核验见外部 `artifact-manifest.json`。
