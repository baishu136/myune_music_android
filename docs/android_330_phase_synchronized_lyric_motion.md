# 330：微缓入、紧凑缓出与焦点属性同相

2026-09-26。实际工作区版本0.9.9+329，更新0.9.9+330（显示0.9.9-android.330）。先阅读README、328/329记录、相关源码和测试；未发现适用AGENTS.md。保留全部已有未提交修改，不重置，不修改音频、歌词时间、播放器同步或公开设置。

## 实际问题

- 329归一化位移确为500ms纯三次缓出，70px行程在retarget瞬间速度420px/s；静止启动测试在修改前失败，日志phase-before.log。
- 逐字焦点缩放已不是用户描述的220/280ms，而是520ms；但曲线和滚动不同，且blur的regularScrollMode优先分支导致实际620ms。外层Opacity直接改目标，没有渐变。原测试仅比较配置，不能证明相位一致。
- 正常间奏切行已经调用下一行retarget，并非完全没有迎宾滚动。本轮明确同边界同步、去除相邻间奏交接的bounded-tail截断，验证圆点退出与正文居中并行；不把高亮提前到真实时间戳之前。
- 329仍记录过Raster超预算；不能将本轮输入的“掉帧已解决”当成已有性能验收事实。

## 统一模型与参数

lib/widgets/lyric_normalized_motion.dart集中定义Curve、导数、时长函数。

- 默认420ms墙钟，与播放倍率独立；倍率只决定媒体边界何时到达。
- 静止启动采用**平滑速度包络的解析积分**，不是直接套标准五次smoothstep（后者峰速在210ms）或初斜率非零的Cubic(.25,.1,.2,1)。位置C2连续，初末速度/加速度为零。前1/7时段将速度smoothstep升至峰值，之后反向smoothstep缓出。
- r=1/7，I(u)=u³−u⁴/2：p(t)=2rI(t/r)（t≤r）；p(t)=1−2(1−r)I((1−t)/(1−r))（t>r）。420ms曲线60ms达到峰速，380ms完成约99.78%，420ms精确归零，不以位移阈值判停。70px在60Hz首帧约0.369px，不将首帧1–1.5px当成任意行距硬性保证。
- 行程≤70px用420ms；70–140px线性增加至480ms；更远仍480ms上限。105px用450ms。长段峰速约68.6ms达到，终点相同比例；时长自适应减轻但不保证任意超长句绝对峰速上限。
- 连续同向重定向保持位置和速度：按当前斜率在同一单调包络内定义边界斜率，不叠加两个独立位移。极近目标必要时缩短时长以保留速度且不超调。静止启动始终零速度；同目标retarget不重启。反向回中从现有位置以零速度重新启动，不宣称反向强改目标也保持原方向速度。
- 明确seek继续直接snap、清空轨迹，并将该次焦点属性时长置零；高亮时间与字形几何不受参数调整影响。

## 属性相位与间奏接力

mobile_lyrics_list.dart把本次归一化模型的transitionDuration和transitionCurve传给每行，而不是各自写固定时长。逐字AnimatedScale、AnimatedDefaultTextStyle和AnimatedOpacity，以及焦点blur使用相同参数。默认420ms，长行同时480ms，中途换目标同时使用继承斜率的曲线；Opacity使用局部FadeTransition合成，不逐帧全列表setState。

景深只允许正在交接的当前/上一行渐变，其他非焦点行在滚动期间仍用静态缓存阶梯，避免恢复十余行动态blur。所有滤镜复用原有61个有界实例；这是明确的非焦点性能保护，不能说远处每行也逐帧同相插值。未修改逐字高亮或字符760ms微浮模型，未重启局部行AnimatedSlide。

间奏正常退出时在同一didUpdate边界启动下一正文的完整居中行程；圆点仍使用329独立240ms退出。正文在列表既有40%阅读锚点落位，不新增50%锚点或抢先起唱。正常暂停后属性退出墙钟可完成，媒体高亮冻结；拖拽仍即时停止列表追踪并保持3.5秒回中规则。

## 自动化验证

- 新test/lyric_phase_motion_test.dart：静止启动/380ms进度/420ms终点；60/90/120Hz×单行/折行，以实际绘制中心位移测算p，再比对当前与上一行的ScaleTransition、FadeTransition和缓存blur结果，不只断言常量；帧期间完整字形排版计数不增长；间奏退出首个16.667ms正文已上移、最终落在40%焦点。
- 原归一化测试更新新预期，增加有界对称行程时长、实际帧率下有限差分步长与速度变化、解析导数校验；保留同目标no-op、延迟帧墙钟、同向C1接续、近目标无超调、seek与非法输入。
- 原刚性行距/缓存/复杂字符测试用实际新模型比对轨迹，未削弱.01px容差。旧透明度测试改读AnimatedOpacity目标；329退出生命周期/残影回归保留。
- 最终完整flutter test --no-pub：313通过、1个原有可选图像导出跳过，包含新增景深逐帧断言。最终flutter analyze --no-pub无问题（8.2秒）；10个相关Dart文件格式检查0改动；git diff --check通过（原有LF/CRLF提示保留）。

