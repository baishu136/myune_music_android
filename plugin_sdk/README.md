# Myune 插件 SDK 1

466 起支持在 Android 导入 `.myune-plugin`。这是 UTF-8 JSON 包，包含
`manifest` 和单文件 `script`，不是 APK、ZIP 或 Dart 热更新包。
通过“设置 → 高级 → 插件”或横屏播放功能菜单进入；导入后默认停用，
启用时显示权限。包来源真实性由安装者判断，本版没有插件商店或作者签名认证。
替换同 ID 包会停用旧版本并清空该插件的独立存储，需重新启用授权。

## 编写与打包

参考 `examples/demo-tools.js` / `demo-lyrics.js` 及对应 manifest。
工具示例包含实际播放控制、曲库查询、短曲队列、存储和事件；歌词示例
提供演示 LRC，可停用以恢复内置来源。应用菜单可导入相同两个离线示例。

```sh
python tool/pack_myune_plugin.py plugin_sdk/examples/demo-tools.manifest.json plugin_sdk/examples/demo-tools.js tools.myune-plugin
```

输出路径必须不存在。宿主导入时完成更严格的 manifest 验证；打包器不执行代码。
TypeScript 可参考 `myune.d.ts`，先自行编译/打包成一个普通 JS 文件。
入口是 `globalThis.myunePlugin = async function(event, api) { ... }`。
不支持 ESM 导入、Node、DOM、原生模块、任意文件访问、直接 fetch 或定时器；
异步工作通过 `await api.request(method,args)` 执行。每次事件是全新的 JS 上下文，
跨事件状态使用 storage。处理器返回页面时格式为 `{view: View}`，歌词为 `{lrc,translation?}`。

## Manifest

```json
{
  "id": "author.example",
  "name": "示例",
  "version": "1.0.0",
  "sdk": 1,
  "permissions": ["playback.read", "ui.page"],
  "features": ["page"],
  "menus": [],
  "networkDomains": []
}
```

ID 为小写点/短横分段标识；版本为三段数字。未知权限、功能或 SDK 会拒绝。
features 支持 page、menu、lyrics、events，分别要求 ui.page、ui.menu、
lyrics.provide、playback.read。menus 为 `{id,title}`，最多 8 项，在插件管理页
注册为独立入口。network 权限必须配合明确域名，不能使用通配符。

## 实际宿主接口

| 方法 | 权限 | 参数/行为 |
| --- | --- | --- |
| app.capabilities | 无 | 返回 SDK、方法与功能集合 |
| playback.get | playback.read | 当前 song、playing、positionMs、durationMs |
| playback.command | playback.control | command: play/pause/next/previous/seek，seek 带 positionMs |
| library.query | library.read | query/offset/limit；limit 1～100，返回 songs/total/nextOffset |
| queue.play | queue.write | ids；用查询所得本地歌曲建立动态播放列表并播放 |
| queue.append | queue.write | ids；添加到原播放队列，未有列表时沿用宿主创建播放列表的行为 |
| storage.get/set | storage | key/value，限当前插件，JSON 可序列化 |
| network.fetch | network | url；HTTPS GET，返回 status/body |

歌曲只暴露 id/title/artist/album/durationMs，不提供本机路径、播放器对象或封面字节。
ID 是本次查询所得歌曲的句柄；宿主保留最近 4096 个，失效时重新查询。
查询保持当前曲库顺序，每次最多扫描 5000 首；即使 songs 为空也应根据
nextOffset 继续分页，不把 total 当成本次筛选匹配数。队列每次最多 100 首。

网络只允许 manifest 中精确匹配的域名与 HTTPS 443，不携带应用 Cookie、
认证头或任意请求头，不支持重定向；DNS 地址检查后连接同一地址，保留原域名
进行 TLS 校验。禁止内网、回环及本地地址，响应体 96 KB、单请求最多 4 秒。
需要登录、POST、流式音源或完整 HTTP 客户端的插件需后续 SDK 能力扩展。

## 事件与交互

- lifecycle.enable：启用验证，不允许播放写操作；异常立即恢复停用。
- ui.open：打开插件页面，返回 `{view:...}`。
- ui.action：用户点击插件按钮，data 为 `{id,value}`。
- menu.action：用户打开 manifest 菜单，data 为 `{id}`。
- playback.changed：歌曲/播放状态变化的合并通知，需 events；繁忙时可能丢弃，
  不承诺逐个事件送达，也不订阅逐帧进度。需要准确当前值时调用 playback.get。
- lyrics.resolve：需要歌词时传入歌曲资料。启用的 providers 按安装次序依次尝试，
  空结果/异常继续其他插件和原内嵌/本地/网络链；有效结果优先于内置来源。

播放与队列写操作仅在 ui.action/menu.action 中开放，避免后台事件互相切歌造成循环。
执行中的插件被停用、替换、移除后，后续调用/结果失效；用户切歌后，尚未分发的
旧写请求会被拒绝。已经交给播放器执行的用户操作不做回滚。
歌词仍由宿主请求代数和插件修订号校验。
插件只能添加自己的页面/动作，不拦截系统导航或播放页既有手势。

## 页面组件

View 支持 column、row（最多四列）、card、text、button、space。
text 可使用 title/muted 样式；button 只声明 action/data，由宿主分发 ui.action。
页面由 Flutter 绘制并使用宿主滚动；最大 120 节点、8 层、单文本 2000 字符、
总文本 16000 字符。脚本不在帧时钟运行，不动态创建 Flutter Widget/自定义 Painter。
完整播放页替换、实时歌词绘制、shader、DSP/解码器、原生 APK 扩展不是 SDK 1 已实现能力。

## 故障与资源

QuickJS 2026-06-04 核心引擎在非导出的 Android isolatedProcess 服务中运行，
不链接 std/os 文件/系统模块。500 ms 累计线程 CPU 预算（不计宿主等待及被系统挂起的时间），
单轮原生执行另有 1.5 秒墙钟截止，
12 MB JS 堆、256 KB JS 栈、每次 24 个宿主调用。任务边界按 10 秒期限校验，
已分发的宿主操作不会被强行打断，因此不保证严格 10 秒返回；
网络自身 4 秒截止；运行时传输有独立 4 秒看门狗。限额不是整进程 RSS 保证。
JNI 只在单工作线程运行，全局调用串行，最多 8 个待处理任务，关闭/完成释放上下文。
连续三次执行失败自动停用并保存；正常执行清零连续故障数。运行记录最多 60 条。
每插件存储 16 KB、最多 16 个安装包、包 192 KB/脚本 128 KB。

“检测接口”在真实运行时验证脚本计算、无 std/os、死循环中断、超大分配拒绝、
故障后再次执行，以及运行进程 UID 隔离。组件测试验证权限、过期请求、停用、
故障熔断、存储和 UI 上限；不会把 FakeRuntime 测试当成原生引擎执行证据。
隔离降低插件对播放器的影响，不代表零安全漏洞、全部 Android 设备或长期功耗已验证。
