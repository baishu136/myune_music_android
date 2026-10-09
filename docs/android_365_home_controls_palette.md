# Android 365：主页按键统一磨砂与中性配色优化

日期：2026-10-05。基于实际364脏工作区继续，版本 `1.0.0+365` / `1.0.0-android.365`，ARM64 split versionCode `2365`。保留现有未提交修改，不提交/推送、不创建Release、不清理旧产物。本轮未真机安装或性能采样。

## 实际修改

- 开启“主页禁用主题色”时，顶部排序/查看方式/搜索等操作区、多选退出及操作区、歌单“添加歌曲”按钮使用 `HomeGlassControls`：与播放状态栏一致的 **70%背景不透明度（30%透过）、20%局部模糊**，100%=sigma20，20%=sigma4。直接复用播放栏滤镜，不再新增第三个sigma实例。
- 顶部按钮组24dp裁切、多选退出28dp、歌单添加16dp；只有合成裁切，没有新的Padding、尺寸约束、描边、方向渐变或悬浮边距。按键保留原图标尺寸/触摸区。普通模式滤镜禁用、填充移除，原FAB背景与阴影恢复。
- 按钮组滤镜置于原380/320ms `AnimatedSwitcher`外：进入/退出按钮共用一个局部背景，不对新旧按钮各叠一个滤镜，不新增动画时钟或动态sigma插值。不同区域不共享backdropKey，不引入重叠滤镜错误合并。
- 两个底栏仍保持364原位、原尺寸、全宽矩形；导航仍70%背景/70%模糊（sigma14）、播放栏70%背景/20%模糊（sigma4）。不再为栏内每个图标单独叠加磨砂层；栏内按键继承所在栏的磨砂，选中状态更新中性配色。

## 配色依据

红测确认：364只替换ColorScheme，但TextTheme仍保留由封面seed生成的粉色偏色，IconTheme亦未显式中性化。365只在主页中性作用域中替换前景色，保留字体、字号、粗细和鼠标/交互样式：

| 角色 | 浅色 | 深色 |
| --- | --- | --- |
| 主页背景 | #FFFFFF | #121212 |
| 按键/播放栏玻璃底色（alpha=.70） | #FFFFFF | #202020 |
| 主文字/操作图标 | #202020 | #F2F2F2 |
| 次级文字/图标 | #595959 | #BFBFBF |
| 选中容器 / 前景 | #DADADA / #202020 | #3B3B3B / #F2F2F2 |
| 主色 | #303030 | #E8E8E8 |

保持浅色白色容器，不恢复363的多级灰底、方向渐变或浮动卡片。禁用按键前景alpha=.38，保持可用/不可用区分。图标主题只覆写前景色，保留原鼠标行为及其他配置。

对比度测试基于真实70% alpha合成后的底色，而非假设不透明白/黑：黑、白、粉、黄、青及灰蓝六组背景下，主前景至少4.5:1、次级前景至少3:1；选中容器/前景至少7:1。这是软件颜色计算验证，不是所有复杂图片/抗锯齿文字的视觉验收保证。

## 兼容边界

- 保留歌单/主页滑动、顶部原衔接动画、自定义图片/封面跟随兼容；路径、优先级、遮罩及模糊保存值不变。
- 不更改全局主题或播放route，不更改歌词/背景引擎、字号上限40、流体速度与播放器逻辑，不增加用户设置。
- `HomeGlassProfile`始终只缓存sigma14与sigma4两实例；按钮使用同一个sigma4对象。新增局部BackdropFilter有实际合成开销，本轮没有GPU、120Hz、功耗实测，不能宣称性能提升或满帧。

## 验证

- 修改前前景偏色红测失败：`controls-365/baseline-red.txt`；测试编写阶段误将Stateless IconButton当作StatefulWidget的失败日志保留，随后改为Element身份/点击验证。
- 相关29项通过；最终全量Flutter **488项通过、1项既有跳过、0失败**。
- 覆盖按键背景alpha、滤镜复用、开关前后连续15个16ms采样帧的尺寸/位置/Element不变、点击、多选切换时新旧Row并存而滤镜不翻倍；延用八组底栏尺寸/亮度/字号/安全区测试、配置恢复与播放route隔离测试。
- 软件PNG位于 `F:/AGENT/1/test-artifacts/controls-365/software/`，生产主题/磨砂组件加载MiSans与MaterialIcons，深浅×纯色/合成条纹四组。内容为测试组合（示意显示添加按钮），不是完整MobileShell或真机截图；检查配色、透出、控件边界及原位底栏。
- 静态分析无问题（30.9s）、工具6项单测通过、`git diff --check`通过。只读对照364源码ZIP确认：主页/歌单切页、完整MiniPlayer与播放页、背景策略、设置、逐字/流体及原生构建配置保持原样，详见 `scope-verification.json`。
- 仅ARM64 Release构建成功（Gradle 101.4s）。APK全条目CRC、必需原生库、仅arm64-v8a、原生库压缩及ELF LOAD ≥16KiB、APK签名v2、`zipalign -c -P 16 4`通过；正式包名 `com.myune.music`、versionName `1.0.0`、versionCode `2365`确认。
- 未重新执行原生行为测试，无原生行为变更；未安装手机、未执行Profile/Perfetto。软件PNG不代表实际GPU模糊效果或满帧验证。

## 留档

主要修改：`lib/mobile/mobile_shell.dart`、`lib/widgets/home_glass_surface.dart`、`lib/theme/home_theme_scope.dart`，版本/更新记录、主题/磨砂测试；新增 `test/home_glass_controls_test.dart`，AGENTS及工作目录索引同步。

- 修改前源码：`dist/Myune-Music-1.0.0-android.364-source-baseline-20261005.zip`（676项）。
- ARM64 Release：`dist/Myune-Music-1.0.0-android.365-arm64-v8a.apk`，32,359,876 bytes（30.86MiB），SHA256 `1CFE85E8584D69E92821C17ECADE8434533C3BD2034524FC747C1DB2D2971CA5`。
- 当前完整源码：`dist/Myune-Music-1.0.0-android.365-source-20261005.zip`（678项）。与364基线相比仅本轮10个既有文件修改、2个新增文件，无删除；逐文件内容对应工作区及ZIP CRC校验。
- 证据：`F:/AGENT/1/test-artifacts/controls-365/`。
- 备份：`F:/临时文件夹/备份/Myune-Music-1.0.0+365-20261005/`，原件/副本逐文件SHA256核对。

此前361–364源码、APK和测试证据全部保留。源码包含工作区现有跟踪及未跟踪成果，排除缓存及敏感资料。签名沿用原debug signing配置，不自动换钥。
