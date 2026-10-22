import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/audio_output_state.dart';
import '../../services/audio/audio_output_controller.dart';
import '../../widgets/mobile_lyrics_list.dart';
import '../playlist/playlist_content_notifier.dart';
import 'settings_provider.dart';

class AudioOutputPage extends StatefulWidget {
  const AudioOutputPage({super.key});
  @override
  State<AudioOutputPage> createState() => _AudioOutputPageState();
}

class _AudioOutputPageState extends State<AudioOutputPage> {
  AudioOutputController? _output;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _output ??= context.read<PlaylistContentNotifier>().audioOutput;
  }

  Future<void> _perform(Future<void> action) async {
    try {
      await action;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _mode(AudioOutputMode mode) async {
    if (mode == AudioOutputMode.bitPerfect) {
      final use = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('优先保证原始 PCM 输出'),
          content: const Text(
            '此模式会临时旁路均衡器、音效、增益、倍速及软件音量，软件音量按100%输出。请先调低DAC或外置功放的硬件音量。原有设置会保留，退出模式后恢复。系统回执符合条件仍不等于外部测量验证。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留音效，使用标准模式'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('临时旁路并继续'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (use != true) {
        await _perform(_output!.setMode(AudioOutputMode.standard));
        return;
      }
    }
    await _perform(_output!.setMode(mode));
  }

  void _capabilities(AudioOutputDevice device) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(device.name),
                subtitle: Text(device.connection),
              ),
              ListTile(
                title: const Text('系统报告采样率'),
                subtitle: Text(
                  device.sampleRates.isEmpty
                      ? '未提供'
                      : '${device.sampleRates.join('、')} Hz',
                ),
              ),
              ListTile(
                title: const Text('系统报告编码'),
                subtitle: Text(
                  device.encodings.isEmpty
                      ? '未提供'
                      : device.encodings
                            .map(
                              (value) => switch (value) {
                                2 => '16-bit PCM',
                                4 => 'Float PCM',
                                21 => '24-bit PCM',
                                22 => '32-bit PCM',
                                _ => '编码 $value',
                              },
                            )
                            .join('、'),
                ),
              ),
              ListTile(
                title: const Text('系统报告声道数'),
                subtitle: Text(
                  device.channelCounts.isEmpty
                      ? '未提供'
                      : device.channelCounts.join('、'),
                ),
              ),
              for (final format in device.mixerFormats)
                ListTile(
                  title: Text(format.description),
                  subtitle: Text(
                    format.bitPerfect ? '系统提供 Bit-Perfect 混音器配置' : '系统共享输出配置',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _offset(
    String title,
    int value,
    ValueChanged<int> onChanged,
    VoidCallback reset, {
    int limit = 2000,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text('${value >= 0 ? '+' : ''}$value ms'),
            IconButton(
              tooltip: '恢复默认',
              onPressed: reset,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: -limit.toDouble(),
          max: limit.toDouble(),
          divisions: limit * 2,
          label: '$value ms',
          onChanged: (v) => onChanged(v.round()),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final step in [-10, -1, 1, 10])
              OutlinedButton(
                onPressed: () => onChanged((value + step).clamp(-limit, limit)),
                child: Text('${step > 0 ? '+' : ''}$step ms'),
              ),
          ],
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final output = _output!;
    return AnimatedBuilder(
      animation: Listenable.merge([output, output.sync]),
      builder: (context, _) {
        final device = output.current, sync = output.sync;
        return Scaffold(
          appBar: AppBar(
            title: const Text('音频输出与歌词同步'),
            actions: [
              IconButton(
                tooltip: '刷新实际状态',
                onPressed: output.busy
                    ? null
                    : () => _perform(output.refresh()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.speaker_group_outlined),
                title: const Text('当前实际输出'),
                subtitle: Text(
                  device == null
                      ? '当前没有可确认的应用音频流；播放后再检查'
                      : '${device.name}\n${device.connection}\n应用音频流：${output.snapshot.at(3)} Hz · ${switch (output.snapshot.at(4)) {
                          1 => '16-bit',
                          2 => 'Float',
                          3 => '24-bit',
                          4 => '32-bit',
                          _ => '格式未报告',
                        }} · ${output.snapshot.at(5)} 声道\n${output.snapshot.at(12) > 0 ? '硬件报告：${output.snapshot.at(12)} Hz · ${switch (output.snapshot.at(13)) {
                                1 => '16-bit',
                                2 => 'Float',
                                3 => '24-bit',
                                4 => '32-bit',
                                _ => '格式未报告',
                              }} · ${output.snapshot.at(14)} 声道' : '系统未提供硬件实际格式'}',
                ),
              ),
              if (output.busy) const LinearProgressIndicator(),
              if (output.message != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(output.message!),
                ),
              ListTile(
                title: const Text('系统自动选择'),
                leading: Icon(
                  output.requestedDeviceId == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: output.busy
                    ? null
                    : () => _perform(output.useAutomatic()),
              ),
              for (final item in output.snapshot.devices)
                ListTile(
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.connection}${device?.id == item.id ? ' · 实际输出中' : ''}${output.requestedDeviceId == item.id && device?.id != item.id ? ' · 已请求，尚未确认' : ''}',
                  ),
                  leading: Icon(item.usb ? Icons.usb : Icons.headphones),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (device?.id == item.id)
                        const Icon(Icons.check_circle_outline),
                      IconButton(
                        tooltip: '查看设备能力',
                        icon: const Icon(Icons.info_outline),
                        onPressed: () => _capabilities(item),
                      ),
                    ],
                  ),
                  onTap: output.busy
                      ? null
                      : () => _perform(
                          item.directSelectable
                              ? output.selectDevice(item.id)
                              : output.systemPicker(),
                        ),
                ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('打开系统输出选择器'),
                onTap: output.busy
                    ? null
                    : () => _perform(output.systemPicker()),
              ),
              const Divider(),
              if (device != null && device.usb) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<AudioOutputMode>(
                    isExpanded: true,
                    initialValue: output.mode,
                    key: ValueKey(output.mode),
                    decoration: const InputDecoration(labelText: 'USB 输出模式'),
                    items: [
                      const DropdownMenuItem(
                        value: AudioOutputMode.standard,
                        child: Text('标准模式'),
                      ),
                      if (output.mode == AudioOutputMode.bitPerfect ||
                          device.mixerFormats.any(
                            (f) => f.bitPerfect && f.mpvFormat != null,
                          ))
                        const DropdownMenuItem(
                          value: AudioOutputMode.bitPerfect,
                          child: Text('请求系统 Bit-Perfect'),
                        ),
                      if (device.directSelectable)
                        const DropdownMenuItem(
                          value: AudioOutputMode.exclusive,
                          child: Text('请求 USB 独占（AAudio）'),
                        ),
                    ],
                    onChanged: output.busy
                        ? null
                        : (v) {
                            if (v != null) _mode(v);
                          },
                  ),
                ),
                ListTile(
                  title: const Text('模式实际状态'),
                  subtitle: Text(
                    output.exclusiveReported
                        ? '系统已报告此 USB 流为独占；不是应用直接接管 USB 的驱动'
                        : output.bitPerfectReported
                        ? '系统 Bit-Perfect 配置与当前应用/硬件格式一致；严格位流未经外部测量'
                        : output.mode == AudioOutputMode.standard
                        ? 'Android 标准媒体输出'
                        : '尚无完整生效回执，不报告为严格 Bit-Perfect 或独占',
                  ),
                ),
                ExpansionTile(
                  title: const Text('USB DAC 能力与限制'),
                  children: [
                    ListTile(
                      title: Text(
                        '系统报告采样率：${device.sampleRates.isEmpty ? '未提供' : device.sampleRates.join('、')}',
                      ),
                    ),
                    for (final f in device.mixerFormats)
                      ListTile(
                        title: Text(f.description),
                        subtitle: Text(
                          f.bitPerfect
                              ? '系统报告支持 Bit-Perfect 混音器配置'
                              : '系统共享输出配置',
                        ),
                      ),
                    ListTile(
                      title: Text(
                        '系统报告编码：${device.encodings.isEmpty ? '未提供' : device.encodings.map((v) => switch (v) {
                                2 => '16-bit PCM',
                                4 => 'Float PCM',
                                21 => '24-bit PCM',
                                22 => '32-bit PCM',
                                _ => '编码 $v',
                              }).join('、')}',
                      ),
                    ),
                    ListTile(
                      title: Text(
                        '可用声道数：${device.channelCounts.isEmpty ? '未提供' : device.channelCounts.join('、')}',
                      ),
                    ),
                    const ListTile(
                      title: Text(
                        '本模式通过 Android 授权的媒体音频接口工作，不申请原始 USB 接管权限，不占用其他 USB 接口。系统拒绝独占或只返回共享流时会回退普通输出。',
                      ),
                    ),
                  ],
                ),
              ] else
                const ListTile(
                  title: Text('USB 高品质输出'),
                  subtitle: Text('连接并选择 USB 音频设备后，按系统实际报告显示可用模式'),
                ),
              const Divider(),
              const ListTile(
                title: Text('歌词同步偏移'),
                subtitle: Text(
                  '正值：歌词延后；负值：歌词提前。只改变歌词画面，不改变歌曲进度。设备补偿按实际倍速换算；歌曲偏移独立保存。',
                ),
              ),
              _offset(
                '全局默认',
                sync.globalDelayMs,
                (v) => _perform(sync.setGlobal(v)),
                () => _perform(sync.setGlobal(0)),
              ),
              SwitchListTile(
                title: const Text('当前设备使用独立配置'),
                value: sync.deviceOverrideMs != null,
                onChanged: !sync.hasDevice
                    ? null
                    : (v) => _perform(
                        sync.setDevice(v ? sync.effectiveDeviceMs : null),
                      ),
              ),
              if (sync.deviceOverrideMs != null)
                _offset(
                  '当前设备',
                  sync.effectiveDeviceMs,
                  (v) => _perform(sync.setDevice(v)),
                  () => _perform(sync.setDevice(0)),
                ),
              if (sync.hasDevice && !sync.canPersistDevice)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('系统未提供可靠的设备唯一标识，此配置仅用于本次连接，避免同名设备混用。'),
                ),
              if (device != null && !device.persistentIdentity && device.usb)
                ListTile(
                  title: const Text('授权读取 USB 设备标识'),
                  subtitle: const Text(
                    '仅在能唯一对应设备时读取序列号，用于重新连接后恢复同步配置；不会接管音频接口。',
                  ),
                  trailing: const Icon(Icons.usb),
                  onTap: () => _perform(output.requestUsbIdentity()),
                ),
              if (device != null &&
                  !device.persistentIdentity &&
                  device.connection == '蓝牙音频' &&
                  output.snapshot.sdk >= 31)
                ListTile(
                  title: const Text('允许识别蓝牙设备'),
                  trailing: const Icon(Icons.bluetooth),
                  onTap: () => _perform(() async {
                    await Permission.bluetoothConnect.request();
                    await output.refresh();
                  }()),
                ),
              SwitchListTile(
                title: const Text('自动时间轴稳定'),
                subtitle: const Text(
                  '利用播放器已校正的播放时间减少小幅抖动，不猜测无线声学延迟，也不重复扣除音频缓冲。',
                ),
                value: sync.automatic,
                onChanged: (v) => _perform(sync.setAutomatic(v)),
              ),
              ExpansionTile(
                title: const Text('当前歌曲独立偏移'),
                children: [
                  _offset(
                    '歌曲歌词',
                    sync.songDelayMs,
                    (v) => _perform(sync.setSong(v)),
                    () => _perform(sync.setSong(0)),
                    limit: 10000,
                  ),
                ],
              ),
              const ListTile(
                title: Text('播放中校准'),
                subtitle: Text(
                  '边听边观察下方歌词，使用上方±1/10ms微调。结果是用户校准值，非硬件测量。需要单设备保存时先开启独立配置。',
                ),
              ),
              SizedBox(height: 300, child: _LyricSyncPreview()),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: () => _perform(sync.reset()),
                  child: const Text('重置全部歌词同步配置'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _LyricSyncPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final playlist = context.watch<PlaylistContentNotifier>();
    final settings = context.watch<SettingsProvider>();
    if (playlist.currentLyrics.isEmpty) {
      return const Center(child: Text('播放有歌词的歌曲后可实时校准'));
    }
    return ValueListenableBuilder<int>(
      valueListenable: playlist.lyricLineIndexListenable,
      builder: (_, active, _) => MobileLyricsList(
        lines: playlist.currentLyrics,
        active: active,
        contentIdentity: playlist.currentSong?.normalizedPath,
        position: playlist.lyricVisualPosition,
        positionListenable: playlist.lyricPositionListenable,
        playbackRate: playlist.currentPlaybackRate,
        playbackRateListenable: playlist.actualPlaybackRateListenable,
        actualPlaybackListenable: playlist.actualPlaybackListenable,
        seekPositionListenable: playlist.lyricSeekListenable,
        seekIntentListenable: playlist.lyricSeekIntentListenable,
        isPlaying: playlist.isPlaying,
        fontSize: settings.lyricFontSizeFor(MediaQuery.sizeOf(context)),
        karaokeLyricsEnabled: settings.enableKaraokeLyrics,
        karaokeLyricsMode: settings.karaokeLyricsMode,
        smoothKaraokeMotion: settings.smoothKaraokeMotion,
        scrollEffect: settings.lyricScrollEffect,
        textAlign: settings.lyricAlignment,
        activeColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
