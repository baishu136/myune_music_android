import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
  ArtworkPaletteCache({this.maximumEntries = 64}) : assert(maximumEntries > 0);

  final int maximumEntries;
  final LinkedHashMap<String, FluidPalette> _cache = LinkedHashMap();
  final Map<String, Future<FluidPalette>> _requests = {};
  int _generation = 0;

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
    final generation = _generation;
    _requests[key] = request;
    request
        .then((palette) {
          if (generation == _generation) remember(key, palette);
        }, onError: (_) {})
        .whenComplete(() {
          if (identical(_requests[key], request)) _requests.remove(key);
        });
    return request;
  }

  Future<FluidPalette> _extract(Uint8List bytes, Color fallbackSeed) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      // Bound readback and CPU work independently of the original cover size.
      // Unlike ImageProvider listeners, codec/image ownership is explicit.
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 64,
        targetHeight: 64,
        allowUpscaling: false,
      );
      image = (await codec.getNextFrame()).image;
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return FluidPalette.fallback(fallbackSeed);
      final samples = await compute(
        _sampleArtwork,
        rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      );
      return buildWeightedFluidPalette(samples, fallbackSeed: fallbackSeed);
    } catch (_) {
      return FluidPalette.fallback(fallbackSeed);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  void clear() {
    _generation++;
    _cache.clear();
    _requests.clear();
  }
}

// A small 4-bit/channel histogram on a worker isolate. Alpha padding does not
// become fake black; proportions refer to all visible pixels, not just top bins.
List<FluidColorSample> _sampleArtwork(Uint8List rgba) {
  final bins = Int32List(4096 * 4);
  var pixels = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    pixels++;
    // Reject paper/achromatic highlights BEFORE quantization. Their area still
    // counts in occupancy, so a tiny warm speck does not become a major accent.
    if (_isAchromaticHighlight(r / 255, g / 255, b / 255)) continue;
    final slot = (((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)) * 4;
    bins[slot] += r;
    bins[slot + 1] += g;
    bins[slot + 2] += b;
    bins[slot + 3]++;
  }
  if (pixels == 0) return const [];
  final occupied = <int>[];
  for (var slot = 0; slot < bins.length; slot += 4) {
    if (bins[slot + 3] > 0) occupied.add(slot);
  }
  // An entirely white image is real achromatic artwork, not missing artwork.
  // Keep a neutral fallback rather than importing the app's coloured seed.
  if (occupied.isEmpty) return const [FluidColorSample(Color(0xFF616161), 1)];
  occupied.sort((a, b) => bins[b + 3].compareTo(bins[a + 3]));
  // A warm region can be spread across many small histogram bins. Pool only
  // real 20–55° pixels on the worker so its total area survives top-32 pruning;
  // otherwise a sizeable golden gradient can disappear behind large cool bins.
  var warmR = 0, warmG = 0, warmB = 0, warmPixels = 0;
  int? warmRepresentative;
  var warmScore = 0.0;
  final warmSlots = <int>{};
  for (final slot in occupied) {
    final count = bins[slot + 3];
    final color = Color.fromARGB(
      255,
      bins[slot] ~/ count,
      bins[slot + 1] ~/ count,
      bins[slot + 2] ~/ count,
    );
    if (!_isWarmAccent(color)) continue;
    warmSlots.add(slot);
    warmR += bins[slot];
    warmG += bins[slot + 1];
    warmB += bins[slot + 2];
    warmPixels += count;
    final hsl = HSLColor.fromColor(color);
    final score = count * hsl.saturation * hsl.lightness * (1 - hsl.lightness);
    if (score > warmScore) {
      warmScore = score;
      warmRepresentative = slot;
    }
  }
  final poolWarm = warmPixels / pixels >= _significantWarmShare;
  final samples = occupied
      .where((slot) => !poolWarm || !warmSlots.contains(slot))
      .take(poolWarm ? 30 : 32)
      .map((slot) {
        final count = bins[slot + 3];
        return FluidColorSample(
          Color.fromARGB(
            255,
            bins[slot] ~/ count,
            bins[slot + 1] ~/ count,
            bins[slot + 2] ~/ count,
          ),
          count / pixels,
        );
      })
      .toList(growable: true);
  if (poolWarm) {
    // Keep the substantial, chromatic warm bin itself (e.g. gold printing).
    // Pool ONLY its remaining neighbours, with their own area. Averaging all
    // warm pixels together let pale skin/antialiasing bleach a real gold accent.
    final slot = warmRepresentative!;
    final count = bins[slot + 3];
    samples.add(
      FluidColorSample(
        Color.fromARGB(
          255,
          bins[slot] ~/ count,
          bins[slot + 1] ~/ count,
          bins[slot + 2] ~/ count,
        ),
        count / pixels,
      ),
    );
    warmR -= bins[slot];
    warmG -= bins[slot + 1];
    warmB -= bins[slot + 2];
    warmPixels -= count;
    if (warmPixels > 0) {
      samples.add(
        FluidColorSample(
          Color.fromARGB(
            255,
            warmR ~/ warmPixels,
            warmG ~/ warmPixels,
            warmB ~/ warmPixels,
          ),
          warmPixels / pixels,
        ),
      );
    }
    samples.sort((a, b) => b.proportion.compareTo(a.proportion));
  }
  return samples;
}

