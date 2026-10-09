# Android 362：字号40、封面关联流体与中性主页

日期：2026-10-05；基于实际未提交的361工作区继续开发，保留其歌词、背景和测试成果。显示版本 `1.0.0-android.362`，ARM64 split versionCode `2362`。本轮不提交Git、不创建Release、不清理任何留档。

## 实际修改

- 歌词字号上限从36提高到40：普通/全屏歌词和桌面歌词共用上限，保存值、预览及恢复均受约束；不改默认字号，不强制覆盖既有用户设置。
- 流体时间系数 `.065 → .0975`，巡航速度提高50%，完整周期约64.44秒（原96.66秒）。保持实际可见时间、后台冻结、质量档位调度和整周期回绕语义，音频能量仍只影响空间运动幅度。
- 取色先聚合相邻18°的真实颜色家族、按占比为主选择主斑，副斑兼顾占比和色相区别、至少占有效样本3%；不再把极小互补色放大到半屏，也不把低饱和封面强制拉到鲜艳范围。家族原色相锚点固定，最强实际RGB色度代表其颜料，避免累计合并漂移。明度>.85的彩色纸张/肤色高光不占据双斑角色；它们仍可参与原选色辅助槽，只有无色高光被原有过滤器彻底剔除。真实粉色、暖金、青绿打印仍保留。只有一个有效颜料家族时保留原辅助颜色，不复制主色挤掉其余封面信息。
- 维持原 `base → ambient → blob1 → blob2` 分层遮罩mix，不恢复加法叠光。色斑两侧分离、中心遮罩弱时，暴露地色由真实主斑颜色最多30%的柔和底色补足；不画中央黑圆/白光，不增加额外模糊层。遮罩覆盖强时该补色自然消退，实色斑核心不受影响，纯黑封面仍黑色。
- 设置→个性化新增“主页禁用主题色”，默认关闭、可持久化。开启时：浅色主页和底部导航/播放状态栏白色且不透明；深色主页#121212，状态栏/导航采用不透明黑灰阶；禁用主页封面和自定义图片背景的实际显示，但不清除其保存配置。关闭恢复原配置。中性主题作用于主页子树，不修改全局动态主题，推入的播放页继续原主题。
- 新 `lib/theme/home_theme_scope.dart` 仅缓存最近一套中性ThemeData，亮/暗ColorScheme各生成一次；保持固定Theme/Builder包装，避免切换开关重置页面State。取色全部仍为每封面缓存阶段工作，不进入逐帧绘制。

## 验证与证据

修改前红测留档 `test-artifacts/theme-362/baseline-red.txt`：旧字号上限、主色偏离、微小互补色三个断言失败。保留全部后续失败日志，包括旧36预览断言和高光辅助色兼容性失败；修复后重新验证。

新增覆盖：设置默认/持久化、不覆盖旧配置、浅/深纯色与栏位alpha、切换不丢页面State、播放route隔离、设置UI操作、低饱和主色保真与1.5%噪点不主导。现有预览测试现实际检查40px。Shader测试使用生产FragmentProgram：24相位、每相位9个中央位置验证亮色测试样本不出现近黑空洞，并检查纯黑样本保持黑色、实色核心不变、独立分层公式一致、循环/切歌连续性。

- 全量Flutter测试：最终477项通过，1项既有跳过。
- `flutter analyze --no-pub`：无问题；工具Python6项测试通过；`git diff --check`通过。
- 软件渲染检查：真实Shader PNG在 `F:/AGENT/1/test-artifacts/theme-362/software/phase-{0,24,48,72}.png`。已逐张检查大范围衔接、中央无近黑圆洞；为合成颜料样本，不冒称真机截图或所有专辑封面表现。
- 仅构建ARM64 Release；APK通过ABI/ELF/CRC审计、v2签名及16KiB zipalign检查，aapt核对包名/版本。签名仍为项目现有debug signing配置，不擅自换钥。

本轮没有覆盖安装、真机录屏或Profile/Perfetto采样。软件Shader验证与测试通过不等于GPU性能/120fps实测；不承诺任意暗封面都亮色或交界绝无降彩。纯黑/深色封面的真实暗色保留是预期行为。

## 文件与留档

生产：`settings_provider.dart`、`tabs/theme_settings_section.dart`、`theme/home_theme_scope.dart`、`mobile/mobile_shell.dart`、`models/fluid_background_state.dart`、`services/artwork_palette_cache.dart`、`shaders/fluid_background.frag`，版本/更新记录同步。

测试：`home_theme_scope_test.dart`、`fluid_artwork_fidelity_test.dart`、`lyric_display_settings_test.dart`、`settings_detail_pages_test.dart`，以及现有流体模型/Shader/版本测试。此前361未提交歌词修改完整保留，未在本轮改动。

- 修改前源码：`dist/Myune-Music-1.0.0-android.361-source-baseline-20261005.zip`（667项）。
- APK：`dist/Myune-Music-1.0.0-android.362-arm64-v8a.apk`。
- APK大小：32,359,028 bytes（30.86MiB）；SHA256：`28C13AD128AA9974F5659D0E1BF302DB92142CD55AA4E1F329C920E4DC3235A6`。
- 当前源码：`dist/Myune-Music-1.0.0-android.362-source-20261005.zip`，包含现有跟踪及未跟踪源码，排除本机缓存/签名敏感资料；逐项SHA256与当前工作区核对、ZIP CRC核验。
- 全部日志、失败证据、软件PNG：`F:/AGENT/1/test-artifacts/theme-362/`。
- 备份：`F:/临时文件夹/备份/Myune-Music-1.0.0+362-20261005/`；保存dist、build输出、记录和本轮全部证据，逐文件SHA256核验；详见 `artifact-manifest.json`。

361原产物与备份继续保留；源码ZIP对比若发现文件删除即停止归档核验，不通过重置工作区恢复。
