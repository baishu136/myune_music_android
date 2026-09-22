# Android 251：流体背景前台恢复修复

日期：2026-09-10  
版本：`0.9.9+251`

## 真机发现

设备为 vivo V2352A / Android 15，实际渲染刷新率约 60 Hz。250 profile 包在播放页流体背景运行时，进入后台阶段无超预算帧，但回到前台后 raster P95 会持续升至约 20–21 ms；build P95 仍约 2–3 ms。暂停播放使背景 ticker 停止，再恢复播放后 raster P95 回落到 5.12 ms，确认问题位于 Shader ticker 的 Surface 恢复时机，不是页面组件加载。

## 修复

- 非前台状态立即停止流体背景 ticker。
- Android 回到 `resumed` 后先保留最后一帧背景，不阻塞封面、歌词或控制组件绘制。
- 等待首个 Flutter 帧、900 ms Surface 恢复窗口以及现有交互控制器的空闲任务许可后，再恢复 Shader 运动。该窗口仅冻结背景运动，不延迟页面内容。
- 使用代次校验取消快速前后台切换产生的过期恢复任务。

## 真机验收结果

profile 模式、60 Hz、流体背景“自动”档位：

| 场景 | 帧数 | build P95 / 最大 | raster P95 / 最大 | 超 16.67 ms（build / raster） |
| --- | ---: | ---: | ---: | ---: |
| 进入播放页 5 次 | 432 | 3.28 / 30.50 ms | 10.09 / 15.06 ms | 5 / 0 |
| 返回主页 5 次 | 147 | 14.04 / 40.82 ms | 11.98 / 17.91 ms | 4 / 1 |
| 播放稳态 15 秒 | 899 | 5.82 / 9.49 ms | 9.13 / 14.05 ms | 0 / 0 |
| 后台 5 秒（收尾帧） | 16 | 2.98 / 4.15 ms | 4.58 / 4.75 ms | 0 / 0 |
| 回前台首 3 秒 | 134 | 3.04 / 4.93 ms | 8.43 / 24.10 ms | 0 / 1 |
| 回前台随后 5 秒 | 296 | 3.82 / 8.26 ms | 8.50 / 10.84 ms | 0 / 0 |

与 250 的同机复测相比，回前台随后 5 秒 raster P95 从约 20.90 ms 降至 8.50 ms，超预算 raster 帧从 89 / 295 降至 0 / 296。首个恢复窗口仍有 1 个 24.10 ms 的 raster 峰值，但没有形成持续卡顿。

歌词播放 10 秒与快速切 8 首歌的 250 对照分别只有 1 个 raster 超预算帧；251 只改变生命周期恢复门控，不改变歌词、切歌或色板算法。测试期间 Android thermal status 为 0，未发现崩溃、Shader 编译或 FragmentProgram 错误。

返回主页的 build P95 仍高于 60 Hz 下 8.3 ms 的规划目标，属于页面卸载/重建侧而不是流体 Shader raster；本版如实保留该限制。播放设置弹层覆盖期间也仍存在弹层自身 raster 峰值，流体背景已经停止调度，后续应作为独立弹层性能工作处理。

## 数据位置

修复前的逐帧原始数据、汇总和可重跑脚本位于：

- 250 对照：`F:\AGENT\1\test-artifacts\fluid-background-250-20260910\`
- 251 验收：`F:\AGENT\1\test-artifacts\fluid-background-251-20260910\`

## 最终发布校验

- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub`：186 项测试全部通过。
- 发布 APK：`F:\AGENT\1\myune_music_android\dist\Myune-Music-0.9.9-android.251-arm64-v8a.apk`
- APK：`versionCode=2251`、`versionName=0.9.9`、`arm64-v8a`，包含 `shaders/fluid_background.frag`，APK Signature Scheme v2 验证通过。
- APK SHA-256：`3FCE0A6B9AE761BD5EF5B8BA8448E613AA6A042199E9B33EB02FCE1F50EE3377`
- 真机覆盖安装并启动成功，设备报告 `primaryCpuAbi=arm64-v8a`、`versionCode=2251`、thermal status 0。
- 留档目录：`F:\临时文件夹\备份\Myune-Music-0.9.9+251-20260910-204910`
