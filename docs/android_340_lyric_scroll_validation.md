# 340：歌词滚动最终验证与景深缓存隔离

2026-10-02。本次用户请求以338为基线，先完成339统一滚动及CPU降峰，再根据真机复测补充340的模糊结果隔离和空歌词防护。339已单独构建、安装和留档，不覆盖旧产物；完整实现原因、339的好/坏采样均在android_339_shared_lyric_scroll.md中保留。工作区其他未提交成果保留，mobile_shell.dart未修改。

## 最终方案

1. 逐字和非逐字采用同一个默认字体自适应列表弹簧；弹性开关使用同一个行脉冲及共享帧时钟。打开/关闭逐字不再更换驱动、清空速度或重启焦点属性。
2. 两模式都移除行内AnimatedSlide，列表或弹性波唯一驱动行级垂直位移。普通焦点属性沿用默认620ms节奏；弹性模式共用420ms。逐字高亮、760ms媒体时间微浮和240ms退出保持原有规则，不提前真实歌词边界。
3. 连跨多行按实际距离判定，1.5视口内保留完整行程和速度继承，不先跳过可见前半程。明显远距仍有界处理；明确seek立即定位。退出保留上一实际播放行姿态，手动浏览仍独立停追踪并3.5s回中。
4. 当前、退出和下一行才保留逐字蒙版，远处行采用完整静态段落，翻译弱化且无逐字运动。滚动中的下一行构建安排在绘制后宏任务，预热、代际检查、取消和释放保留。静态行不再为每个字符复制完整双语Picture；首次进入/未命中seek仍可能同步构建一次。
5. 运动期间用离散缓存景深阶梯，焦点立即无模糊。340额外将**模糊结果**包在动画Opacity/Scale下方的RepaintBoundary，原内层边界只隔离文字源。结果可独立复用，不新增滤镜实例或无界全曲缓存。引擎光栅缓存由Flutter管理，不能据结构断言GPU提升百分比。
6. 修复339边界判断读取空_itemOffsets的错误：先验证索引及scroll clients，再读取坐标。新增空歌词0→-1→0测试先失败后通过，防止错误边界重新替换为灰色ErrorWidget。

## 最终自动化验证

- 完整flutter test --no-pub：**358通过、1个原有可选导出跳过**；analyze --no-pub无问题，8文件格式检查0改动，git diff --check通过，6项APK审计工具测试通过。
- 60/90/120Hz×普通/弹性配对测试比较逐字开关的逐帧实际绘制中心，包含跨两行、150ms再次重定向及中途开关；.01px容差，没有把固定常量当作运动连续证明。
- 下一行蒙版在边界首帧不构建，后续只构建一次；远处行最多两个初始逐字缓存；退出取消Timer并释放Picture。新增测试确认模糊结果边界位于本行FadeTransition/ScaleTransition下方。
- 原高亮像素、透明度合成、复杂文字回退、字素/连字/折行、翻译静态、倍率/暂停、正反seek、缓存字体/宽度/DPR失效测试保留并通过。没有改karaoke_paint_cache.dart或媒体时钟公式。

## 真机性能：实测与限制

设备Vivo V2352A，ADB 10CEB70TQE001E2。ARM64 **Profile**，隔离com.myune.music.karaokebench，不接触正式曲库。相同240行中/英/复杂字形+双语折行，28/W800左对齐，模糊开启；行间隔循环1000/180/0/0/180/220/1400/180ms，正常时间推进产生连跨3个索引。4s预热、36s测量，四个9s阶段：逐字普通/非逐字普通/逐字弹性/非逐字弹性。独立可控媒体时钟，**没有音频**，不是完整播放器同曲人声A/B。338与340均720×1600/5Mbps连续录屏。

| 同场景有录屏指标 | 338 | 最终340 |
| --- | ---: | ---: |
| 全样本帧数 | 2162 | 2162 |
| Build P95/最大 ms | 3.453 / 30.932 | 2.722 / 11.335 |
| 切行650ms窗口Build P95 ms | 3.818 | 2.815 |
| Build >16.67ms帧 | 1 | 0 |
| Raster P95/最大 ms | 10.717 / 68.115 | 12.225 / 60.644 |
| 切行Raster P95 ms | 11.284 | 12.712 |
| Raster >16.67ms帧 | 8 | 8 |
| 最长连续超预算帧 | 2 | 2 |
| 全样本vsync间隔P95/最大 ms | 16.580 / 66.290 | 16.581 / 49.720 |

