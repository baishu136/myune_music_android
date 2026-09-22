import 'dart:collection';
import 'dart:typed_data';

import 'package:colorgram/colorgram.dart';
import 'package:flutter/material.dart';

import '../models/fluid_background_state.dart';

final fluidArtworkPaletteCache = ArtworkPaletteCache();

String fluidArtworkPaletteKey(
  String artworkIdentity,
  int cacheGeneration,
  Uint8List bytes,
) {
  if (bytes.isEmpty) return '$artworkIdentity@$cacheGeneration:empty';
  // Sample the encoded bytes instead of hashing a potentially multi-megabyte
  // cover on the UI isolate. The cache generation handles global invalidation.
  var fingerprint = 0x811C9DC5;
  final stride = (bytes.length / 64).ceil().clamp(1, bytes.length);
  for (var index = 0; index < bytes.length; index += stride) {
    fingerprint ^= bytes[index];
    fingerprint = (fingerprint * 0x01000193) & 0xFFFFFFFF;
  }
  return '$artworkIdentity@$cacheGeneration:${bytes.length}:$fingerprint';
}

class ArtworkPaletteCache {
  ArtworkPaletteCache({this.maximumEntries = 64});

  final int maximumEntries;
  final LinkedHashMap<String, FluidPalette> _cache = LinkedHashMap();
  final Map<String, Future<FluidPalette>> _requests = {};

  int get length => _cache.length;

  FluidPalette? peek(String key) {
    final cached = _cache.remove(key);
    if (cached == null) return null;
    _cache[key] = cached;
    return cached;
  }

  void remember(String key, FluidPalette palette) {
    _cache.remove(key);
    _cache[key] = palette;
    while (_cache.length > maximumEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<FluidPalette> resolve({
    required String key,
    required Uint8List bytes,
    required Color fallbackSeed,
  }) {
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached);
    }
    final pending = _requests[key];
    if (pending != null) return pending;

    final request = _extract(bytes, fallbackSeed);
    _requests[key] = request;
    request
        .then((palette) {
          remember(key, palette);
        }, onError: (_) {})
        .whenComplete(() {
          if (identical(_requests[key], request)) _requests.remove(key);
        });
    return request;
  }

  Future<FluidPalette> _extract(Uint8List bytes, Color fallbackSeed) async {
    try {
      final extracted = await extractColor(MemoryImage(bytes), 8);
      final samples = extracted
          .map(
            (value) => FluidColorSample(
              Color.fromRGBO(value.r, value.g, value.b, 1),
              value.percentage.toDouble(),
            ),
          )
          .toList(growable: false);
      return buildWeightedFluidPalette(samples, fallbackSeed: fallbackSeed);
    } catch (_) {
      return FluidPalette.fallback(fallbackSeed);
    }
  }

  void clear() {
    _cache.clear();
  }
}

@immutable
class FluidColorSample {
  const FluidColorSample(this.color, this.proportion);

  final Color color;
  final double proportion;
}

FluidPalette buildFluidPalette(
  List<Color> extracted, {
  required Color fallbackSeed,
}) {
  final equalShare = extracted.isEmpty ? 0.0 : 1 / extracted.length;
  return buildWeightedFluidPalette(
    extracted
        .map((color) => FluidColorSample(color, equalShare))
        .toList(growable: false),
    fallbackSeed: fallbackSeed,
  );
}

FluidPalette buildWeightedFluidPalette(
  List<FluidColorSample> extracted, {
  required Color fallbackSeed,
}) {
  final profile = _classifyArtwork(extracted);
  final selected = _selectDominantFluidColors(
    extracted.map((sample) => sample.color).toList(growable: false),
    fallbackSeed: fallbackSeed,
    profile: profile,
  );
  // Occupancy is deliberately not carried into the shader. The extraction
  // percentages only classify the artwork style; every retained main colour
  // receives an equal low-frequency field so accents cannot disappear.
  final retained = selected.take(4).toList(growable: true);
  final fallback = FluidPalette.fallback(fallbackSeed);
  while (retained.length < 4) {
    retained.add(fallback[retained.length]);
  }
  return FluidPalette(retained[0], retained[1], retained[2], retained[3]);
}

class _FluidArtworkProfile {
  const _FluidArtworkProfile({required this.vivid, required this.dark});

  final bool vivid;
  final bool dark;
}

