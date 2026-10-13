# Android384：三平台歌词链路审查、封面外发光与全屏提示退场

日期2026-10-12，1.0.0+384，正式ARM64 split版本2384。基线为383完整源码ZIP，保留全部已有成果。本轮不提交/推送/tag/Release，不进行ADB查询、安装、启动、Profile、录屏或Launcher登记。

## 歌词来源的实际路径

生产入口为 `lib/page/playlist/playlist_content_notifier.dart` 的 `_resolveLyricsForSong` → `_resolveLyricsUncached`。优先外置时为外置LRC→在线（若启用）→内嵌；否则在线（若启用）→外置→内嵌。在线 `_fetchOnlineLyrics` 优先用户选择的网易/QQ/酷狗，允许回退时再按网易、QQ、酷狗顺序排除已尝试项。找到任何非空结果即停止，**没有逐字质量优选或继续寻找更好的逐字源**。默认在线及回退关闭，原用户配置本轮不改。

16项LRU和同键请求合并，缓存键包含路径/来源优先级/在线/主平台/回退/译文；空结果不缓存。当前结果提交核对请求代际/当前歌曲，随后80ms再预取邻曲。开启逐字显示不是向平台请求逐字数据的开关；普通LRC在“全部歌词”逐字模式可以估算时间，不能当作真实词元。

| 平台 | 当前生产获取链路 | 本轮匿名在线探测 | 当前应用真实逐字接入 |
| --- | --- | --- | --- |
| 网易 | `api/search/get`歌名+歌手，limit=1→`api/song/lyric?os=pc&id=…&lv=-1`读`lrc.lyric`，可另请求tv=-1译文→普通解析 | 当前接口LRC样本43时间标记；新版`POST /api/song/lyric/v1`带yv/ytv/yrv等版本参数，公开《十年》样本返回38毫秒行/294个YRC逐字标记；《晴天》第一结果是翻唱，未返回YRC，另一个《海阔天空》样本也无YRC | 未请求/读取yrc，未实现YRC转换 |
| QQ | `POST u.y.qq.com/cgi-bin/musicu.fcg`，`DoSearchForQQMusicDesktop`取40首但只用第一首mid/id→`c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg`→Base64 UTF8 `lyric/trans`→普通解析 | 旧接口63个LRC时间标记；新版`music.musichallSong.PlayLyricInfo/GetPlayLyricInfo`，qrc=1返回HTTP200/模块code0、qrc=1、crypt=0、9808字符十六进制载荷。仅确认QRC格式标志/非空载荷，未解密并验证词时间；不凭crypt=0宣称明文可解析 | 未请求新版QRC、未实现解密/解压及QRC解析 |
| 酷狗 | HTTP `mobilecdnbj.kugou.com/api/v3/search/song`歌名+歌手，pagesize=1→歌曲hash→HTTPS `krcs.kugou.com/search?man=yes&hash=…`→第一候选id/accesskey→HTTPS `lyrics.kugou.com/download?ver=1&id=…&accesskey=…&fmt=lrc`→Base64 UTF8→普通解析 | 原链路四步HTTP200，20候选；同候选LRC为63时间标记，fmt=krc为4192字节，krc1头、XOR和zlib解码成功，63毫秒行/602个KRC逐字标记 | fmt固定lrc，未请求/解码KRC |

证据仅保存响应字段、长度、类型、格式标记和计数，不保存歌词正文、accesskey、Cookie、凭据或音频。使用公开曲目查询，未使用本机曲库/私有媒体。测试日期仅代表该时刻该网络和这些样本，不能保证所有歌曲、版本或账号均能返回。

## 酷狗缺陷及接入边界

`_fetchKugouLyrics` 最后调用 `_parseLrcContent([decodedLyric])`。普通解析器按输入字符串迭代，时间正则的`.`不跨行，`allMatches`虽找到多行，但每个输入字符串只取`matches.first`。因此整份多行LRC作为一个元素时只处理首个匹配；不等价于网易/QQ的`split('\n')`。这是源码静态确认的截断缺陷，尚未通过完整播放器HTTP注入复测。本轮用户要求查看链路，**不改网络/解析行为**，避免审查顺带升级来源。

后续实施建议：先拆分酷狗多行文本并做合成多行回归；独立解码适配器输出现有LyricLine/LyricToken，不在绘制帧做网络或解码；网易YRC把绝对词起点及长度转start/end，酷狗KRC把行起点加词偏移、长度转start/end；QQ需先核实十六进制QRC载荷编码与解密/解压，随后解析XML及词时间。每源优先真实逐字，缺失/格式错误回退同曲普通LRC，不能把估算歌词标成平台逐字。

