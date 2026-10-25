# 426：动态背景恢复412（2026-10-25）

用户要求“动态背景回退412版”。仅恢复背景，不回退整应用。当前版本为1.0.0+426，ARM64 Android versionCode为2426；不提交、推送或发布GitHub Release。应用内更新日志仍为最后实际发布的412，413～426待下次授权发布归并。

## 恢复来源与范围

基准为不可变的 `dist/Myune-Music-1.0.0-android.412-source-20261018.zip`，检查CRC及其pubspec版本后，在外部证据目录解压限定文件并以补丁恢复。8个核心文件规范BOM/换行后与412逐字一致：FluidPalette模型、ArtworkPaletteCache、FluidBackgroundController、FluidPlaybackBackground、FluidBackgroundPainter、FluidFrameUniforms、fluid_colour_motion及原fluid_background.frag。

恢复412的取色、四场空间分布、宽扩散混色、颜色变化速度和路径、形变及45参数渲染链路。原生命周期、画质、减少动画、节奏响应、切歌中断重定向与背景快照也采用412实现；其中控制器本来已与412一致，不做无意义更改。对照425源码包，其余263个运行文件逐字节未变，包括歌词、音频、主页、设置和桌面歌词，不回退60字号或后台播放修复。

移除被替换的网格/Atmospheric辅助类和着色资源，以及其专属423～425测试；414测试只移除已撤销的背景规则，逐字平滑及60字号测试保留。对应历史代码与测试仍可从完整425源码ZIP/标准备份恢复，删除前另在本轮外部证据superseded425中保存。恢复5个旧背景测试/参考计算文件至412原文，不将新风格测试门槛放宽来假装旧风格通过。

## 验证

- `restore-verified.json`：8个背景文件与412一致，其余263个425运行文件保持。
- 全量Flutter：896通过、1项既有跳过，69秒；工具22项通过。
- 首轮全量出现两项旧测试基准冲突：颜色速率仍期望414的3.2（412为8），CPU对照仍使用414边缘系数。恢复412原始测试及参考计算后复验通过，原失败日志和冻结清单保留。
- 静态检查无问题（61.4秒）；699个非文档输入在构建前后保持。
- 正式ARM64 Release：32,372,535 bytes，SHA256 `73C6DE34F82D0DFC8723AD92710E94BFB174F063EAC028ADBF119F219B7C2055`。versionCode2426、原v2签名、16KiB ZIP/ELF对齐、压缩原生及CRC通过。7个非libapp原生库同425；Flutter资源仅原shader/AssetManifest变化，并移除两种撤销风格的shader。源码ZIP及标准备份以最终清单为准。

证据：`F:/AGENT/1/test-artifacts/restore-fluid-412-426/`。ADB未检测到设备；没有安装、实际启动、真机视觉/GPU/耗电验证或Launcher登记。背景源码一致和软件渲染回归不等同真机性能验收，原生/音频未变也不重复声称通过真机专项。

## 交付

- `dist/Myune-Music-1.0.0-android.426-arm64-v8a.apk`
- `dist/Myune-Music-1.0.0-android.426-source-20261025.zip`
- `F:/临时文件夹/备份/Myune-Music-1.0.0+426-20261025/`

保留412、424、425等全部历史留档；最终字节数、SHA、备份副本和相对425的完整变化范围见本轮artifact-manifest及scope-review。