## 真机profile

设备V2352A，ADB 10CEB70TQE001E2。ARM64 profile，真实MobileLyricsList、2s间奏/2s混合文字与翻译fixture，无音频、Performance Overlay开启；暖机4s、采集30.5s，同时720×1600录屏。为覆盖最长480ms运动，本轮窗口从329的300ms改为600ms，不能直接比较两版P95声称提升。

请求120Hz，显示元数据120.000Hz；实际vsync间隔P95 16.563ms，最大33.104ms，不证明真实120fps。600ms交接窗口288帧：Build P95/最大1.119/6.005ms，Raster P95/最大10.738/12.527ms；窗口Build/Raster均没有超过16.67ms，Raster超过8.33ms有75帧。全段1850帧Raster超过16.67ms仍有17帧，最大26.127ms。

**仅此fixture采样的交接窗口满足60Hz预算，严格120Hz预算失败，全局零掉帧未通过。** 记录原始失败断言，不关闭模糊/放大预算使测试通过。未运行Perfetto或采集GPU显存、功耗、长期温升；进程RSS306,880,512→304,308,224字节不能证明长期内存稳定。软件曲线连续性不是实测观感/满帧证明。

证据目录F:/AGENT/1/test-artifacts/karaoke-330/，含profile-request120.json、display-request120.txt、interlude330-profile.mp4、修复前/最终测试及构建日志。

## 正式Release与真实歌曲

恢复正式包adb install -r -d返回Success，原生versionCode2330且无DEBUGGABLE，真实启动到音乐库，收藏仍146首。系统刷新率再次读取144.0/null；不卸载、不清数据。根据register-generated-program技能，在真实启动后更新既有本地入口，返回ok=true、canonical ID=55597a6477880f94。

真实《其实》复录30秒、720×1600/6Mbps，无音轨：updated330-real-qishi-retry-release.mp4。开始录制前已从0:00恢复播放约1秒，视频0并非音频0。保留先前329同曲前奏视频baseline329-real-qishi-intro-release.mp4作参考，不冒称本轮重新控制字号/状态的严密A/B；按歌曲内容对齐，不按相同视频秒数对齐。

检查330视频17.0–18.25秒的原始帧及100ms序列：间奏圆点收缩消隐同时正文向上，正文进入既有阅读焦点且高亮推进；有限检查未见反向下坠、缺字或裁切。视频1811帧、容器平均60.48fps是编码元数据，**不是应用帧率**，不证明每次换行精确420/480ms，也未以视频拟合确定绝对峰值速度。第一轮录制出现灰色占位大块，原因未定位，不用于观感/A/B结论；复录同播放页完整显示歌词。该偶发采集异常仍是验证限制。

真机片段覆盖中文和前奏；长英文、快慢句、折行与复杂字符主要由fixture及软件回归覆盖，未逐一录制真实歌曲。测试结束保持正式包，《其实》约0:31暂停（release330-final-paused.png），不宣称恢复用户此前精确音频采样点。

## 文件与构建

修改lib/widgets/lyric_normalized_motion.dart、lib/widgets/mobile_lyrics_list.dart；test/lyric_normalized_motion_test.dart、test/lyric_transition_performance_test.dart、test/mobile_lyrics_list_test.dart、test/interlude_animation_widget_test.dart、新test/lyric_phase_motion_test.dart；integration_test/interlude_exit_performance_test.dart仅扩大采集窗口；pubspec.yaml、lib/page/setting/project_changelog.dart、test/project_changelog_test.dart；本记录。mobile_shell.dart本轮未改，原有未提交成果保留。

仅android-arm64 --split-per-abi。正式Release：F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.330-arm64-v8a.apk，53,363,258字节，versionCode2330/versionName0.9.9；ABI仅arm64-v8a，16KiB对齐与v2签名通过。SHA256：422D5B10661CE1F899AA842F19C2AA3D601AAAEA1E96C2C535C0F7804B30415D。

Profile独立fixture target/build-number1330，原生ABI偏移后3330、仅测试用；正式包2330仍按项目约定，不提升发布号掩盖测试包。测试后覆盖恢复Release，不卸载或清曲库；原刷新率144.0/null恢复。

329完整源码及APK已保留，回退/对照在独立目录解压，不覆盖当前脏工作区或以卸载清数据绕过Android降级限制。没有增加永久公开新旧路径开关。

留档F:/临时文件夹/备份/Myune-Music-0.9.9+330-20260926-183213/：完整当前工作区源码含未跟踪文件、正式APK、本记录、有效日志/profile原始数据及有效录屏；排除.git/.dart_tool/build/dist/编译缓存/local.properties。首轮灰块视频保留在证据工作目录，不归入有效视觉证据。
