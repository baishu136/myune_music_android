# Android 361：大范围柔和色块与逐字运动衔接

日期：2026-10-05。基线：实际 `1.0.0+360`、Git `b96a28c`；本轮递增到 `1.0.0+361`，正式 ARM64 split versionCode 2361。没有提交或推送 Git，也不创建 Release。旧历史清理不延续；本轮全部新产物和失败证据保留。

## 查明的问题与实现

- 360 背景已是地色/环境/双色斑的分层 mix，不是加法。原按距离平方 smoothstep 的衰减把大部分颜色变化集中于较窄环带。改为按椭圆归一化半径计算五次 smootherstep：核心半径 .20，双色斑外半径 1.20，环境外半径 1.50。保留原物理椭圆、图层顺序、颜料、96.66 秒慢周期、暗角/dim、抖动及 48-float ABI；不新增 GPU 模糊层、不改取色算法。
- 实际移动端路径是 `mobile_lyrics_list.dart` 的 part `karaoke_paint_cache.dart`。`I` 并没有单独的停止分支，空白也早已不参与字素时间分配；真实问题是普通英文单空格会硬断开运动跟随，加上原对称五次曲线初段很慢，使短词/单字母重新从静止起立。不能据此声称所有 `I` 停顿都来自代码：有真实长拖音的 `I` 仍应慢扫。
- 只对相邻 Latin 字素跨一个普通空格/NBSP/窄 NBSP 的运动建立局部桥接。同一物理行、同方向、正序时间，间隙不超过相邻原始词元较短时长的 35%，且最多 80ms；多空格、标点、折行、真实长停顿仍断链。汉字/假名既有 359 短间隙规则保留。没有改变真实高亮起止、既有 visual lead-in 或词元内估算。
- 三阶牵引从 `[.24,.12,.05]` 调为 `[.30,.16,.07]`。仍仅读前驱自主运动，不递归读跟随；剩余行程连续融合不使用硬 max。预牵引理论最大从原行程的 36.464% 调到 45.316%，每一级小幅增加，而非恢复 355/356 大幅下沉归位。
- 正常上浮保留 `.055 × shaped lineHeight`、1.2–4px 及 **760ms 媒体时间**。默认曲线换为 `t²(6−8t+3t²)`：起点速度为零，终点速度/加速度为零，前段比旧对称曲线更有响应，末段仍柔和缓冲。退出仍是原 240ms 包络；翻译保持静态，列表三种滚动效果不改。
- 估算局部字素节奏小于 180ms 时允许一次受限超调，低于 60ms 达到最大原高度 10%（不超过额外 .4px）。强度在 60–180ms 之间连续渐变；窗口为基础运动的 .55–1.35，使用 `64[x(1−x)]³` 单峰 C2 脉冲。最多约 1026ms 媒体时间完全回稳，2x 对应约 513ms 实际时间；慢字/拖音不超调。超调不传给后字，不逐帧积累，暂停、倍率/seek 沿用媒体时钟的确定性语义。
- 节奏/断链/超调幅度只在布局阶段缓存；paint 仍写入复用 typed buffers，无新增逐帧排版、字形图片或临时 Map/List。保留完整字形/下伸部、复杂文字回退及一次透明度合成。

## 自动验证

旧 360 上先复现三个失败：`I` 自主起点前实际绘制 dy 为 -0.0、跟随增幅未发生、快字不能超调。新的背景标量 oracle 在旧实际 Shader 上也失败；修改后通过。

- 最终全量 Flutter（含补强后的生产 `I` 60/90/120Hz、0.75/1/1.5/2x 采样）：470 通过、1 项既有截图导出跳过。原始结构化结果保存在 `full-tests-final.jsonl`，末条 `success=true`；最终分析结果在 `analysis-verified.txt`。部分早期PowerShell Transcript未完整收录原生子进程stdout，保留但不当作完整测试输出。
- 静态分析无问题；工具 6 项测试通过；`git diff --check` 通过。
- 新测试覆盖三阶边界/不递归、受限超调回稳、所有倍率下帧间位移/速度变化、暂停与正反 seek/直接定位一致、局部英文间隙限幅、原始高亮不变及缓存复用。原下伸部、翻译、复杂字符、折行和列表滚动回归继续通过。
- 实际 FragmentProgram 像素与独立分层径向标量公式对照误差≤2个 8-bit 色阶；保留两个颜料核心、元数据不新增光源、黑白/单色及周期回绕等回归。
- 修正样本导出器：DisplayList 在 draw 时快照 Uniform，不能在录制后改相位。最初四张同相位的失败样本保留在 `baseline-software/`、`current-software/`，**不作为四相位证据**；正确四相位在 `*-software-corrected/`。旧 Shader 只为导出对照通过限定补丁短暂恢复，导出完成即恢复新实现，无 Git reset/checkout。