const _significantWarmShare = .03;

bool _isAchromaticHighlight(double r, double g, double b) {
  final maximum = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final minimum = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final lightness = (maximum + minimum) / 2;
  if (lightness <= .88) return false;
  final delta = maximum - minimum;
  final saturation = delta == 0 ? 0.0 : delta / (2 - maximum - minimum);
  return saturation < .20;
}

bool _isWarmAccent(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.hue >= 20 &&
      hsl.hue <= 55 &&
      hsl.saturation >= .20 &&
      hsl.lightness >= .08 &&
      hsl.lightness <= .90;
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
  if (extracted.isEmpty) return FluidPalette.fallback(fallbackSeed);
  final pigments = extracted
      .where((s) => !_isAchromaticHighlight(s.color.r, s.color.g, s.color.b))
      .toList(growable: false);
  if (pigments.isEmpty) {
    return buildWeightedFluidPalette(const [
      FluidColorSample(Color(0xFF616161), 1),
    ], fallbackSeed: fallbackSeed);
  }
  extracted = pigments;
  final profile = _classifyArtwork(extracted);
  final selected = _selectDominantFluidColors(
    extracted.map((sample) => sample.color).toList(growable: false),
    fallbackSeed: fallbackSeed,
    profile: profile,
    maximumColors: 4,
  );
  // Occupancy selects/classifies the palette, never scales per-frame fields.
  final retained = selected.take(4).toList(growable: true);
  while (retained.length < 4) {
    retained.add(retained[retained.length % selected.length]);
  }
  final warm = _significantWarmAccent(extracted, profile);
  if (warm != null) {
    var replace = retained.indexWhere(
      (color) => _colorDistance(color, warm) < .10,
    );
    if (replace < 0) {
      // Preserve the dominant region (including meaningful black) and replace
      // the least distinct auxiliary colour, not pink/teal just due to hue order.
      final dominant = _normalizeFluidColor(
        extracted.reduce((a, b) => a.proportion >= b.proportion ? a : b).color,
        profile,
      );
      var weakest = double.infinity;
      replace = 3;
      for (var i = 0; i < retained.length; i++) {
        if (_colorDistance(retained[i], dominant) < .05) continue;
        var nearest = double.infinity;
        for (var j = 0; j < retained.length; j++) {
          if (i == j) continue;
          final distance = _colorDistance(retained[i], retained[j]);
          if (distance < nearest) nearest = distance;
        }
        final score =
            nearest + HSLColor.fromColor(retained[i]).saturation * .10;
        if (score < weakest) {
          weakest = score;
          replace = i;
        }
      }
    }
    retained.removeAt(replace);
    retained.insert(2, warm);
  }
  // Blob 1 must contain a real, substantial vivid pigment, not
  // whichever grey happened to land second after hue sorting. Only boost c1;
  // leave genuine shadows/neutral auxiliaries and the real warm c2 unchanged.
  var vividAccentLocked = false;
  if (profile.vivid && !profile.dark && !profile.monochrome) {
    var hero = -1;
    var bestScore = 0.0;
    for (var i = 0; i < retained.length; i++) {
      if (warm != null && i == 2) continue;
      final hsl = HSLColor.fromColor(retained[i]);
      if (hsl.saturation < .20 || hsl.lightness < .08) continue;
      var score = 0.0;
      for (final sample in extracted) {
        final normalized = _normalizeFluidColor(sample.color, profile);
        if (_colorDistance(retained[i], normalized) < .10) {
          score +=
              sample.proportion.clamp(0.0, 1.0) *
              HSLColor.fromColor(sample.color).saturation;
        }
      }
      if (score > bestScore) {
        hero = i;
        bestScore = score;
      }
    }
    if (hero >= 0) {
      final color = retained[hero];
      retained[hero] = retained[1];
      retained[1] = HSLColor.fromColor(color)
          .withSaturation(HSLColor.fromColor(color).saturation.clamp(.70, .95))
          .withLightness(HSLColor.fromColor(color).lightness.clamp(.35, .55))
          .toColor();
      vividAccentLocked = true;
    }
  }
  // Assign a real contrasting pigment to blob 2, rather than leaving whichever
  // auxiliary grey happens to occupy slot 3. Pool/selection happens per cover,
  // never in paint. A single-hue or monochrome cover does not invent a hue.
  final lead = HSLColor.fromColor(retained[1]);
  Color? contrast;
  var contrastScore = -1.0;
  for (final sample in extracted) {
    final hsl = HSLColor.fromColor(sample.color);
    if (sample.proportion < .01 || hsl.saturation < .20 || hsl.lightness < .025) {
      continue;
    }
    final rawHue = (lead.hue - hsl.hue).abs();
    final hueDistance = (rawHue > 180 ? 360 - rawHue : rawHue) / 180;
    final score =
        hueDistance * .70 + hsl.saturation * .20 + sample.proportion * .10;
    if (score > contrastScore) {
      contrastScore = score;
      contrast = _normalizeFluidColor(sample.color, profile);
    }
  }
  if (contrast != null && !profile.monochrome) retained[3] = contrast;
  if (profile.vivid && !profile.dark && !profile.monochrome) {
    for (final slot in [1, 3]) {
      final hsl = HSLColor.fromColor(retained[slot]);
      if (hsl.saturation < .20 || hsl.lightness < .08) continue;
      retained[slot] = hsl
          .withSaturation(hsl.saturation.clamp(.75, .85))
          .withLightness(hsl.lightness.clamp(.35, .55))
          .toColor();
    }
  }
  var darkest = retained.first;
  for (final color in retained) {
    if (HSLColor.fromColor(color).lightness <
        HSLColor.fromColor(darkest).lightness) {
      darkest = color;
    }
  }
  final baseHsl = HSLColor.fromColor(darkest);
  final canvasHsl = profile.dark ? baseHsl : HSLColor.fromColor(retained[1]);
  final base = profile.monochrome
      ? HSLColor.fromAHSL(1, 0, 0, profile.dark ? 0 : .045).toColor()
      : canvasHsl
            .withLightness(
              profile.dark
                  ? (canvasHsl.lightness * .08).clamp(0.0, .012)
                  : (canvasHsl.lightness * .50).clamp(.12, .26),
            )
            .toColor();
  return FluidPalette(
    retained[0],
    retained[1],
    retained[2],
    retained[3],
    baseColor: base,
    warmAccentLocked: warm != null,
    vividAccentLocked: vividAccentLocked,
    layeredRolesLocked: true,
    glowStrength: profile.dark
        ? (profile.monochrome ? .28 : (profile.vivid ? .70 : .55))
        // Legacy snapshot/uniform metadata, not additive light energy.
        : (profile.monochrome ? .30 : .50),
  );
}

