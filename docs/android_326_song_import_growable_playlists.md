# 326：修复歌曲导入的固定长度列表错误

日期：2026-09-26。基于实际 `0.9.9+325` 工作区，更新为 `0.9.9+326`，显示版本 `0.9.9-android.326`。保留已有未提交修改，不改动逐字歌词、主题或其他无关功能。

## 根因与证据

用户报错：`添加歌曲时发生错误：Unsupported operation: Cannot add to a fixed-length list`。

已连接的 V2352A（ADB `10CEB70TQE001E2`）上，325 版于 10:58:32、10:59:48 两次记录相同异常：

```text
FixedLengthListMixin.addAll
PlaylistContentNotifier._processSongsInBackground:3594
PlaylistContentNotifier.pickFolderAndAddSongs:3557
_MobileShellState._showImportOptions:1322
```

直接失败的是 `currentPlaylist.songs!.addAll(parsedSongs)`，不是权限或音乐元数据解码错误。`_ensurePlaylistSongs` 使用 `.toList(growable: false)` 恢复已解析的歌曲列表，而导入/刷新/删除等调用都将歌单当作可增删集合。

同类风险也存在于构造/赋值传入的固定长度歌曲路径、只读歌曲列表和 const 文件夹列表。只修改一次 `addAll`，或只修复一个调用点，无法保证其他歌单编辑操作和后续列表替换不再触发同类问题。

## 修改

`lib/page/playlist/playlist_models.dart`：

- 歌曲路径、歌曲对象与文件夹路径改为模型持有的私有列表，保持原有公开属性 API。
- 构造及每次赋值时均使用 `List.of` 持有**独立、可增长的浅副本**，统一保障 add/remove/insert/clear 的可用性。
- 仅复制列表容器，不复制 Song 对象、音频文件或封面字节；保留 Song 身份、顺序与原数据。`songs == null` 仍表示尚未加载，JSON 和歌单 ID 格式不变。
- 输入数组不与歌单编辑共享容器，避免刷新或导入回滚反向修改调用方的固定/只读列表。

该约束在列表赋值边界生效，不增加动画帧工作，也不通过吞掉异常、清空曲库或重建用户数据规避错误。播放器与现有导入逻辑继续使用同一模型。

其余本轮修改：

```text
test/playlist_mutability_test.dart                新增 7 项回归测试
pubspec.yaml                                     0.9.9+326
lib/page/setting/project_changelog.dart           326 版修复说明
test/project_changelog_test.dart                  当前版本断言
docs/android_326_song_import_growable_playlists.md 本记录
```

## 自动化验证

先补测试、再修复：修复前新增测试中 **6 项失败**，复现相同 Cannot add/remove/clear 错误；修复后 **7 项全部通过**。覆盖：

- 恢复固定长度 songs 后追加新歌曲，保留已有歌曲及原输入；
- 首次导入到固定长度空 songs；
- 构造输入为只读列表/const 文件夹列表；
- 后续替换为固定长度路径与文件夹列表后的移除/插入；
- 文件夹刷新删旧加新；
- 列表级回滚只移除新条目，保留已有顺序；
- songs 的 null/懒加载与 JSON 恢复语义。

列表级回滚测试不是文件系统写入失败的注入测试，本轮没有人为制造真实存储失败。

- 相关歌单、排序、缓存和变更记录测试：17 项通过。
- 完整 `flutter test --no-pub`：**283 项通过**，原有软件图片导出用例跳过 1 项。
- 完整 `flutter analyze --no-pub`：**无问题**。
- `git diff --check`：通过；仅有原有 LF/CRLF 提示。

## 真机验证（release）

仅构建 release ARM64，并以 `adb install -r` 更新到 V2352A，未卸载、未清空应用数据。

1. 更新前默认「收藏」为空，325 版日志已复现用户报错。
2. 326 版正常启动并确认已安装 `versionCode=2326`。
3. 系统选择器再次打开此前的「音乐1」目录；通过正常文件夹授权流程重试导入。应用显示 **“成功添加 146 首歌曲”**，「收藏」为 **146 首**，标题、歌手、封面正常显示。
4. 停止并重启应用，已导入曲目恢复；「收藏」仍为 **146 首**，首屏顺序一致。
5. 再次导入同一目录，应用提示 **“文件夹中没有可导入的新歌曲”**，数量保持 **146 首**，未重复添加。
6. 重启后的应用进程日志中未发现本次固定长度列表错误或文件夹扫描错误；没有据此宣称所有无关启动警告都已修复。

本轮实际操作是文件夹导入、重启恢复与重复导入；单曲追加、删除/刷新/回滚的可变性由回归测试覆盖，未在真机额外删除用户歌曲或进行故障注入。没有改写或删除原始音频文件；本次导入的 146 首歌曲留在用户「收藏」歌单。

证据目录：`F:/AGENT/1/test-artifacts/import-326/`：

- `import-success.xml`：成功通知及 146 首语义树；
- `import-success.png`：成功导入后的歌单；
- `restored-playlist.xml`：重启后仍为 146 首；
- `duplicate-folder.xml`、`duplicate-folder.png`：重复导入提示与保持的数量。

按 `register-generated-program` 技能，在实际 release 真机启动成功后登记本地 LLMPET 启动入口，返回 `ok=true`；启动命令为当前项目下的 `adb shell am start -n com.myune.music/.MainActivity`。该入口要求有连接的 Android 设备，不是 Windows 原生播放器版本。

## 构建与留档

命令：

```powershell
flutter build apk --no-pub --release --target-platform android-arm64 --split-per-abi
```

- 安装包：`F:/AGENT/1/myune_music_android/dist/Myune-Music-0.9.9-android.326-arm64-v8a.apk`。
- 53,363,258 字节；原生 ABI **仅 arm64-v8a**，`versionCode=2326`、`versionName=0.9.9`；16 KiB zipalign 与 v2 签名校验通过，沿用项目现有签名配置。
- APK SHA-256：`D2D32D421E89837C7B76B861AD184BCA372BA24D11E09740A0FE5A8F402B0EF4`。
- 留档目录：`F:/临时文件夹/备份/Myune-Music-0.9.9+326-20260926-111240/`。包含完整工作区源码快照、ARM64 APK、本记录、README 与上述真机验证截图/语义树。
- 源码快照包含已有未提交成果，排除 Git 历史、工具/编译缓存、build/dist、自动插件依赖文件及本机 `local.properties`；不修改或删除原文件。

回退可在独立目录解压相邻 325 留档，不覆盖当前脏工作区。但不建议将真机降回有导入错误的 325 版；本轮不涉及用户数据格式迁移。
