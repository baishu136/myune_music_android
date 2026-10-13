import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Conservative music defaults; output peak protection is owned by MusicDsp.
AudioEffects musicEffectPolicy(
  AudioEffects e,
  String id,
  bool enabled, {
  String? model,
}) => switch (id) {
  'crossfeed' => e.updateCrossfeed(
    (m) => m.copyWith(enabled: enabled, strength: .4, range: .5),
  ),
  'earwax' => e.updateCrossfeed(
    (m) => m.copyWith(enabled: enabled, strength: .3),
  ),
  'widerStereo' =>
    e
        .updateExtrastereo((m) => m.copyWith(enabled: enabled, m: 1.2))
        .updateStereowiden(
          (m) => m.copyWith(enabled: enabled, delay: 15, drymix: 1),
        ),
  'haas' => e.updateHaas(
    (m) => m.copyWith(
      enabled: enabled,
      level_in: 1,
      level_out: 1,
      side_gain: .25,
      middle_source: HaasSource.mid,
    ),
  ),
  'vocalBoost' => e.updateStereotools(
    (m) => m.copyWith(enabled: enabled, mlev: 1.25, slev: 1),
  ),
  'vocalRemover' => e.updateStereotools(
    (m) => m.copyWith(enabled: enabled, mlev: .15, slev: 1.1),
  ),
  'acompressor' => e.updateAcompressor(
    (m) => m.copyWith(
      enabled: enabled,
      threshold: .35,
      ratio: 1.5,
      makeup: 1.15,
      attack: 20,
      release: 200,
    ),
  ),
  'softClip' =>
    e
        .updateAlimiter((m) => m.copyWith(enabled: false))
        .updateAsoftclip(
          (m) => m.copyWith(
            enabled: enabled,
            threshold: 1,
            output: 2,
            param: .5,
            type: AsoftclipTypes.tanh,
            oversample: 1,
          ),
        ),
  'deNoise' =>
    e
        .updateAgate(
          (m) => m.copyWith(
            enabled: enabled,
            threshold: .006,
            range: .7,
            ratio: 1.5,
          ),
        )
        .updateAfftdn((m) => m.copyWith(enabled: enabled, nr: 6)),
  'virtualbass' => e.updateVirtualbass(
    (m) => m.copyWith(enabled: enabled, strength: 1.5),
  ),
  'subboost' =>
    e
        .updateAsubboost((m) => m.copyWith(enabled: enabled, dry: 1, wet: .2))
        .updateBass((m) => m.copyWith(enabled: enabled, g: 2)),
  'crystalizer' =>
    e
        .updateCrystalizer((m) => m.copyWith(enabled: enabled, i: .35))
        .updateTreble((m) => m.copyWith(enabled: enabled, g: .75)),
  'tilt' =>
    e
        .updateAtilt((m) => m.copyWith(enabled: enabled))
        .updateTiltshelf((m) => m.copyWith(enabled: enabled)),
  'vinyl' =>
    e
        .updateHighpass((m) => m.copyWith(enabled: enabled, frequency: 150))
        .updateLowpass((m) => m.copyWith(enabled: enabled, frequency: 7500)),
  'exciter' => e.updateAexciter(
    (m) => m.copyWith(enabled: enabled, drive: 2, amount: .25, blend: .05),
  ),
  'echo' => e.updateAecho(
    (m) => m.copyWith(
      enabled: enabled,
      in_gain: 1,
      out_gain: 1,
      delays: '80|160',
      decays: '0.18|0.08',
    ),
  ),
  'deesser' => e.updateDeesser((m) => m.copyWith(enabled: enabled)),
  'declip' => e.updateAdeclip((m) => m.copyWith(enabled: enabled)),
  'arnndn' => e.copyWith(
    arnndn: ArnndnSettings(enabled: enabled, model: model ?? ''),
  ),
  _ => throw ArgumentError.value(id, 'id', 'Unknown music effect'),
};
