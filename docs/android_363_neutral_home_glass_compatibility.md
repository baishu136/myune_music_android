# Android 363：中性配色兼容主题配置与局部磨砂玻璃

日期：2026-10-05。基于实际362脏工作区继续，保留361/362未提交成果。版本 `1.0.0+363`，显示 `1.0.0-android.363`，ARM64 split versionCode `2363`。不提交/推送、不创建Release、不清理历史产物。本轮未安装真机。

## 问题与兼容处理

362把“主页禁用主题色”同时用于阻止自定义图片及封面背景的显示，与用户希望只禁用主题配色的意图冲突。本轮拆分背景与配色：

- `home_background_policy.dart` 只读取原图片路径/启用状态和封面跟随配置，完全不依赖配色开关。移动端实际主页使用该策略设置背景和透明Scaffold；原遮罩、模糊参数原样传递。
- 图片/封面优先级、保存路径、遮罩强度、模糊程度及播放页配置不变；保持原“封面跟随优先、无可用封面时回退自定义图片”规则。
- 无主题背景时浅色仍为纯白主页、深色#121212；有背景时背景按原配置可见。关闭禁用配色开关还原原主题。默认仍关闭，不新增第二个质感开关。
- 仅主页子树使用独立中性Theme及`HomeChromeStyle`扩展，不改全局ThemeProvider，也不把磨砂效果传入播放route/其他新页面。

## 独立配色与质感

- 浅色主色#303030、主文字/图标使用中性onSurface，主页白底，容器#FAFAFA / #F6F6F6 / #F0F0F0 / #E8E8E8分层。
- 深色主色#E8E8E8、白灰文字、背景#121212、黑灰容器#161616～#282828，选中胶囊#393939。
- 保留现有字体/字号，文本及图标颜色改为中性，避免沿用原封面色的微弱染色。
- 中性模式迷你播放栏、底部导航、顶部操作按钮组、多选关闭/操作区、添加歌曲按钮，以及平板导航使用局部磨砂。20dp卡片圆角，顶部按钮胶囊28dp，添加按钮16dp；薄描边和灰阶方向渐变保证层次，不叠加发光或全屏模糊。
- 浅色面板渐变 `#EFFFFFFF → #D8F4F4F4`，深色 `#E02A2A2A → #DC161616`；按钮填充略透。玻璃半透明仅作用于这些局部区域，不修改背景遮罩配置。这按本轮要求取代362该模式的底栏全不透明处理。

## 绘制范围与性能限制

- `HomeGlassSurface` 裁切至自身圆角边界，使用一个预创建/复用的sigma10滤镜。主页`BackdropGroup`让非重叠区域共享背景输入；顶部按钮组在AnimatedSwitcher外统一滤镜，不对退出/入场按钮分别叠加动态高斯模糊。
- 不逐帧改变sigma，不为列表每首歌曲增加滤镜，不新建动画时钟或全屏saveLayer，不影响主页切页/播放器位置更新规则。
- `HomeGlassMaterial` 使用透明Material承接真实Ink/touch行为，避免旧实色底把模糊盖住。普通主题模式禁用BackdropFilter，零边距/无裁切，保留原底色；固定包装保持子组件State。
- 软件测试验证有限绘制边界、共享backdropKey、滤镜对象复用、开关切换State/点击、普通模式禁用滤镜及底色恢复。**这是结构及软件渲染证据，不是GPU/内存/满帧提升数据。** 毛玻璃确实有额外合成开销；本轮未做Profile/Perfetto及60/120Hz真机测试。

## 验证

- 修改前灰阶层次红测失败，保存在 `glass-363/baseline-red.txt`；测试开发过程的编译错误、截图异步等待中止日志/首张未加载字体样本均保留，不删除或冒称成功证据。
- 最终全量Flutter：482项通过、1项既有跳过。
- `flutter analyze --no-pub`无问题；工具Python6项通过；`git diff --check`通过。
- 背景策略/重启恢复/参数不变、实际自定义背景挂载、独立配色及字体保留、route不携带中性/玻璃扩展、点击/State、裁切/共享/复用、深浅软件渲染均覆盖。
- 软件视觉检查：`F:/AGENT/1/test-artifacts/glass-363/software-final/`下light/dark与plain/image四张PNG。使用生产主题/玻璃组件，加载MiSans与MaterialIcons；页面内容为测试组合、条纹为合成背景，不是完整真机主页截图。已检查字符、按钮、卡片边缘和背景透出。
- 仅ARM64 Release构建，包名`com.myune.music`、versionName1.0.0、versionCode2363；ABI/ELF/CRC、v2签名及16KiB对齐审计。签名沿用现有debug配置，不自动更换签名。

## 交付与留档

主要生产文件：`lib/mobile/mobile_shell.dart`、`lib/theme/home_theme_scope.dart`、新`lib/theme/home_background_policy.dart`及`lib/widgets/home_glass_surface.dart`、设置选项副标题和版本/更新记录。

测试：`test/home_theme_scope_test.dart`、新`test/home_glass_surface_test.dart`以及版本测试。逐字歌词引擎、流体着色器/取色、播放逻辑和主题配置参数未在本轮修改。

- 修改前完整源码：`dist/Myune-Music-1.0.0-android.362-source-baseline-20261005.zip`（671项）。
- APK：`dist/Myune-Music-1.0.0-android.363-arm64-v8a.apk`。
- APK大小32,359,996 bytes（30.86MiB）；SHA256：`8927C21D34353BE9F091FFFC516A204DB4AF91F9B8157DE52C6DFE7A5CDEE66C`。
- 完整源码：`dist/Myune-Music-1.0.0-android.363-source-20261005.zip`，涵盖当前跟踪及未跟踪源码，逐项SHA256与工作区一致、ZIP CRC通过。
- 日志、软件PNG、审计及清单：`F:/AGENT/1/test-artifacts/glass-363/`。
- 备份：`F:/临时文件夹/备份/Myune-Music-1.0.0+363-20261005/`；dist、build输出、本轮证据及记录逐文件SHA256核对，详见artifact-manifest.json。

此前361/362源码、APK及测试资料全部保留。本轮不以旧设备安装、旧录屏或软件PNG宣称已真机验证363。
