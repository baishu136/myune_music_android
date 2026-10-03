# Android 346：流体光场与连续换色

日期：2026-10-03。基线为当前脏工作区345，不回退其歌词、歌单及全屏切歌成果。

## 实际问题和修改

- 四个色域中心原为对角线排列，横向幅度仅0.16–0.18。改为分散锚点，两个轴0.30–0.34的独立漫游；默认时钟下单轴约21–31秒，FFT仍仅改变平滑速度包络。
- 原先只有单层坐标弯曲，改为两层低空间频率嵌套域扭曲。不叠加高频纹理，保留静态亚色阶IGN抖动，避免重引263版的周期干涉纹。
- 原先归一化平均四色，改为独立暗底与四色Screen光场，场强平方保留局部色彩。`exp(-pow(d², .70)*1.85)`使光斑边缘柔和。更正反向smoothstep未定义的边界顺序。
- 色彩分类增加无色系分支，不再给黑白或单一色相封面补入主题色。鲜艳色饱和度上限.92；暗色不强制提亮。底色和glowStrength作为调色板元数据缓存，而非逐帧分类。
- 真实《Light Mellow》封面进一步暴露“先选六色，按色相排序，再取前四色”会丢掉粉红/紫色的错误。四个Shader槽先独立完成色彩距离选择，再排序；保留公开三至六色选择函数兼容性。新增六色封面测试先复现失败、修复后通过。
- 鲜艳封面选择时增加真实饱和度优先项，防止灰色脸部/阴影占满色槽；原始饱和度低于.20不强制增色。否则仅改六选四顺序仍可能由色彩距离偏置选入灰蓝而漏掉粉红，回归测试覆盖了这两层问题。
- 切歌650ms五次平滑插值。此前Shader使用五次曲线，而控制器中途快照使用线性进度；现在当前颜色、连续重定向及离页快照都使用同一包络，连切不跳回错误颜色。
- 封面解码至不超过64×64；RGBA读回和4096桶统计有界，统计放在worker isolate，透明填充不计入底色。显式释放Codec/Image；保留64条LRU、请求去重，clear后旧异步结果不回填。
- Painter复用Paint和尺寸对应Rect；仍单次drawRect，无新增纹理或saveLayer。自动档上限60Hz，流畅档上限120Hz且按屏幕刷新率限帧，省电24Hz保留；5%调度容差避免时间戳取整造成隔帧丢更新。
- 保留后台/被覆盖路由/TickerMode/减少动态效果立即停止Ticker和FFT监听的语义；保留900ms前台Surface恢复保护。路由Listenable过渡结束时补发Shader/取色准备，避免因上一代请求取消而一直回退。

## 文档参考的边界

检查了用户提供的`salt player1.mp4`至`4.mp4`的0/20/40秒画面：彩色分布大范围迁移，暗蓝/暖红/黑白影调有明显差异。参考资料的数学反推不等于已知Salt内部实现，也不宣称1:1还原。

没有直接复制示例的额外uTime×.45（会在现有时钟下把周期进一步拉长）、反向smoothstep、所有暗色最低提亮，或给黑白封面生成冷暖伪色。650ms仅用于切歌换色，不修改播放器或歌词时序。每帧不做封面分析；Dart托管Paint/Rect复用不等于引擎内部零分配。

Shader/Uniform遵循Flutter官方Runtime Effect约定：https://docs.flutter.dev/ui/design/graphics/fragment-shaders 。目标尺寸解码API说明：https://api.flutter.dev/flutter/dart-ui/instantiateImageCodec.html 。

## 验证

- 全量Flutter测试394通过、1项既有跳过；静态分析无问题。
- 新增`test/fluid_background_regression_test.dart`：黑白不引入伪色、暗蓝保护、鲜艳色保留、实际显示色的连切连续性、650ms完结、60/90/120Hz调度、后台冻结及恢复、缓存失效/去重、有界LRU。
- 使用真正FragmentProgram渲染RGBA验证大面积运动、200π相位回绕连续性和无色系输出；并调用生产Painter覆盖尺寸复用/无效尺寸。不是只断言Shader文本或某个常数。
- 新增独立Profile基准`integration_test/fluid_background_performance_test.dart`，全屏使用生产组件及相同四组生成封面；生成样本不是实际专辑封面，FrameTiming的Raster耗时不是独立GPU Shader耗时。
- 真机：vivo V2352A / Android15，独立包`com.myune.music.fluidbench`，Profile模式，1080×2400 Flutter Surface，4秒预热、每组7秒。`display.refreshRate`报告120但实际display mode及帧间隔为60Hz（约16.6ms），因此不宣称120fps实测通过。