_FluidArtworkProfile _classifyArtwork(List<FluidColorSample> samples) {
  var total = 0.0;
  var saturation = 0.0;
  var lightness = 0.0;
  var colourfulShare = 0.0;
  for (final sample in samples) {
    if (HSLColor.fromColor(sample.color).lightness > .96) continue;
    final weight = sample.proportion.clamp(0.0, 1.0);
    final hsl = HSLColor.fromColor(sample.color);
    total += weight;
    saturation += hsl.saturation * weight;
    lightness += hsl.lightness * weight;
    if (hsl.saturation >= .38) colourfulShare += weight;
  }
  if (total <= 0) {
    return const _FluidArtworkProfile(vivid: false, dark: false);
  }
  return _FluidArtworkProfile(
    vivid: saturation / total >= .34 || colourfulShare / total >= .42,
    dark: lightness / total < .28,
  );
}

Color _normalizeFluidColor(Color color, _FluidArtworkProfile profile) {
  final hsl = HSLColor.fromColor(color);
  // A genuinely black cover region is meaningful visual information. Keep it
  // black instead of coercing every artwork into a coloured grey background.
  if (hsl.lightness < .018 && hsl.saturation < .08) return Colors.black;
  final normalizedLightness = profile.dark
      ? hsl.lightness.clamp(0.0, profile.vivid ? .50 : .43)
      : hsl.lightness.clamp(.10, profile.vivid ? .68 : .62);
  final normalizedSaturation = hsl.saturation < .08
      ? hsl.saturation
      : profile.vivid
      ? hsl.saturation.clamp(.34, .88)
      : hsl.saturation.clamp(.08, .42);
  return hsl
      .withSaturation(normalizedSaturation)
      .withLightness(normalizedLightness)
      .toColor();
}

bool _isUsableFluidColor(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.lightness <= .96;
}

List<Color> selectDominantFluidColors(
  List<Color> extracted, {
  required Color fallbackSeed,
}) {
  final share = extracted.isEmpty ? 0.0 : 1 / extracted.length;
  return _selectDominantFluidColors(
    extracted,
    fallbackSeed: fallbackSeed,
    profile: _classifyArtwork(
      extracted
          .map((color) => FluidColorSample(color, share))
          .toList(growable: false),
    ),
  );
}

List<Color> _selectDominantFluidColors(
  List<Color> extracted, {
  required Color fallbackSeed,
  required _FluidArtworkProfile profile,
}) {
  final candidates = <Color>[];
  for (final color in extracted) {
    if (!_isUsableFluidColor(color)) continue;
    final normalized = _normalizeFluidColor(color, profile);
    if (candidates.every((other) => _colorDistance(other, normalized) > .10)) {
      candidates.add(normalized);
    }
  }
  final fallback = FluidPalette.fallback(fallbackSeed);
  if (candidates.isEmpty) return fallback.colors.take(3).toList();

  final selected = <Color>[candidates.first];
  while (selected.length < 6 && selected.length < candidates.length) {
    Color? best;
    var bestDistance = -1.0;
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      if (selected.contains(candidate)) continue;
      final nearest = selected
          .map((color) => _colorDistance(color, candidate))
          .reduce((first, second) => first < second ? first : second);
      // colorgram returns dominant colors first. A small rank penalty rejects
      // isolated tail noise without overpowering useful colour diversity.
      final score = nearest - index * .012;
      if (score > bestDistance) {
        bestDistance = score;
        best = candidate;
      }
    }
    if (best == null) break;
    selected.add(best);
  }

  final selectedFallback = FluidPalette.fallback(selected.first);
  while (selected.length < 3) {
    selected.add(selectedFallback[selected.length]);
  }
  selected.sort((first, second) {
    final firstHsl = HSLColor.fromColor(first);
    final secondHsl = HSLColor.fromColor(second);
    final hue = firstHsl.hue.compareTo(secondHsl.hue);
    return hue != 0 ? hue : firstHsl.lightness.compareTo(secondHsl.lightness);
  });
  return selected;
}

double _colorDistance(Color first, Color second) {
  final a = HSLColor.fromColor(first);
  final b = HSLColor.fromColor(second);
  final rawHue = (a.hue - b.hue).abs();
  final hue = (rawHue > 180 ? 360 - rawHue : rawHue) / 180;
  return hue * (.2 + .8 * (a.saturation + b.saturation) / 2) * .55 +
      (a.saturation - b.saturation).abs() * .25 +
      (a.lightness - b.lightness).abs() * .20;
}
