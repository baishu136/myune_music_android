import 'dart:convert';
import 'dart:math' as math;

/// Optional music graph, independent of the generated effect catalogue.
/// All gain-changing stages share one floating-point graph and a final guard.
class MusicDspSettings {
  const MusicDspSettings({
    this.enabled = false,
    this.gains = const [],
    this.frequencies = const [],
    this.sampleRate = 48000,
    this.filterThreads = 0,
    this.normalizationGainDb = 0,
    this.keepAlive = false,
    this.entrySofteningEnabled = false,
    this.entrySofteningDb = 0,
  });
  final bool enabled, keepAlive;
  final List<double> gains;
  final List<int> frequencies;
  final int sampleRate;
  final int filterThreads;
  final double normalizationGainDb;
  final bool entrySofteningEnabled;
  final double entrySofteningDb;
  static const label = 'myune_music';

  MusicDspSettings copyWith(
          {bool? enabled,
          List<double>? gains,
          List<int>? frequencies,
          int? sampleRate,
          int? filterThreads,
          double? normalizationGainDb,
          bool? keepAlive,
          bool? entrySofteningEnabled,
          double? entrySofteningDb}) =>
      MusicDspSettings(
        enabled: enabled ?? this.enabled,
        gains: gains ?? this.gains,
        frequencies: frequencies ?? this.frequencies,
        sampleRate: sampleRate ?? this.sampleRate,
        filterThreads: filterThreads ?? this.filterThreads,
        normalizationGainDb: normalizationGainDb ?? this.normalizationGainDb,
        keepAlive: keepAlive ?? this.keepAlive,
        entrySofteningEnabled:
            entrySofteningEnabled ?? this.entrySofteningEnabled,
        entrySofteningDb: entrySofteningDb ?? this.entrySofteningDb,
      );

  int get rate =>
      sampleRate >= 8000 && sampleRate <= 384000 ? sampleRate : 48000;
  int get bandCount => math.min(32, math.min(gains.length, frequencies.length));
  int get threads => filterThreads > 0 ? math.min(filterThreads, 32) : 0;
  double gain(int band) =>
      gains[band].isFinite ? gains[band].clamp(-12.0, 12.0) : 0;
  double frequency(int band) =>
      frequencies[band].toDouble().clamp(1, rate * .45);
  double get outputDb =>
      normalizationGainDb.isFinite ? normalizationGainDb.clamp(-24.0, 24.0) : 0;
  double get entryDb =>
      entrySofteningDb.isFinite ? entrySofteningDb.clamp(-6.0, 0.0) : 0;
  double get entryFrequency => math.min(3500.0, rate * .4);
  bool active(String effects) =>
      enabled && (entrySofteningEnabled || processingActive(effects));
  bool processingActive(String effects) =>
      enabled &&
      (keepAlive ||
          effects.isNotEmpty ||
          outputDb.abs() > .001 ||
          List.generate(bandCount, gain).any((g) => g.abs() >= .05));

  static String wire(double value) => value.toStringAsFixed(9);

  String afChain(String effects) {
    if (!enabled) return effects;
    if (!active(effects)) return '';
    final graph = filterGraph(effects);
    // mpv length quoting preserves UTF-8 model paths and nested graph syntax.
    final options = threads == 0 ? '' : 'o=[threads=$threads]:';
    return '@$label:lavfi=${options}graph=%${utf8.encode(graph).length}%$graph';
  }