| 相同生成封面 | 345 Raster p95 ms | 346最终 Raster p95 ms | 346最终 Build p95 ms |
| --- | ---: | ---: | ---: |
| 粉红/青绿/暖黄 | 3.305 | 2.273 | 1.473 |
| 黑底暗蓝 | 2.877 | 2.191 | 1.491 |
| 暖红/琥珀 | 2.556 | 2.147 | 1.423 |
| 黑白 | 2.694 | 2.220 | 1.603 |

- 345：1693帧；346最终：1690帧，Raster最大5.418ms，两者均无Raster超过16.67ms。346最终RSS 260608000→259481600字节（减少约1.07MiB），短时未见持续增长；不能据此保证长时GPU内存或功耗。
- 初始参数含录屏采样1692帧，Raster p95 2.010–2.555ms；检查画面后发现黑色补槽压低了冷光/暖光，最终暗色采用真实现有辅色补槽，暗色光强按黑白.28、暗蓝.55、暗且鲜艳.70分类。期间另有1690帧不录屏结果（`current-346-final.json`）；真实封面再发现六选四漏色后重新构建及采样，最终上表使用`current-346-verified.json`，不是早期结果。
- 345录像启动于安装等待阶段，未覆盖基准画面，不能作为视觉对照（保留并标注`profile-345-install-wait.mp4`）。345/346最终不录屏性能数据可按同一基准比较；只是单设备短时结果，不概括所有机型或将全屏Raster等同GPU Shader<1.2ms。
- 346 Release构建及真机覆盖安装、实际启动通过，曲库与设置保留。APK仅ARM64，32578266字节（31.07MiB），SHA256 `B2277826B4C9CA971D8BFBEF4BA07C23F95357C08F0CBE056C127BE249DE76AA`；v2签名和16KiB ZIP对齐通过。
- APK独立ABI/ELF/资源审计通过。与345的严格资产不变检查按预期报流体Shader变化；补充资源哈希对比确认只有该Shader改变，其余13个字体/图片/Shader资源相同，没有以丢资源方式换取性能。
- 真实封面视觉录屏另保留Release暗蓝封面及彩色封面检查。没有完成四张真实专辑的新旧同时间长录屏、Perfetto独立GPU计时、120Hz实呈现和功耗测量；参考外观并非1:1还原。
- 真实Release样本为《Best Friends》Dawn FM暗蓝封面和《10cmヒール》Light Mellow彩色封面；六选四修复后的全屏歌词背景最终录屏为`release-verified.mp4`及其0/8/16秒联系图，粉红/青绿等色域保留并迁移。此前`release-vivid.mp4`是发现漏色的中间参数，不作为最终视觉结果。
- 包体审计脚本6项测试通过；没有改动歌词组件、播放器时钟或既有歌词滚动算法。全屏背景基准的帧预算通过不等同于345记录中未通过的歌词压力满帧验收现在也通过。

证据位于 `F:/AGENT/1/test-artifacts/fluid-346/`：`baseline-345-run1.json`、`current-346-verified.json`、历轮构建/测试/分析日志、签名及资源审计、参考抽帧和录屏。独立基准克隆只改包名/测试入口，最终核心流体文件与当前项目一致。

## 文件与回退

改动：`shaders/fluid_background.frag`、`lib/models/fluid_background_state.dart`、`lib/services/artwork_palette_cache.dart`、`lib/services/fluid_background_controller.dart`、`lib/widgets/playback_background/fluid_background.dart`、`fluid_background_painter.dart`及上述测试、版本与更新说明。

345完整基线：`dist/Myune-Music-0.9.9-android.345-source-20261002-210941.zip`。回退请从该快照解压到新目录对照，不覆盖现在的脏工作区。无新增用户设置或常驻旧算法分支。

346 APK：`dist/Myune-Music-0.9.9-android.346-arm64-v8a.apk`。最终源码及测试证据留档到 `F:/临时文件夹/备份/Myune-Music-0.9.9+346-20261003/`。没有Git提交/推送。
