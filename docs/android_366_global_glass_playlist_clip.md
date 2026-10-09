# Android 366：全主题磨砂、歌单背景与底栏边界隔离

日期：2026-10-05。基于实际365脏工作区继续；版本 `1.0.0+366` / `1.0.0-android.366`，ARM64 split versionCode `2366`。保留所有历史产物及无关未提交修改，不提交/推送、不发布Release、不安装手机。

## 问题与修改

- 365磨砂是否生效由 `HomeChromeStyle`（中性主页的ThemeExtension）决定，普通主题会关闭。366将磨砂参数独立于该开关，所有深浅色、动态配色/自选主题与中性模式共用同一规则；底色仍取当前ColorScheme，不强制将全应用改为灰阶。
- 右上角操作区明确 `enabled:false`：背景透明、滤镜禁用，保留原380ms进入/320ms退出及图标切换。左侧多选退出、歌单添加和分栏操作按键保留70%背景/20%局部模糊。
- 新增 `HomePlaylistSurface`，横向歌单卡片（包括新建）及分栏歌单条目均用70%背景不透明度、20%模糊（sigma4）。选中底色使用secondaryContainer，未选中使用surfaceContainer，Material透明以免再叠一层不透明底色；保持原120dp横向卡片、12/14dp圆角、间距、长按和选中逻辑。
- 底部导航保持70%背景/70%模糊（sigma14），手机/平板播放状态栏保持70%背景/20%模糊（sigma4），原位/原尺寸，不新增悬浮边距或每个栏内图标的重复滤镜。移除原只在中性模式透明的内部导航/FAB/播放栏填充，避免全主题磨砂被不透明Material遮住。
- `HomeTabViewport`外增加始终生效的 `ClipRect(Clip.hardEdge)`，隔离全部主页内容与底栏。内层滚动视口可能只在其滚动轴溢出时裁切，不能充当纵向入场Transform/嵌套绘制的稳定边界。手机body和平板Expanded共享此修复；不改变滚动物理、缓存准备、保活、切页曲线、列表尺寸或歌曲间距。

## 范围与性能边界

“全局”在本轮是统一这些磨砂组件的样式策略，不再依赖禁用主题色：应用的所有主题使用相同参数。没有给歌词正文、播放页全屏或无关新页面批量叠加模糊；这些页面没有上述主页底栏。中性配色开关仍只控制主页配色，自定义图片/封面跟随优先级、遮罩和模糊保存值不变。

100%局部模糊定义为sigma20逻辑像素，20%=sigma4、70%=sigma14；不是改变已有自定义背景0–40设置。所有新表面复用同一个sigma4对象，总共仍只有两个滤镜实例，无逐帧sigma插值/新增Ticker。不共享重叠区域的backdropKey。列表使用原ListView惰性构建，滤镜只属于已挂载条目；实例缓存有界不代表GPU合成零成本。全主题磨砂及歌单条目会增加合成工作，本轮无GPU/120Hz/功耗实测，不宣称满帧或实测性能提升。

## 验证

- 修改前两项红测复现普通主题滤镜禁用、主页无外层ClipRect，见 `baseline-red.txt`。
- 相关33项通过：深浅色/中性开关/歌单选中切换，连续15×16ms尺寸与Element不变、点击/长按、右上角透明/滤镜关闭、滤镜复用、自定义背景、路由配色隔离及原有页面预排/保活测试。
- 像素级软件测试用故意绘制越界的绿色内容和纯蓝底座，检查手机两底栏及平板播放栏，静止及320ms切页过程的采样不再混入越界绿色；同时每帧检查body几何不变。不是实际真机滚动或帧率验收。
- 软件PNG八组：深/浅 × 普通主题/中性 × 纯色/条纹背景，生产主题/磨砂组件加载MiSans与MaterialIcons，右上角透明、歌单玻璃与原位底栏已检查；示意组合，不是完整MobileShell截图。
- 测试编写阶段的括号错误及首版像素阈值误用Material蓝色而非纯蓝底座的失败日志保留；修正测试后通过，不用放宽阈值掩盖越界问题。
- 最终全量Flutter **492项通过、1项既有跳过、0失败**（28.6s），静态分析无问题（7.2s）、工具6项单测通过、`git diff --check`通过。初次静态分析发现测试中一个缺少const的信息提示，修正后重跑全量测试和分析通过。
- `verify_scope.py`只读对照365完整源码，确认主页切页/选择逻辑、分组/列表核心、完整播放页与准备协调器、主题/背景策略、持久化配置、逐字/流体及原生构建配置不变；见 `scope-verification.json`。
- 仅ARM64 Release构建成功（Gradle59.9s）；APK全条目CRC、必需原生库/仅arm64-v8a、原生库压缩/ELF LOAD ≥16KiB、签名v2及`zipalign -c -P 16 4`通过，aapt确认正式包名com.myune.music、versionName1.0.0、versionCode2366。
- 未执行原生行为测试（没有原生修改）、真机安装或Profile/Perfetto。

## 文件与留档

主要生产修改：`lib/widgets/home_glass_surface.dart`、`home_tab_viewport.dart`、`lib/mobile/mobile_shell.dart`；版本、更新记录及对应测试同步。新增 `test/home_glass_global_test.dart`；AGENTS与父目录索引同步。

- 修改前完整源码：`dist/Myune-Music-1.0.0-android.365-source-baseline-20261005.zip`（678项）。
- ARM64 Release：`dist/Myune-Music-1.0.0-android.366-arm64-v8a.apk`，32,359,208 bytes（30.86MiB），SHA256 `47D2F2A404529743599501D0DB7EB25ED54F53136ED2A2394CE27DAC73885818`。
- 当前完整源码：`dist/Myune-Music-1.0.0-android.366-source-20261005.zip`（680项），相比365基线仅本轮10个既有文件修改、2个新增，无删除；逐文件对应工作区/ZIP CRC与备份SHA256核验。
- 红测/失败/成功/PNG/审计/核验：`F:/AGENT/1/test-artifacts/glass-366/`。
- 完整备份：`F:/临时文件夹/备份/Myune-Music-1.0.0+366-20261005/`，原件/副本逐文件SHA256核对。

此前361–365 APK、源码ZIP及证据全部保留。签名沿用既有debug signing配置，不擅自换钥；本轮不推送GitHub。
