# 2026-10-23 构建交付与安装包审计

本轮按用户允许自行选择工作的要求，检查当前 Myune Android 项目并修复构建交付工具中的确定问题。开始时工作区干净，HEAD 为 `fbf20c5`。播放器运行源码、设置、版本和既有 APK 没有改动，仍为 `1.0.0+417`。

## 实际修复

1. `.github/workflows/flutter_android.yml` 原先将任何新构建固定命名为 `Myune-Music-0.9.9-android.325-arm64-v8a.apk`，上传名也固定为旧版。现在复用本机 ARM64 Release 脚本，从 pubspec 版本生成名称，按实际 APK 名输出上传名和 SHA256。整理阶段必须且只能找到一个 APK；缺失或多个包时失败。
2. `tool/build_android_release.ps1` 原先在构建完成后读取版本，使用 `Copy-Item -Force` 覆盖既有同名留档。现在先校验唯一有效版本和目标冲突，再调用 Flutter；构建后再次确认版本未改变，使用禁止覆盖的文件复制，保护构建期间并发出现的留档。增加 `-SkipPubGet` 供已获取依赖的 CI 使用，避免重复获取依赖。
3. `tool/analyze_android_apk.py` 原先只检查 LOAD 的 `p_align`，没有验证共享库类型、ELF 版本和头部大小、加载段文件范围、文件/内存大小及偏移与地址的同余关系。现在补齐这些检查，错误带具体库路径。规则来源为 [ELF Header](https://gabi.xinuos.com/elf/02-eheader.html) 和 [Program Loading](https://gabi.xinuos.com/elf/07-pheader.html)。有效的 BSS 内存尾部和非零同余偏移仍被接受。

CI 同时由单个日志测试扩大为全量 Flutter 测试、静态分析和 Python 工具测试。修改保存在本地；没有提交、推送或触发远程 Actions。

## 验证与证据

证据目录：`F:/AGENT/1/test-artifacts/quality-audit-20261023/`。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 全量 Flutter 测试 | 875 通过、1 项既有跳过，约 62 秒 | `flutter-tests.txt` |
| Flutter 静态分析 | 无问题，97.6 秒 | `flutter-analyze.txt` |
| 工具回归测试 | 22 项通过，包含原有 6 项和新增 16 项 | `tool-tests-final.txt` |
| 发布脚本旧行为复现 | 修复前的新增测试出现预期失败 | `release-wrapper-red.txt` |
| ELF 漏检复现 | 修复前的新增畸形结构测试出现预期失败 | `elf-audit-red.txt` |
| CI 整理阶段实际脚本 | 当前版本、不同版本、零包、多个包四组通过 | `ci-stage-verification.json`、`verify_ci_stage.py` |
| 现有 417 APK 内容审计 | 新旧审计器均通过，原生库压缩和 ELF 检查通过 | `apk-417-audit.json`、`apk-417-audit-hardened.json` |
| 现有 417 APK 签名与对齐 | v2 签名验证、16 KiB ZIP 对齐通过 | `apk-417-signature.txt`、`apk-417-zipalign.txt` |
| 现有 417 APK 身份 | `com.myune.music`、2417、1.0.0、ARM64 | `apk-417-badging.txt` |

发布脚本测试在临时项目中运行真实 PowerShell 包装脚本，由假的 Flutter 入口模拟成功、失败、版本中途改变和并发留档，不调用实际编译器。包含带空格路径、绝对输出目录、失败时不复制旧包及跳过重复获取依赖。CI 整理验证直接提取工作流中的 PowerShell 脚本执行，校验实际名称和 SHA256 文件，并非只匹配配置文本。

本轮没有重新编译 APK、安装或启动手机应用，没有进行真机听感、性能或长期后台测试。对既有 417 APK 的审计不等同于新版本构建或完整远程 CI 成功。仅工具和测试改动不递增播放器构建号，不重写 417 的源码 ZIP、APK或历史备份。

审计期间额度接口从周已用 0% 更新为 1%，未耗尽周额度；比例以账户实时返回为准。修改前后文件、Git 差异、日志及哈希清单另存于本轮证据和独立备份，旧档保持不变。