搜索全部仅选第一歌曲/第一歌词候选，缺少歌手、时长、版本评分，网易晴天实测即匹配翻唱；若实施逐字接入，应先扩大候选并校验身份/版本，避免更精细但对错歌曲的时间。酷狗HTTP搜索还需单独评估HTTPS替代与Android明文配置；本机HTTP200不证明厂商设备可用。请求通常设置10秒，但串行多阶段/多源没有整体截止时间；QQ的Response.fromStream读取体没有同样的timeout，不宣称总耗时封顶。保留代际/缓存/邻曲预取，加入整链预算和取消，再评估实际延迟。

格式依据（社区适配器的原作者代码/文档，非平台官方稳定API承诺）：[网易新版请求源码](https://gitlab.com/fantasycat6/neteasecloudmusicapi/-/blob/main/module/lyric_new.js?ref_type=heads)、[酷狗SDK原作者格式文档](https://docs.rs/kugou_sdk/latest/kugou_sdk/lyric/index.html)、[KRC解析器原作者源码](https://github.com/kangkang520/kugou-lyric/blob/master/src/parser/krc.ts)、[QQMusicApi原作者响应模型](https://l-1124.github.io/QQMusicApi/reference/model/lyric/)。本轮实际返回以外部JSON探测为准。

## 本轮运行代码

- `NowPlayingCoverGlow`：仅实际流体背景（resolved coverEnabled且style=fluid）启用，一层白色alpha=.40、blur24、spread2、外侧BlurStyle.outer、圆角8。始终保持Decorator/内部Hero及图像结构，不改尺寸、点击、图片过渡和路由飞行；光晕在Hero外，飞行图像不添加滤镜。无Ticker、BackdropFilter、取色或逐帧变化。40%按本轮开头明确的“不透明度40%”实现。
- `FullscreenSwipeSongHint`：提示可见时才监听原行索引通知；合并到下一次post-frame核对已经提交的当前歌曲/歌词，排除无焦点、越界、未来时间、空行及间奏。当前非空正播行高亮即从现有姿态开始原140ms向右64dp淡出，随后解除监听。晚到歌词由父页数据更新复核；按行级高亮，不额外等待该行某个逐字词元开始。若切到0秒即已高亮的曲目，可直接取消尚未显现的标题，避免覆盖歌词。
- 保留220ms方向入场、24固定字号/无封面、2200ms无歌词兜底，减少动画/退出/后台清除、失败或同曲不显示。歌身份守卫避免旧曲事件关闭新标题；提示退场后不订阅位置帧、不轮询、不重建整页。383滚动、扫光、弹性/7%上浮、背景算法和首页功能保持。

## 验证与交付

证据目录：`F:/AGENT/1/test-artifacts/lyrics-provider-glow-384/`。新增6项行为回归：空行/间奏/时点守卫、提前退出/退订、旧曲排除/定时兜底、淡入中连续退出/重复事件、新标题与退出竞态、光晕外侧及布局/Element保持/无Ticker。首次两项因测试未锚定post-frame启动Ticker而失败，补零时长pump后相关24项通过，保留两份记录。

最终Flutter628通过、1项既有跳过；新增6项。静态无问题，工具6项，595项代码哈希在最终测试后、构建后均相同。首次静态protected成员用法改为测试Notifier子类内getter；最终重新跑全量628项。实际组件软件预览6帧、软件用合成封面和固定渐变背景，MiSans与真实组件加载；开关外光时封面内区逐像素相同，外边7px之外可见光晕；歌词事件后标题清除。初次宿主未把异步字体/截图放进runAsync而中断；测试默认禁用阴影的六张预览保留，启用实际阴影后一次debug变量在测试结尾恢复的断言失败也保留，最终visual-shipping通过。软件验证不等于实际GPU/厂商显示验证，本轮没有真机性能/功耗或满帧保证。

ARM64 Release耗时58.5秒，APK32,138,860 bytes，SHA256 `BA393C817FC29C2B4B28E1EC9898CE353309B65270A66B0A679B1F9B3C146C5B`；正式com.myune.music/2384/1.0.0，签名v2/16KiB zipalign/压缩原生库/ELF对齐/字体与CRC通过。无原生代码修改，不重跑原生行为测试；除libapp.so外原生库和全部Flutter资源与383逐字节相同。完整740项源码，相对383修改7/新增3/删除0，构建后源码一致核验、ZIP CRC及逐文件对应、备份SHA以最终清单为准。

交付 `dist/Myune-Music-1.0.0-android.384-arm64-v8a.apk`、`dist/Myune-Music-1.0.0-android.384-source-20261012.zip`；核验备份 `F:/临时文件夹/备份/Myune-Music-1.0.0+384-20261012/`。本轮网络函数、歌词解析/媒体时钟/逐字绘制/滚动及动态背景算法保持383源码，未伪造平台逐字支持。
