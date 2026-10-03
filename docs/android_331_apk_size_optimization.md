# 331：ARM64 安装包体积优化

2026-09-26。基于实际工作区 0.9.9+330 更新至 0.9.9+331（应用显示 0.9.9-android.331，ARM64 原生 versionCode 2331）。阅读项目说明、最近记录、构建脚本与源码；未发现适用 AGENTS.md。保留所有已有未提交与未跟踪成果，未调整歌词、播放器、导入、页面或用户设置。

## 依据与实施

330 正式 ARM64 Release 为 53,363,258 字节。原生库以 STORE 方式保存，共 36,153,656 字节；MiSansVF 完整可变字体原始 20,093,424 字节、ZIP 内 14,410,630 字节。字体、Flutter 引擎、AOT 应用和 libmpv 是主要体积来源。项目实际 release 已开启 minifyEnabled/shrinkResources，Material Icons 已进行 tree shaking，本轮不将这些既有机制冒充新增优化。

实际构建入口是 android/settings.gradle 与 android/app/build.gradle（AGP 8.11.1），不是同目录的 .gradle.kts 模板（后者写有 AGP 9.0.1）。首轮只改 Kotlin 模板，包体仍为 53,363,258 字节，审计未通过；已撤销模板改动，在真正的 Groovy 配置开启 android.packaging.jniLibs.useLegacyPackaging=true。保留此诊断记录，不交付未优化的首轮包。

- 使用 ZIP DEFLATE 无损压缩全部七个 ARM64 .so；不删除解码器、不改 ELF、不换字体、不裁剪多语言字形或可变字重。
- tool/build_android_release.ps1 只调用 android-arm64 --split-per-abi Release，默认 dist、按 pubspec 版本命名并打印 SHA256，不再构建/复制 ARMv7。
- 新增标准库工具 tool/analyze_android_apk.py：核对 ABI 和必需库、ZIP 内容与 CRC、ELF64 AArch64 LOAD 对齐，统计实际压缩大小；与基线逐项比较整个 Flutter assets 与非应用原生库 SHA256，拒绝丢资源或没有体积收益的结果。libapp.so 因版本及更新说明改变，单独允许变化。工具不代替签名检查或真机验证。
- README 更新构建方式、审计命令与安装占用权衡；更新应用内变更记录和版本测试。

构建中曾尝试 --no-pub，生成注册器引用 integration_test 而 release 依赖没有该插件，Java 编译失败；已恢复 Flutter 标准 build 流程重新同步插件。未手改生成代码、未删除集成测试或依赖。最终脚本已实际成功执行，错误与成功日志均保留。

## 实测包体

MB=1,000,000 字节；MiB=1,048,576 字节。比较两份实际签名 Release 文件，而非 build 日志中的四舍五入标注。

| 项目 | 330 | 331 |
| --- | ---: | ---: |
| APK 字节 | 53,363,258 | 32,532,354 |
| APK MB | 53.36 | 32.53 |
| APK MiB | 50.89 | 31.03 |
| 原生库 ZIP 字节 | 36,153,656 | 15,397,500 |
| MiSansVF ZIP 字节 | 14,410,630 | 14,410,630 |

总减少 **20,830,904 字节（20.83MB / 19.87MiB），39.036%**。主要收益来自原生库压缩，另有 ZIP 对齐填充差异；不声称资源或程序逻辑减少了同样多的原始内容。

26 项受保护内容逐字节一致：全部 Flutter assets（字体、图片、图标、着色器、许可等）与六个非应用原生库。所有七个库均为 compression_method=8；LOAD 对齐均 >=16KiB（Flutter/AOT 为64KiB，其他为16KiB）。完整审计原始数据见 apk-size-audit.json。

## 安装占用与限制

这是 **APK 下载/分发体积优化，不是运行内存或 GPU 性能优化**。330 manifest extractNativeLibs=false，331 为 true：安装器需将原生库解压到磁盘，安装后占用可能比旧包增加，也可能增加安装耗时。未将较小 APK 等同较小安装占用；没有真机安装占用、冷启动时间、内存或播放功耗实测。

依据：[Android 原生库打包 API](https://developer.android.com/reference/tools/gradle-api/8.13/com/android/build/api/dsl/JniLibsPackaging)、[Android 对压缩库的安装占用说明](https://developer.android.com/guide/practices/page-sizes)。压缩并不免除 ELF 16KiB 对齐要求；已检查 LOAD，但尚未在 16KiB 真机验证，不能仅据 ZIP 检查宣布完整设备兼容性。

完整字体现占包体较大比例，本轮有意保留，避免以丢生僻字、混合语言或字重表现换取体积数字。未移除音频格式支持或改变签名。

## 验证

- flutter test --no-pub --reporter expanded：313 通过、1 项原有可选导出测试跳过。
- flutter analyze --no-pub：No issues found（13.3s）。修改的 Dart 文件格式检查 0 改动。
- python -m unittest discover -s tool/tests -v：6 通过。覆盖真实 ZIP 压缩收益与内容一致、字体/着色器损失拒绝、相同包不冒称收益、缺失 libmpv/错误 ABI、未压缩库、损坏或未对齐 ELF。
- 实际 APK 审计通过，与 330 基线比对通过；v2 签名验证通过，与 330 签名证书 SHA256 一致；zipalign -c -P 16 4 通过。versionName=0.9.9、versionCode=2331、ABI 仅 arm64-v8a，无 DEBUGGABLE。
- ADB 多次及结束检查均没有连接设备。本轮没有安装、启动或播放验证，没有清空曲库。不将前轮 330 的真机数据用于证明 331 行为。
- 未经真实启动，不更新本地启动器注册；只交付构建与静态校验通过的 APK。

## 产物与留档

正式包：F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.331-arm64-v8a.apk

SHA256：343674EEC4BCB8A123AE7028CB69CDA243EB24CC68D0D943EC134176F2DD2C1E

证据：F:/AGENT/1/test-artifacts/package-331/，包含实际构建、失败诊断、测试、签名、manifest、审计 JSON 与设备检查日志。

留档：F:/临时文件夹/备份/Myune-Music-0.9.9+331-20260926-192047/，包含完整当前工作区源码（含未跟踪成果）、正式包、本记录和验证证据；排除 .git/.dart_tool/build/dist/release/编译缓存/__pycache__/local.properties。330 源码和包仍保留，不覆盖旧档。

修改文件：android/app/build.gradle；tool/build_android_release.ps1；新 tool/analyze_android_apk.py、tool/tests/test_analyze_android_apk.py；README.md；pubspec.yaml；lib/page/setting/project_changelog.dart；test/project_changelog_test.dart；本记录。

若优先减少安装后磁盘占用，可在后续版本将真实 Groovy 配置 useLegacyPackaging 改回 false 并重新构建；不要覆盖当前脏工作区，或通过卸载/清库回退。330 基线可在独立目录用于对照。