Color? _significantWarmAccent(
  List<FluidColorSample> samples,
  _FluidArtworkProfile profile,
) {
  if (profile.monochrome) return null;
  var share = 0.0, bestScore = 0.0;
  Color? best;
  for (final sample in samples) {
    if (_isAchromaticHighlight(
      sample.color.r,
      sample.color.g,
      sample.color.b,
    )) {
      continue;
    }
    if (!_isWarmAccent(sample.color)) continue;
    final weight = sample.proportion.clamp(0.0, 1.0);
    share += weight;
    final hsl = HSLColor.fromColor(sample.color);
    final score =
        weight * (.35 + hsl.saturation) * hsl.lightness * (1 - hsl.lightness);
    if (score > bestScore) {
      bestScore = score;
      best = sample.color;
    }
  }
  return share >= _significantWarmShare && best != null
      ? _normalizeFluidColor(best, profile)
      : null;
}

class _FluidArtworkProfile {
  const _FluidArtworkProfile({
    required this.vivid,
    required this.dark,
    required this.monochrome,
  });

  final bool vivid;
  final bool dark;
  final bool monochrome;
}

_FluidArtworkProfile _classifyArtwork(List<FluidColorSample> samples) {
  var total = 0.0;
  var saturation = 0.0;
  var lightness = 0.0;
  var colourfulShare = 0.0;
  var chromatic = false;
  for (final sample in samples) {
    final weight = sample.proportion.clamp(0.0, 1.0);
    final hsl = HSLColor.fromColor(sample.color);
    if (weight > .001 &&
        hsl.saturation >= .10 &&
        (hsl.lightness * (1 - hsl.lightness) * hsl.saturation) > .008) {
      chromatic = true;
    }
    total += weight;
    saturation += hsl.saturation * weight;
    lightness += hsl.lightness * weight;
    if (hsl.saturation >= .38) colourfulShare += weight;
  }
  if (total <= 0) {
    return const _FluidArtworkProfile(
      vivid: false,
      dark: false,
      monochrome: true,
    );
  }
  return _FluidArtworkProfile(
    vivid: saturation / total >= .34 || colourfulShare / total >= .42,
    dark: lightness / total < .28,
    monochrome: !chromatic,
  );
}

