# Android389：默认歌词滚动活动修复

日期2026-10-14，版本1.0.0+389，基线为388不可变源码ZIP（771项，SHA256 `F9B0424A7CAD5B605347D7DEB15B88B1F366C56683139570AB8CBEE56F1F1C73`）。保留上一轮所有未提交源码；本轮无提交/推送/tag/Release，无真机测试、ADB、安装、应用启动/Profile/录屏/Launcher登记。

## 原因与修改

自动跟随的共享时钟原先每帧调用`ScrollPositionWithSingleContext.jumpTo`。核对本机Flutter SDK：该方法每次先goIdle，再forcePixels、didStartScroll、didUpdateScrollPositionBy、didEndScroll，最后goBallistic(0)。一个连续动画被当成几十次跳转，重复通知、活动分配及惯性评估，增加滚动帧开销。新增回归在60Hz普通双语歌词样本中复现一次滚动47次开始通知；这是可复现的软件开销，不冒充真机卡顿耗时归因。

新增`LyricFollowScrollController`与专用滚动活动，共享时钟逐帧以setPixels提交同一弹簧的偏移；一个跟随周期只开始/结束一次，不另建Ticker、Simulation或逐帧状态快照。完成时回到idle；手动触摸/拖动/惯性活动已接管时，stopFollowing不会关闭它。真实seek、换曲定位和版式重锚仍使用原有立即跳转。边界约束、用户拖动、ListView懒挂载、语义与ScrollUpdate通知保持。

默认弹簧的解析推进、字号适配频率、.90阻尼、亚像素尾部与中途速度接续保持，不换曲线、缩时或丢弃延迟帧。动态/弹性共用的基础偏移提交也消除逐帧活动重启，但行运动、7%逐字上浮、字形缓存、预热、模糊/光晕和620ms高亮交接未改。网络资格、40%→15%普通透明度、20%封面外光、队列操作与EQ预设、480ms播放淡入全部保持388。

## 验证

新增2项有意义回归：60/90/120Hz一次跟随只有1次开始/1次结束，更新仍超过10帧、完成idle且全文布局计数不增；16/120/16/240ms延迟帧逐点符合原解析模型，连续切行保持速度，随后真实拖动进入浏览。首次红测保存`red.txt`，旧实现47次开始，轨迹测试本身通过。完整Flutter699通过/1既有跳过；旧逐字/动态/弹性/切页/旋转/字号/显隐/seek/浏览/滤镜与字形缓存回归保持。工具6项、静态检查及构建后623项代码哈希见最终记录。

四张实际MobileLyricsList软件帧已检查，包含中文/英文、光晕和行模糊，合成文案/固定底色与实际MiSans。文件名为0/120/360/1000，最后一张实际在pumpAndSettle后截取，1000仅终态标签，并非精确1秒采样。没有GPU/Android帧耗时或实际封面设备验证，不能据此保证所有场景零掉帧。

证据`F:/AGENT/1/test-artifacts/default-scroll-389/`。APK/源码位于dist；备份`F:/临时文件夹/备份/Myune-Music-1.0.0+389-20261014/`，原生/字体/资源/16KiB/签名/CRC/源码与副本SHA以该目录最终清单为准。完整774项源码较388改6/增3/删0，历史388APK/源码/记录与备份不覆盖。

Release构建106.4秒，APK32,271,740 bytes，SHA256 `238A52D8A631B164C2D87EA4AD1C16A2919B5CA0B5CDE7E79C1AE39CE7AC9BBE`。交付路径`dist/Myune-Music-1.0.0-android.389-arm64-v8a.apk`；完整源码`dist/Myune-Music-1.0.0-android.389-source-20261014.zip`。版本2389/单ARM64/既有debug签名v2，字体与6项非libapp原生、19项Flutter资源保持388。详细审计和备份SHA见artifact-checks/final-verification/artifact-manifest/backup-verification。
