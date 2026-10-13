# Android387：音乐音效增益与封面外光入场

日期：2026-10-13。版本1.0.0+387；正式ARM64 versionCode2387。沿用用户本轮不做真机测试的边界，无ADB、安装、应用启动、Profile、录屏或Launcher登记。没有提交、推送、tag或Release；源码同步在修改、构建期间暂缓。

## 封面

- 设置“播放”的封面大小为100%/90%/80%；既有80%保持，旧60%迁移并保存为80%，非法值回退100%。保留布局槽与Hero尺寸逻辑，没有新增选项注释。
- 动态背景封面外光为白色、最终alpha0.10、blur10/spread0/outer/圆角8。
- 独立720ms easeInOutCubic外光淡入，同时检查路由完成、封面回到可见位置且动画结束、图片已解码且封面交接完成。没有“固定等若干毫秒就点亮”的替代门槛。
- 图片自身报告显示完成，空图/解码失败/等待下一张/连续切歌的待交接图均不提前点亮。封面→歌词隐藏外光；切回封面待真实transform结束后重亮。减少动画设置下完成门槛仍成立、点亮直接交接。
- 外光装饰和Image/Hero元素保持；仅外光动画重绘，完成无活跃Ticker，不新增BackdropFilter。不是全播放页GPU或120fps证明。

## 音频

原EQ将各频段直接串联，Q=1的相邻提升会重叠，整数样本可能在中间频段先削波。原始custom过滤器每次改变字符串都会重建链。部分效果默认干声增益、压缩阈值、软削波非线性及过强高频增强还会引起响度变化或刺耳。

- MusicDspSettings是独立手写类型，不修改自动生成的AudioEffects目录；播放器链写入、实时diff、失败恢复和换曲重同步统一使用有效音乐图。普通typed效果配置仍保留，音乐图为显式启用。异步写入只确认其捕获字符串；较早的回执不能把随后改变的EQ/响度标为已同步，拒绝或失败保留换曲恢复标记。
- 输入浮点；10段EQ和已有bass/treble/tiltshelf/highpass/lowpass显式f32，避免中间整数硬削波。RBJ Q=1数字响应预测整个级联峰值、192段对数网格加实际频段中心，额外0.5dB余量；全减益或全平不添加预衰减。
- 预衰减及响度增益用零状态biquad的b0实现，不依赖精简原生库缺失的volume滤镜，不改变声道数。频段、b0通过有名称的lavfi子滤镜实时命令更新；先衰减后提高EQ，先降低EQ后恢复增益。
- 正常播放中EQ和响度增益按1dB/16ms平滑推进，快速操作合并到最新目标。mapper保留并发更新的EQ、响度和采样率。首次启用及拓扑改变仍需写链，原生不支持某命令时恢复完整最新图；不能宣称所有效果开关都免重建。
- 所有效果及自有响度增益后只有一个最终峰值保护，level=false、limit0.891250938约−1dBFS、5ms attack/100ms release、latency=true。默认平EQ、零响度增益、无效果时没有音乐滤镜图；实时拖回零可保持已建图直到下次轨道配置，以避免反复冷建。
- 压缩threshold0.35/ratio1.5/makeup1.15/20ms/200ms，Haas干声in/out1/side0.25，回声in/out1/decays0.18/0.08，立体声dry1。增强低频/晶化/激励降低力度；去噪也更保守。软削波为2*tanh(0.5*x)、阈值1、单倍采样，保留用户选择的非线性音色，减少原始tanh削弱；不额外串联重复limiter。
- 自有−16LUFS扫描增益移入最终保护前，启动AO volume-gain清零，新曲空扫描重置旧曲增益；原生ReplayGain仍track/clip=false，false表示禁止原生归一化削波。该原生增益及用户音量在AO侧、滤镜之后，故−1dBFS保护是音乐滤镜输出样本峰值界，不是真峰值或任意AO增益下绝不失真的承诺。

## 验证

- 新增14项回归：三档迁移/外光范围与元素、路由+慢解码完成、封面返回、连续切歌、EQ重叠余量/低采样率频率限幅/异常输入、实时命令顺序、浮点与最终保护顺序、生产图导出、服务快速操作合并及并发槽位、先开效果的保护图、较早回执/失败恢复。
- 最终全量677通过/1项既有跳过，静态分析无问题、工具6项通过、610项验证代码哈希。构建与留档最终结论以证据目录清单为准。
- 使用已有本机7z内的FFmpeg可执行文件，仅解压到外部证据目录；没有下载或替换生产原生库。24个实际生产图在48kHz双声道合成音频上全部执行、数值有限且峰值≤0.891252。
- 0.75振幅1kHz正弦、10段+6dB、16-bit输入：旧链THD约35.409%，新链约0.001439%；新浮点输入约0.000019%。这是特定合成输入/滤镜测量，不能等同实际曲库主观听感。
- 同样本左声道稳定RMS：压缩0.235→0.502，Haas0.203→0.402，回声0.345→0.630；不同效果本来会改变频率、声像及能量，不做任意内容等响度保证，也没有自动无限抬增益。
- Windows本机libmpv v0.41.0仅null AO：真实解码合成WAV、生产图解析及13条EQ/b0/频率实时命令成功，af字符串保持、日志确认子滤镜系数改变。不是Android原生运行测试；Android原生二进制逐字节保持，仍需后续允许真机时核对实际听感、开关、seek及CPU。
- 三张实际组件软件帧已查看：入场前、淡入中点、完全点亮；合成渐变封面/固定底色，非完整播放页。中点最大RGB变化6、最终11，轻柔小范围白色外光；不声明GPU/功耗下降。
- 有效红测、softclip非法参数、精简FFmpeg缺格式、缺volume、接口类型遗漏、fake-frame精确端点等待和debug阴影恢复失败全部留存；优先all-tests-final、analysis-shipping、verified-code-hashes-shipping、native-final、native-mpv-fourth、visual-shipping。首个116.4秒候选APK及其2184D30B…哈希保存在证据目录，随后修复回执竞态再构建最终包，不覆盖候选证据。

参考：[FFmpeg滤镜说明](https://ffmpeg.org/ffmpeg-filters.html)、[mpv af-command](https://mpv.io/manual/stable/#command-interface)、[FFmpeg RBJ实现](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_biquads.c)、[mpv AO增益](https://github.com/mpv-player/mpv/blob/master/player/audio.c)。用文档核对参数/行为，未复制上游实现代码。

## 交付与范围

- `dist/Myune-Music-1.0.0-android.387-arm64-v8a.apk`
- `dist/Myune-Music-1.0.0-android.387-source-20261013.zip`
- `F:/AGENT/1/test-artifacts/audio-cover-387/`
- `F:/临时文件夹/备份/Myune-Music-1.0.0+387-20261013/`

最终Release44.8秒，APK32,248,924 bytes，SHA256 `B6AF1066CA4220730BF8372AD29676AF68BB3B9E0C496408A4D48E8AB2AF1461`；正式2387/仅ARM64/v2签名/16KiB zipalign及ELF/压缩原生库/字体/CRC通过。6项非libapp原生内容及19项Flutter资源与386逐字节一致，610项验证代码构建后保持。

完整758项源码，相对386修改24/新增9/删除0；386动态背景shader/取色/16色运动及弹性歌词代码、385网络逐字和其他主页/静态高斯算法保持。本轮仅音频链、封面参数/外光衔接及必要PlayerApi类型适配。源码CRC、备份SHA及源码ZIP的最终SHA以外部最终清单为准，避免自指哈希；历史快照不覆盖。
