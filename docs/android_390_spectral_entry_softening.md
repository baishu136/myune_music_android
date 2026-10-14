# Android390：切歌与播放开头的高频柔化

2026-10-14，1.0.0+390，基线389的774项不可变源码ZIP，SHA256 `669462967295B4E856F002BE212C9B11C76DF763EFA57D53A05D6D6FC9BE32D6`。保留388/389所有成果，本轮不提交/推送/tag/Release，继续无真机测试、ADB、安装、应用启动/Profile/录屏/Launcher登记。

## 改动

移除切歌/恢复播放的AO −60→0dB整体淡入，改成MusicDspSettings独立高频棚式衰减槽。中心3500Hz，低采样率限制至采样率40%；初始gain−6dB、t=q/w=0.5/f32，实际输出开始后用480ms半余弦曲线恢复到0dB。16ms参数更新、串行合并最新目标，缓冲冻结计时，快速换曲/暂停/销毁仍有代际保护。用户volume、AO volume-gain、十段EQ、响度、睡眠音量及音效控制参数不用于此过渡；初始化AO gain仍归零，播放过程中不写负AO gain。

新槽先在播放前准备，第一次建立后以0dB保留，后续只用命名treble滤镜的gain命令，避免每帧重建AF或在结束时拆除滤镜造成断续。参数不写用户设置。仅柔化时使用aformat/treble及unity峰值保护，省去空EQ网格/预衰减/输出增益节点；unity alimiter limit1、level=false、5ms/100ms/latency补偿，只防滤波瞬态越界，不做音量从低到高的控制。已有EQ/音效/响度处理仍走原−1dB末端保护，高频槽在末端增益与保护之前，维持单一限幅器。

diff的同EQ/同响度快速路径仅提交高频gain，不重算192点EQ响应网格；采样率变更更新必要频率，用户EQ/音效变化仍按原拓扑规则更新。图内字段copyWith保持当前用户参数。滤镜不支持或恢复命令失败时取消柔化并尝试移除槽，保留其余处理；迟到的失败在销毁后不再安排恢复写入。

这是固定高频柔化，不是识别“刺激感”的算法，也未做耳机听感验证。部分高频成分的响度会降低，低中频基本保持；不是完全无音色变化。480ms为实际playing流驱动的参数恢复时长，AF之前/之后的解码、AO缓冲会影响最终听到的时间，不保证每个设备的首个采样或听感恢复恰好480ms。原生自动无缝切歌仍由playlist事件触发，不承诺Dart事件发生在第一采样前。

## 验证

706项Flutter通过、1项既有跳过，新增7项。原控制器5项与加载3项按高频行为更新：不写负AO gain、EQ/响度并发保持、unsupported取消、慢加载/缓冲/快速切歌/慢写合并/旧暂停回执/销毁后迟到失败；新增DSP槽、命令/拓扑/低采样率及导出回归。静态无问题，工具6项。

实际生产图14个、8/44.1/48/96kHz、42个正弦频响测点，−6/−3/0dB阶段与组合EQ+响度均有限。48kHz/初始−6dB时300Hz约−0.00033dB，1kHz−0.04020dB，8kHz−5.83292dB；0dB恢复测点近unity。3个0.99幅度、起始非零相位的1kHz样本峰值≤1.000001，组合处理保持既有≤0.891252样本保护。

Windows本机libmpv v0.41.0仅null AO，31条实际treble gain命令成功，AF属性字符串未重写，volume72/volume-gain0保持。上述是离线合成与Windows属性/命令验证，不是Android听感或设备性能结论。

首轮有效红测捕获AO仍写−60dB。候选w0.707在48kHz/1kHz会抬升约0.218dB，已改w0.5并保持无中频抬升断言；8kHz的测试3520Hz接近棚中心3200Hz，实际−5.327dB，将专用边界阈值设为−5dB，其余采样率仍−5.4dB。候选图/失败日志/诊断和lint全保留，最终优先all-tests-complete、analysis-complete、graphs-shipping、native-shipping。

证据`F:/AGENT/1/test-artifacts/entry-softening-390/`。完整776源码较389改9/增3/删1（旧播放音量淡入文件由高频柔化文件替换），624代码哈希。歌词/default滚动/背景/封面/队列/EQ预设及生成音效目录保持。APK、源码及备份CRC/签名/16KiB/字体/原生与资源范围/SHA以最终清单为准；备份`F:/临时文件夹/备份/Myune-Music-1.0.0+390-20261014/`，不覆盖旧产物。

Release85.9秒，APK32,275,012 bytes，SHA256 `A4000BC99FD5982499B8513D43BD136E9B77DA5F73DBE71D9230A5075628FF9C`。`dist/Myune-Music-1.0.0-android.390-arm64-v8a.apk`及`dist/Myune-Music-1.0.0-android.390-source-20261014.zip`；正式2390/单ARM64/既有debug密钥v2签名。6项非libapp原生与19项Flutter资源保持389；代码构建后哈希和全部副本以final-verification/artifact-manifest/backup-verification为准。