  String filterGraph(String effects) {
    final entry =
        'treble@myune_entry=g=${wire(entryDb)}:f=${wire(entryFrequency)}:t=q:w=0.5:r=f32';
    if (entrySofteningEnabled && !processingActive(effects)) {
      return 'aformat=sample_fmts=fltp,$entry,alimiter@myune_guard=limit=1:level=false:attack=5:release=100:latency=true';
    }
    final tone = <String>[],
        soft = <String>[],
        dynamics = <String>[],
        limit = <String>[];
    for (final entry in _split(effects)) {
      final match = RegExp(
              r'^@([a-zA-Z0-9_]+):lavfi-([a-zA-Z0-9_]+)(?:=(.*))?$',
              dotAll: true)
          .firstMatch(entry);
      if (match == null) {
        throw const FormatException('Unsupported raw stage in music graph');
      }
      final name = match.group(2)!, id = match.group(1)!;
      var options = match.group(3) ?? '';
      // Generated string options use mpv's brackets; convert to lavfi quoting.
      options = options.replaceAllMapped(
          RegExp(r'(\w+)=\[([^\]]*)\]'), (m) => '${m[1]}=${_option(m[2]!)}');
      var stage = '$name@$id${options.isEmpty ? '' : '=$options'}';
      if (const {
        'bass',
        'treble',
        'tiltshelf',
        'equalizer',
        'highpass',
        'lowpass'
      }.contains(name)) {
        if (!RegExp(r'(^|:)r=|(^|:)precision=').hasMatch(options)) {
          stage += '${options.isEmpty ? '=' : ':'}r=f32';
        }
      }
      (name == 'alimiter'
              ? limit
              : name == 'asoftclip'
                  ? soft
                  : name == 'acompressor'
                      ? dynamics
                      : tone)
          .add(stage);
    }
    return [
      'aformat=sample_fmts=fltp',
      for (var i = 0; i < bandCount; i++)
        'equalizer@myune_eq_$i=f=${wire(frequency(i))}:t=q:w=1:g=${wire(gain(i))}:r=f32',
      ...tone,
      ...soft,
      ...dynamics,
      ...limit,
      if (entrySofteningEnabled) entry,
      'biquad@myune_output=b0=${wire(math.pow(10, outputDb / 20).toDouble())}:b1=0:b2=0:a0=1:a1=0:a2=0:r=f32',
      'alimiter@myune_guard=limit=1:level=false:attack=5:release=100:latency=true',
    ].join(',');
  }

  static String _option(String value) {
    final option = value
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll(':', '\\:');
    return option
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll(',', '\\,')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]');
  }

  static List<String> _split(String chain) {
    if (chain.isEmpty) return const [];
    final parts = <String>[];
    var start = 0, depth = 0;
    for (var i = 0; i < chain.length; i++) {
      if (chain[i] == '[') depth++;
      if (chain[i] == ']') depth--;
      if (chain[i] == ',' && depth == 0) {
        parts.add(chain.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(chain.substring(start));
    return parts;
  }

  List<({String label, String option, String value, String filterName})>? diff(
      MusicDspSettings previous, String effects) {
    if (enabled != previous.enabled ||
        bandCount != previous.bandCount ||
        active(effects) != previous.active(effects) ||
        (active(effects) && threads != previous.threads) ||
        entrySofteningEnabled != previous.entrySofteningEnabled ||
        processingActive(effects) != previous.processingActive(effects)) {
      return null;
    }
    if (!active(effects)) return const [];
    final entryCommands =
        <({String label, String option, String value, String filterName})>[
      if (entrySofteningEnabled && entryFrequency != previous.entryFrequency)
        (
          label: label,
          option: 'frequency',
          value: wire(entryFrequency),
          filterName: 'treble@myune_entry'
        ),
      if (entrySofteningEnabled && entryDb != previous.entryDb)
        (
          label: label,
          option: 'gain',
          value: wire(entryDb),
          filterName: 'treble@myune_entry'
        ),
    ];
    // Tone recovery never recomputes the EQ response grid or rewrites the AF.
    if ((identical(gains, previous.gains) &&
            identical(frequencies, previous.frequencies) &&
            sampleRate == previous.sampleRate &&
            outputDb == previous.outputDb &&
            keepAlive == previous.keepAlive) ||
        !processingActive(effects)) {
      return entryCommands;
    }
    final out =
        <({String label, String option, String value, String filterName})>[];
    for (var i = 0; i < bandCount; i++) {
      if (frequency(i) != previous.frequency(i)) {
        out.add((
          label: label,
          option: 'frequency',
          value: wire(frequency(i)),
          filterName: 'equalizer@myune_eq_$i'
        ));
      }
      if (gain(i) != previous.gain(i)) {
        out.add((
          label: label,
          option: 'gain',
          value: wire(gain(i)),
          filterName: 'equalizer@myune_eq_$i'
        ));
      }
    }
    if (outputDb != previous.outputDb) {
      out.add((
        label: label,
        option: 'b0',
        value: wire(math.pow(10, outputDb / 20).toDouble()),
        filterName: 'biquad@myune_output'
      ));
    }
    return [...out, ...entryCommands];
  }
}
