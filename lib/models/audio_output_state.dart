enum AudioOutputMode { standard, bitPerfect, exclusive }

class OutputPcmFormat {
  const OutputPcmFormat(
    this.sampleRate,
    this.encoding,
    this.channels, {
    this.bitPerfect = false,
  });
  final int sampleRate, encoding, channels;
  final bool bitPerfect;
  factory OutputPcmFormat.fromMap(Map data) {
    final f = data['format'] as Map? ?? data;
    return OutputPcmFormat(
      (f['sampleRate'] as num?)?.toInt() ?? 0,
      (f['encoding'] as num?)?.toInt() ?? 0,
      (f['channels'] as num?)?.toInt() ?? 0,
      bitPerfect: data['bitPerfect'] == true,
    );
  }
  // Android PCM encodings; floating point is deliberately not claimed lossless PCM.
  String? get mpvFormat => switch (encoding) {
    2 => 's16',
    22 => 's32',
    _ => null,
  };
  int get aaudioFormat => switch (encoding) {
    2 => 1,
    21 => 3,
    22 => 4,
    4 => 2,
    _ => 0,
  };
  String get description =>
      '$sampleRate Hz · ${switch (encoding) {
        2 => '16-bit',
        21 => '24-bit',
        22 => '32-bit',
        4 => 'Float',
        _ => '格式 $encoding',
      }} · $channels 声道';
}

class AudioOutputDevice {
  AudioOutputDevice.fromMap(Map data)
    : id = (data['id'] as num).toInt(),
      name = data['name'] as String? ?? '音频设备',
      connection = data['connection'] as String? ?? '系统媒体输出',
      profileKey = data['profileKey'] as String? ?? '',
      persistentIdentity = data['persistentIdentity'] == true,
      usb = data['usb'] == true,
      directSelectable = data['directSelectable'] == true,
      encodings = ((data['encodings'] as List?) ?? [])
          .whereType<num>()
          .map((v) => v.toInt())
          .toList(),
      channelCounts = ((data['channelCounts'] as List?) ?? [])
          .whereType<num>()
          .map((v) => v.toInt())
          .toList(),
      sampleRates = ((data['sampleRates'] as List?) ?? [])
          .whereType<num>()
          .map((v) => v.toInt())
          .toList(),
      mixerFormats = ((data['mixerFormats'] as List?) ?? [])
          .whereType<Map>()
          .map(OutputPcmFormat.fromMap)
          .toList();
  final int id;
  final String name, connection, profileKey;
  final bool persistentIdentity, usb, directSelectable;
  final List<int> sampleRates;
  final List<int> encodings, channelCounts;
  final List<OutputPcmFormat> mixerFormats;
}

class AudioOutputSnapshot {
  AudioOutputSnapshot.fromMap(Map data)
    : sdk = (data['sdk'] as num?)?.toInt() ?? 0,
      bridgeAvailable = data['bridgeAvailable'] == true,
      devices = ((data['devices'] as List?) ?? [])
          .whereType<Map>()
          .map(AudioOutputDevice.fromMap)
          .toList(),
      stream = ((data['stream'] as List?) ?? [])
          .whereType<num>()
          .map((v) => v.toInt())
          .toList(),
      routeVerified = data['routeVerified'] == true,
      mixerConfirmed = data['mixerConfirmed'] == true;
  final int sdk;
  final bool bridgeAvailable, routeVerified, mixerConfirmed;
  final List<AudioOutputDevice> devices;
  final List<int> stream;
  int at(int i) => i < stream.length ? stream[i] : 0;
  AudioOutputDevice? get current {
    if (!routeVerified || at(1) != 1 || at(7) < 2 || at(7) > 10) return null;
    for (final device in devices) {
      if (device.id == at(2)) return device;
    }
    return null;
  }

  bool get exclusiveConfirmed =>
      current?.usb == true && at(6) == 0 && at(1) == 1;
  bool matches(OutputPcmFormat format) =>
      current?.usb == true &&
      mixerConfirmed &&
      at(3) == format.sampleRate &&
      at(4) == format.aaudioFormat &&
      at(5) == format.channels &&
      at(12) == format.sampleRate &&
      at(13) == format.aaudioFormat &&
      at(14) == format.channels;
  // mpv's AAudio driver already uses this playhead to subtract its local queue.
  // Never apply this buffer duration again as an acoustic Bluetooth delay.
  Duration? get localQueuedAudio {
    if (at(3) <= 0 ||
        at(10) <= 0 ||
        at(11) < at(10) ||
        at(11) - at(10) > 2000000000) {
      return null;
    }
    final frames = at(8) - at(9) - (at(11) - at(10)) * at(3) / 1000000000;
    if (frames < 0 || frames > at(3) * 2) return null;
    return Duration(microseconds: (frames * 1000000 / at(3)).round());
  }
}