CPU换行峰值有下降证据，轨迹配对测试确认滚动兼容性；**总Raster P95未改善，仍有实测超预算帧，未达到完全零掉帧/所有帧<12ms**。最终逐字弹性阶段Raster P95 9.670ms、最大15.659ms，539帧未超60Hz预算；逐字普通阶段P95 13.738ms、最大18.793ms，539帧有3帧超预算，不能隐去。非逐字弹性阶段仍有60.644ms的光栅峰值，说明残余GPU尖峰并非仅在逐字路径中。

339无录屏复测出现Raster P95 16.387ms、96帧超预算；加入结果边界的隔离实验为11.673ms、10帧超预算，但这不是受控的单变量GPU因果证明，仍受缓存/系统负载影响。两轮结果及旧版复测全部保留于karaoke-339，不只挑最佳采样。340最终生产源码与Profile复制件的mobile_lyrics_list.dart SHA256一致。

显示接口报告120Hz，但实际SurfaceFlinger/采集节奏约60Hz；不宣称真机120fps。RSS340为321,974,272→339,128,320字节，短时观察而非GPU显存/功耗/长期无泄漏。未获取Perfetto、GPU频率的受控对照、持续温升或多机型结果。

按原始视频帧解码6/10/23/28秒各1.3s、不补帧，338/340缩小歌词视口均未发现均差<.01；接触表检查中文、多行英文和翻译未见新重影、整行灰块或高亮裁切。不能由有损编码/部分窗口证明全视频无冻结，视频开头没有严格逐帧对齐。

## 正式安装与产物

ARM64 **Release**构建成功：F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.340-arm64-v8a.apk。

32,552,650字节（31.04MiB），SHA256 **3DBC050886B4DD305CEB885FA7175D0CF1F7EF5BC7FD2D1FEAFB58E7CBDF6098**。versionCode2340，min24/target36，无DEBUGGABLE，仅arm64-v8a；v2签名、zipalign -P16、CRC、完整字体/解码库、原生压缩及ELF16KiB审计通过。Profile对照包也仅ARM64。

正式包adb install -r从339升级340，成功启动至原音乐库，自定义图片背景及当前A Lonely Night保留，firstInstallTime仍2026-09-26 20:36:54。正式包没有执行uninstall、清数据或flutter drive。真实Release播放页另录A Lonely Night歌词页25s（开启逐字的英文折行、既有流体背景/沉浸模式），抽查8秒图像未见新重影或高亮裁切；没有FrameTiming或旧包同曲音频对照，不能据其宣称全播放器帧预算/人声同步已测通过。测试后暂停于64.848秒，详见formal-final-media.txt。登记技能更新既有入口55597a6477880f94至340，未新增重复快捷方式。

本轮修改文件：lib/widgets/mobile_lyrics_list.dart；pubspec.yaml；lib/page/setting/project_changelog.dart；test/{mobile_lyrics_list,synthetic_karaoke,lyric_phase_motion,lyric_transition_performance,project_changelog}_test.dart；新增test/lyric_scroll_compatibility_test.dart及339/340记录。没有新增用户设置或修改无关页面。

证据：F:/AGENT/1/test-artifacts/karaoke-340/（最终JSON/录屏、338对照副本、相同fixture Profile包、连续帧接触表、正式播放录屏、软件验证/构建/审计/安装日志）；339中间结果、失败回归及复测在F:/AGENT/1/test-artifacts/karaoke-339/。

339留档：F:/临时文件夹/备份/Myune-Music-0.9.9+339-20261002-125320/。340留档：F:/临时文件夹/备份/Myune-Music-0.9.9+340-20261002-131200/，完整当前源码（含未跟踪成果）+正式包+记录+验证/对照产物；排除.git/.dart_tool/build/dist/.gradle/.cxx/target编译缓存及local.properties。回退或对照在独立目录解压338/339，不整库覆盖当前脏工作区，不卸载正式包绕过版本降级。

验证结束只移除本轮隔离测试应用com.myune.music.karaokebench；其全部APK和报告可从留档恢复。正式com.myune.music保持2340且用户曲库不清理。