更宽的互补色交界会增加混色区域，不能承诺所有像素都保持高饱和度或“零灰”。固定颜料/静止轨道网格平均 HSL 饱和度约 .538（360 原记录 .577）；这是有意放宽交界的技术样本，不是《Cupid》封面实测或 GPU 性能数据。

## 真机验证与限制

当前设备 vivo V2352A / Android 15，正式应用测试前 versionCode 2360。已获本轮测试授权。使用独立包名 `com.myune.music.benchmark` 的 ARM64 Profile fixture，不替换正式曲库；Gradle 可选 `myuneBenchmarkApplicationId` 只接受该包名且只允许 Profile 任务，正式包名/签名不变。

对照 fixture：生成粉红/青绿/暖黄封面，逐字中文、含 `I` 的长英文、混排、复杂字素、折行及静态翻译；四档倍率、前后 seek、拖拽浏览；保留背景、模糊及 Performance Overlay。不是实际音频/完整播放器验收。

360 有效 Profile 采样：实际约 60Hz，1275 帧，Build P95 1.796ms、Raster P95 10.574ms；Build 超16.67ms 1帧、Raster超16.67ms 8帧，Raster最大25.273ms。RSS约322.3→412.9MB，包含首次词形/字体缓存等，不能据此声称长期内存稳定。

首次基线驱动因 DDS 连接失败，保留失败日志；使用 `--no-dds` 且限定重启测试应用后才取得上述数据。新版 Profile 首次安装后启动白页、未取得 VM service 或有效采样；限定重启仍未取得数据，已停止该轮挂起的驱动并保留 APK/白页截图/日志。**不得用旧版数据代替新版，不宣称新版真机满帧或性能提高。** 正式覆盖安装首次返回 `INSTALL_FAILED_ABORTED: User rejected permissions`；用户再次确认后 `adb install -r` 成功，复核正式versionCode2361、versionName1.0.0，应用成功进入音乐库/播放页，未卸载或清空曲库。

新版Release视觉抽查：The Weeknd《Is There Someone Else?》，原保存设置逐字开启/范围全部、默认滚动、W800、歌词模糊及沉浸开启，未改设置。实际显示调度约60Hz，1080×2400无音轨录屏两段44.95s/29.95s（包含暂停准备时间），检查了抽帧概览及连续帧样本。原始视频为 `release-lyrics.mp4` / `release-lyrics-vocal.mp4`，设置截图/XML与启动截图也保留。未见灰块/缺字；这只是有限英文片段抽查，不是全语种、120Hz或完整帧预算验证。第一段出现短暂系统音量面板，保留且不作为无干扰的性能对照；没有同曲旧版Release配对。结束时歌曲暂停于约2:21，留在封面页；本地既有ADB启动入口按启动登记技能复核更新，未复制或发布项目。

目前没有新版完整播放页的 Profile/Perfetto、120Hz呈现、同曲新旧配对连续录屏或 GPU/功耗证据。单元测试的公式连续、软件渲染与有限Release抽查不是全面主观观感或满帧验收。

## 包与留档

正式 APK 仅 ARM64 Release：32,313,232 bytes，包名 `com.myune.music`、versionName `1.0.0`、versionCode 2361。原生压缩/ELF/ABI/CRC审计、v2签名及16KiB ZIP对齐通过；签名仍沿用项目 debug key，没有改密钥。

SHA256：`1A1E81D84F2E58DC04F33998A3B2754A35FD52768C257E7B5F6DB4611821012E`。

- 正式包：`dist/Myune-Music-1.0.0-android.361-arm64-v8a.apk`。
- 源码：`dist/Myune-Music-1.0.0-android.361-source-20261005.zip`。
- 修改前完整665文件备份：`dist/Myune-Music-1.0.0-android.360-source-baseline-20261005.zip`。
- 两个独立 ARM64 Profile 对照 APK：`dist/Myune-Music-1.0.0-android.360-motion-baseline-arm64-profile.apk` / `361-motion-arm64-profile.apk`（后者完整文件名前缀同前者）。
- 原始证据/失败日志/实际 PNG：`F:/AGENT/1/test-artifacts/motion-361/`。
- 完整副本：`F:/临时文件夹/备份/Myune-Music-1.0.0+361-20261005/`。包含上述源码、APK、记录与全部证据；最终逐文件SHA256及ZIP CRC核对。

内部运动对照：配置 `curve=smoothTop`、`followerWeights=[.24,.12,.05]`、`fastOvershootFraction=0`、`maxWordFollowerGap=Duration.zero` 可恢复旧运动规则；完整360源码另存ZIP，新目录解压对照，不覆盖工作区。没有增加公开设置或长期重复生产引擎。