Color _normalizeFluidColor(Color color, _FluidArtworkProfile profile) {
  final hsl = HSLColor.fromColor(color);
  // A genuinely black cover region is meaningful visual information. Keep it
  // black instead of coercing every artwork into a coloured grey background.
  if (hsl.lightness < .018 && hsl.saturation < .08) return Colors.black;
  if (profile.monochrome) {
    return hsl
        .withSaturation(0)
        .withLightness(hsl.lightness.clamp(0.0, .38))
        .toColor();
  }
  final normalizedLightness = profile.dark
      ? hsl.lightness.clamp(0.0, .38)
      : hsl.lightness.clamp(
          profile.vivid && hsl.saturation >= .20 && hsl.lightness >= .08
              ? .38
              : .10,
          profile.vivid ? .68 : .58,
        );
  final normalizedSaturation = hsl.saturation < .20
      ? hsl.saturation
      : profile.vivid
      ? hsl.saturation.clamp(.34, .95)
      : hsl.saturation.clamp(.08, .55);
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
  int maximumColors = 6,
}) {
  final candidates = <Color>[];
  final candidateChroma = <double>[];
  for (final color in extracted) {
    if (!_isUsableFluidColor(color) && !profile.monochrome) continue;
    final normalized = _normalizeFluidColor(color, profile);
    final duplicate = candidates.indexWhere(
      (other) => _colorDistance(other, normalized) <= .10,
    );
    final chroma =
        [color.r, color.g, color.b].reduce((a, b) => a > b ? a : b) -
        [color.r, color.g, color.b].reduce((a, b) => a < b ? a : b);
    if (duplicate < 0) {
      candidates.add(normalized);
      candidateChroma.add(chroma);
    } else if (profile.vivid && chroma > candidateChroma[duplicate]) {
      // The first bin can be pale paper/skin of the same hue. Keep the real
      // higher-chroma pigment, rather than discarding it after L clamping made
      // both candidates appear similar. This is cover work, never paint work.
      candidates[duplicate] = normalized;
      candidateChroma[duplicate] = chroma;
    }
  }
  final fallback = FluidPalette.fallback(fallbackSeed);
  if (candidates.isEmpty) {
    return profile.monochrome && extracted.isNotEmpty
        ? const [Color(0xFF101010), Color(0xFF202020), Color(0xFF303030)]
        : fallback.colors.take(3).toList();
  }

  final selected = <Color>[candidates.first];
  // Select the four shader slots BEFORE hue ordering; sorting six candidates
  // then taking four systematically discarded magenta/purple at high hues.
  while (selected.length < maximumColors &&
      selected.length < candidates.length) {
    Color? best;
    var bestDistance = -1.0;
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      if (selected.contains(candidate)) continue;
      final nearest = selected
          .map((color) => _colorDistance(color, candidate))
          .reduce((first, second) => first < second ? first : second);
      // A small occupancy-rank penalty rejects isolated noise. On vivid covers
      // favour real chroma so grey face/shadow bins do not crowd out pink/teal.
      final chroma = profile.vivid
          ? HSLColor.fromColor(candidate).saturation * .20
          : 0.0;
      final score = nearest + chroma - index * .012;
      if (score > bestDistance) {
        bestDistance = score;
        best = candidate;
      }
    }
    if (best == null) break;
    selected.add(best);
  }

  while (selected.length < 3) {
    // Do not invent coloured companions for a black/white or single-hue cover.
    final first = HSLColor.fromColor(selected.first);
    final source = profile.dark && !profile.monochrome && first.lightness < .04
        ? HSLColor.fromColor(selected.last)
        : first;
    selected.add(
      source
          .withLightness(
            (source.lightness * (1 - .12 * selected.length)).clamp(0.0, 1.0),
          )
          .toColor(),
    );
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
