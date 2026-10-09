# Android 364：保留歌单动效、恢复主页外观与固定底栏磨砂

日期：2026-10-05。基于实际363脏工作区，通过限定补丁恢复362的主页外观，不重置工作区。版本仍向前递增至 `1.0.0+364` / `1.0.0-android.364`，ARM64 split versionCode `2364`，确保升级无需卸载。未提交/推送Git、未创建Release、未清理旧产物、未安装真机。

## 回退范围与保留项

- 对照已保存362/363源码ZIP，363没有新增歌单内容动画或修改主页切页算法。完整保留已有歌单、主页滑动与顶部标题/按钮380ms进入、320ms退出的衔接动效，不回到旧的闪烁路径。
- 保留363的 `home_background_policy.dart`：禁用主题色只改变主页配色，不阻止自定义图片或封面跟随；路径、启用状态、优先级、遮罩及模糊参数不变。播放页及推入的新页面仍使用原全局主题。
- 撤回363顶部/多选按钮磨砂、歌单添加按钮磨砂、平板导航磨砂、方向渐变/描边及悬浮卡片边距。恢复362单色方案：浅色容器均白色，深色背景#121212和原黑灰容器；撤回363额外主色覆写及文本/图标重着色，继承原字体样式。
- 361逐字歌词与362字号40、流体速度/取色/中央补色、现有播放功能及其他未提交成果均保持不变。这不是整库回到362，也不撤销其后的兼容修复。

## 底部两栏

- 不再添加圆角、描边或额外Padding，不修改原NavigationBar、手机ListTile、平板88dp播放栏的内容尺寸、位置及触摸范围；原SafeArea仍负责底部安全区。
- 开启“主页禁用主题色”时，两栏均只有一次 **70%不透明度（alpha=.70，30%透过）** 的单色填充，文字/按键不随背景变透明。关闭恢复原颜色/透明度，并禁用滤镜。
- 导航模糊强度70%、播放状态栏20%。高斯模糊本身没有通用百分比单位，本轮局部控件定义100%=sigma20逻辑像素，因此分别为 **sigma14 / sigma4**。这是局部底栏强度，不更改自定义背景原0–40设置的换算或保存值。
- `HomeGlassProfile`集中定义数值，并复用两个固定滤镜；两种强度不共享backdropKey，避免错误合并。滤镜裁切到各自矩形边界，未增加全屏滤镜、动态sigma插值或计时器。包装结构固定，开关不会重建子组件State。

## 验证及证据边界

- 修改前红测：旧圆角20dp和浅色灰阶断言失败，见 `chrome-364/baseline-red-verified.txt`。初次误用plain-name筛选未运行任何测试，日志另保留，不计入验证。
- 相关首轮26项通过；全量Flutter **485项通过、1项既有跳过、0失败**。覆盖真实背景挂载/重启配置、路由隔离、开关点击和State、有限滤镜复用，以及原有主页/歌单切页连续帧和缓存保留测试。
- 新底栏几何测试覆盖深/浅色、390×844与960×800、1.0/1.4文字缩放和24dp安全区；连续切换开关，在每次15个16ms采样帧中，栏位边界、标题/导航文字位置与State保持一致，并验证点击可用。是生产底栏组件的组合测试，不冒称完整MobileShell真机截图或帧率测试。
- `verify_scope.py`只读对比：主页切页/歌单区域及播放页逻辑与362/363一致（仅规范换行/缩进）；灰阶ColorScheme与362完全一致；主页viewport、背景兼容策略、逐字、流体、设置provider和原生构建文件与363逐字节一致。生产磨砂仅接入底部导航和手机/平板MiniPlayer，不进入顶部、添加按钮或侧边导航。
- 软件视觉：`F:/AGENT/1/test-artifacts/chrome-364/software/`四张深浅/plain/image PNG。使用生产主题/磨砂组件、MiSans与MaterialIcons，条纹是合成背景；检查原位全宽栏、导航强模糊与播放栏较弱模糊、文字与背景透出。不是完整真机截图。
- `flutter analyze --no-pub`无问题（93.6s）、工具6项单测通过、`git diff --check`通过。仅ARM64 Release构建完成（346.7s），ABI/ELF/CRC和原生压缩审计、v2签名及16KiB对齐通过；aapt确认包名com.myune.music、versionName1.0.0、versionCode2364及仅arm64-v8a。
- 软件测试/PNG不能证明GPU/120Hz/功耗。本轮未执行真机安装、Profile/Perfetto采样或原生行为测试（未修改原生行为）。

## 修改与留档

生产：`lib/mobile/mobile_shell.dart`、`lib/theme/home_theme_scope.dart`、`lib/widgets/home_glass_surface.dart`、设置副标题、版本/更新记录。测试：`home_glass_surface_test.dart`、`home_theme_scope_test.dart`及版本/记录测试；本文件、AGENTS和工作目录索引同步。

- 修改前完整源码：`dist/Myune-Music-1.0.0-android.363-source-baseline-20261005.zip`（675项）。
- 安装包：`dist/Myune-Music-1.0.0-android.364-arm64-v8a.apk`，仅ARM64 Release。
- APK大小32,360,320 bytes（30.86MiB）；SHA256：`6DEE42E6F19C7F1ADCC39A6AF55FFA626E26E1C7D8F0D377FA727A3CF554CDD0`。
- 当前源码：`dist/Myune-Music-1.0.0-android.364-source-20261005.zip`。
- 日志/PNG/审计/核验：`F:/AGENT/1/test-artifacts/chrome-364/`。
- 备份：`F:/临时文件夹/备份/Myune-Music-1.0.0+364-20261005/`。

旧361–363产物、备份及失败记录全部保留。源码ZIP含当前跟踪和未跟踪成果，而非HEAD快照；备份逐文件SHA256核对，不恢复/覆盖工作区。保留原debug signing配置，不擅自换签名。
