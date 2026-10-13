# GitHub Release：Myune Music 1.0.0（Android387）

2026-10-13，用户明确要求“发布至GitHub（含release）”，授权提交并正常推送当前项目源码，以及创建标签和正式Release。此前修改轮次中的“不提交、不推送、不发布”不是本次发布的限制。

目标仓库为`baishu136/myune_music_android`，分支`main`，版本`1.0.0+387`，标签`v1.0.0-android.387`。此次仅发布已验证产物，不修改软件、不递增版本、不重建安装包；保留全部本地源码和历史留档。

## 更新范围

发布说明汇总上次Android353 Release以来、截至Android387仍有效的更新：三平台网络逐字歌词与酷狗修复，主页空闲准备与局部更新，歌词连贯性及弹性滚动，四色自然流动背景，隐藏歌曲/多选/文件夹管理，全屏切歌标题，以及均衡器增益保护和封面三档/外光入场。

本次源码提交还包含此前未推送的Android375–377提交及本地Android378–387新增、修改的源码、测试与项目文档。构建产物、dist、外部证据、本机配置、缓存及凭据不进入Git源码提交。

## 发布附件

| 文件 | SHA256 |
| --- | --- |
| Myune-Music-1.0.0-android.387-arm64-v8a.apk | B6AF1066CA4220730BF8372AD29676AF68BB3B9E0C496408A4D48E8AB2AF1461 |
| Myune-Music-1.0.0-android.387-source-20261013.zip | BDCFB988245577F889E423A26EC403F06381D97F46975D7BAAB5D72075DB6EA1 |

完整源码ZIP为387构建时的758项不可变快照；仓库另外记录本次发布的文档。APK为32,248,924 bytes，正式包`com.myune.music`，versionCode2387，仅arm64-v8a。签名沿用既有配置，不换签名。

677项Flutter测试通过、1项既有跳过，静态分析无问题、工具测试6项，610项验证文件的内容保持。APK版本/签名/压缩原生库/16KiB对齐/字体/CRC已核验。网络逐字并非每首歌都具备词时间；本轮未做真机测试，离线音频和组件软件验证不能代替真机听感或GPU数据。

## 发布完成

- [正式Release](https://github.com/baishu136/myune_music_android/releases/tag/v1.0.0-android.387)已公开并设为Latest，id411547350，非预发布。
- [源码提交9c4bdf7](https://github.com/baishu136/myune_music_android/commit/9c4bdf73ebcb4433523c23b9a0a049f1bd072beb)已正常推送main；父提交3665d5a及此前历史保持。标签为注释标签，对象6d06b7002924382b06e705531eda899e4d11a219，指向该源码提交。main另外记录本次发布完成的交接文档。
- Release先以草稿上传，再核对三个附件的名称、大小、uploaded状态及GitHub服务器SHA256，全部匹配后公开，并重新验证公开附件。
- APK附件id636661226，32,248,924 bytes；源码附件id636661223，44,096,589 bytes；SHA256SUMS附件id636661224，226 bytes。
- 发布记录与远端核验保存在`F:/AGENT/1/test-artifacts/github-release-387-20261013/`；本次只使用当前已登录GitHub CLI凭据通道，没有输出令牌，remote保持原SSH地址，临时HTTPS通道正常非强制推送。
- 原始APK/源码ZIP及387构建留档保持不变；源码包里的AGENTS是构建时快照，仓库的发布交接是后续文档。定时源码同步仍默认不创建Release。
