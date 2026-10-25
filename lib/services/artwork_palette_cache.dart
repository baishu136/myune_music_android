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
      return buildWeightedFluidPalette(
        samples.colors,
        fallbackSeed: fallbackSeed,
        artworkLightness: samples.lightness,
      );
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
({List<FluidColorSample> colors, double lightness}) _sampleArtwork(
  Uint8List rgba,
) {
  final bins = Int32List(4096 * 4);
  var pixels = 0;
  var lightnessSum = 0.0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    pixels++;
    final maximum = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final minimum = r < g ? (r < b ? r : b) : (g < b ? g : b);
    lightnessSum += (maximum + minimum) / 510;
    // Reject paper/achromatic highlights BEFORE quantization. Their area still
    // counts in occupancy, so a tiny warm speck does not become a major accent.
    if (_isAchromaticHighlight(r / 255, g / 255, b / 255)) continue;
    final slot = (((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)) * 4;
    bins[slot] += r;
    bins[slot + 1] += g;
    bins[slot + 2] += b;
    bins[slot + 3]++;
  }
  if (pixels == 0) return (colors: const <FluidColorSample>[], lightness: 0);
  final occupied = <int>[];
  for (var slot = 0; slot < bins.length; slot += 4) {
    if (bins[slot + 3] > 0) occupied.add(slot);
  }
  // An entirely white image is real achromatic artwork, not missing artwork.
  // Keep a neutral fallback rather than importing the app's coloured seed.
  if (occupied.isEmpty) {
    return (
      colors: const [FluidColorSample(Color(0xFF616161), 1)],
      lightness: lightnessSum / pixels,
    );
  }
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
  return (colors: samples, lightness: lightnessSum / pixels);
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
  double? artworkLightness,
}) {
  if (extracted.isEmpty) return FluidPalette.fallback(fallbackSeed);
  final totalShare = extracted.fold<double>(0, (sum, s) => sum + s.proportion);
  final visibleLightness =
      artworkLightness ??
      (totalShare > 0
          ? extracted.fold<double>(
                  0,
                  (sum, s) =>
                      sum +
                      HSLColor.fromColor(s.color).lightness * s.proportion,
                ) /
                totalShare
          : 0);
  final hasPigment = extracted.any((sample) {
    final hsl = HSLColor.fromColor(sample.color);
    return sample.proportion >= .03 &&
        hsl.saturation >= .20 &&
        hsl.lightness <= .75;
  });
  final pigments = extracted
      .where((s) => !_isAchromaticHighlight(s.color.r, s.color.g, s.color.b))
      .where(
        (s) =>
            !hasPigment ||
            HSLColor.fromColor(s.color).saturation >= .12 ||
            HSLColor.fromColor(s.color).lightness <= .55 ||
            (visibleLightness >= .55 &&
                HSLColor.fromColor(s.color).lightness <= .80),
      )
      .toList(growable: false);
  if (pigments.isEmpty) {
    return buildWeightedFluidPalette(
      const [FluidColorSample(Color(0xFF616161), 1)],
      fallbackSeed: fallbackSeed,
      artworkLightness: visibleLightness,
    );
  }
  extracted = pigments;
  final profile = _classifyArtwork(extracted, bright: visibleLightness >= .55);
  if (profile.bright && !profile.monochrome) {
    final chromatic = extracted
        .where(
          (s) =>
              HSLColor.fromColor(s.color).saturation >= .12 ||
              HSLColor.fromColor(s.color).lightness >= .22,
        )
        .toList();
    if (chromatic.isNotEmpty) extracted = chromatic;
  }
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
  // Pool nearby hue families so a gradient's many small bins retain their area.
  // Area dominates lead selection; contrast alone cannot promote a tiny speck.
  // Only per-cover work. Keep the observed saturation, not a .75/.85 floor.
  final roles = _artworkBlobPigments(extracted, profile, reservedAccent: warm);
  if (roles != null) {
    void place(Color pigment, int slot) {
      final existing = retained.indexWhere(
        (c) => _colorDistance(c, pigment) < .06,
      );
      if (existing >= 0 && existing != slot) {
        retained[existing] = retained[slot];
      }
      retained[slot] = pigment;
    }

    // Assign roles by permutation, rather than overwriting an unrelated real
    // pigment (e.g. pink disappearing when gold wins companion selection).
    if (retained.contains(Colors.black)) place(Colors.black, 0);
    place(roles.$1, 1);
    if (warm == null || _colorDistance(roles.$2, warm) >= .06) {
      place(roles.$2, 3);
    }
    if (warm != null) place(warm, 2);
  }
  final vividAccentLocked = roles != null && profile.vivid && !profile.dark;
  var darkest = retained.first;
  for (final color in retained) {
    if (HSLColor.fromColor(color).lightness <
        HSLColor.fromColor(darkest).lightness) {
      darkest = color;
    }
  }
  final baseHsl = HSLColor.fromColor(darkest);
  final canvasHsl = profile.bright && !profile.vivid
      ? HSLColor.fromColor(
          _normalizeFluidColor(
            extracted
                .reduce((a, b) => a.proportion >= b.proportion ? a : b)
                .color,
            profile,
          ),
        )
      : profile.dark
      ? baseHsl
      : HSLColor.fromColor(retained[1]);
  final base = profile.monochrome
      ? HSLColor.fromAHSL(
          1,
          0,
          0,
          profile.bright ? .32 : (profile.dark ? 0 : .045),
        ).toColor()
      : canvasHsl
            .withLightness(
              profile.bright
                  ? (canvasHsl.lightness * .60).clamp(.28, .36)
                  : profile.dark
                  ? (canvasHsl.lightness * .08).clamp(0.0, .012)
                  : (baseHsl.lightness * .32).clamp(.01, .14),
            )
            .toColor();
  return FluidPalette(
    fluidSaturationBoost(retained[0]),
    fluidSaturationBoost(retained[1]),
    fluidSaturationBoost(retained[2]),
    fluidSaturationBoost(retained[3]),
    baseColor: fluidSaturationBoost(base),
    warmAccentLocked: warm != null,
    vividAccentLocked: vividAccentLocked,
    layeredRolesLocked: true,
    motionColors: List<Color>.unmodifiable(
      _buildMotionColors(
        retained,
        extracted,
        profile,
        fallbackSeed,
      ).map(fluidSaturationBoost),
    ),
    glowStrength: profile.dark
        ? (profile.monochrome ? .28 : (profile.vivid ? .70 : .55))
        // Legacy snapshot/uniform metadata, not additive light energy.
        : (profile.monochrome ? .30 : .50),
  );
}

List<Color> _buildMotionColors(
  List<Color> retained,
  List<FluidColorSample> samples,
  _FluidArtworkProfile profile,
  Color fallbackSeed,
) {
  final pool = <Color>[retained[1], retained[2], retained[3], retained[0]];
  if (profile.monochrome) {
    final lightness = HSLColor.fromColor(retained[1]).lightness;
    final minimum = profile.bright ? .42 : 0.0;
    final maximum = profile.bright ? .52 : .38;
    final low = (lightness - .035).clamp(minimum, maximum - .07);
    for (var i = 0; i < fluidMotionColourCount; i++) {
      final c = HSLColor.fromAHSL(
        1,
        0,
        0,
        lightness == 0 ? 0 : low + i * .01,
      ).toColor();
      if (i < 4) {
        pool[i] = c;
      } else {
        pool.add(c);
      }
    }
  }
  final extras = _selectDominantFluidColors(
    samples.where((s) => s.proportion >= .015).map((s) => s.color).toList(),
    fallbackSeed: fallbackSeed,
    profile: profile,
    maximumColors: fluidMotionColourCount,
  );
  for (final c in extras) {
    if (pool.length == fluidMotionColourCount) break;
    if (pool.every((other) => _colorDistance(c, other) > .045)) pool.add(c);
  }
  var step = 0;
  while (pool.length < fluidMotionColourCount) {
    final hsl = HSLColor.fromColor(pool[step % 4]);
    final delta = step.isEven ? .035 : -.035;
    pool.add(
      hsl
          .withLightness(
            (hsl.lightness + delta).clamp(
              profile.bright ? (hsl.saturation < .12 ? .40 : .28) : 0.0,
              profile.dark ? .38 : .60,
            ),
          )
          .toColor(),
    );
    step++;
  }
  if (!profile.monochrome && pool.toSet().length < 6) {
    final pigment = retained.reduce(
      (a, b) =>
          HSLColor.fromColor(a).saturation >= HSLColor.fromColor(b).saturation
          ? a
          : b,
    );
    final hsl = HSLColor.fromColor(pigment);
    var attempt = 0;
    for (var i = 1; i < pool.length && pool.toSet().length < 6; i++) {
      if (!pool.take(i).contains(pool[i])) continue;
      Color candidate;
      do {
        attempt++;
        candidate = hsl
            .withLightness(
              (hsl.lightness + attempt * .0125).clamp(
                profile.bright ? .28 : 0.0,
                profile.dark ? .38 : .60,
              ),
            )
            .toColor();
      } while (pool.contains(candidate) && attempt < 48);
      if (!pool.contains(candidate)) pool[i] = candidate;
    }
  }
  // Each field starts from its assigned pigment and visits the same cover pool
  // in a different order. No spatial rainbow or per-frame colour extraction.
  const path = [0, 4, 1, 5, 2, 6, 3, 7];
  return List<Color>.unmodifiable(
    List.generate(4 * fluidMotionColourCount, (i) {
      final field = i ~/ fluidMotionColourCount,
          variant = i % fluidMotionColourCount;
      return pool[path[(variant + field * 2) % fluidMotionColourCount]];
    }),
  );
}

(Color, Color)? _artworkBlobPigments(
  List<FluidColorSample> samples,
  _FluidArtworkProfile profile, {
  Color? reservedAccent,
}) {
  if (profile.monochrome) return null;
  final families = <FluidColorSample>[];
  final familyHues = <double>[];
  for (final sample in samples) {
    final hsl = HSLColor.fromColor(sample.color);
    // Pale paper/skin highlights may inform the base, but must not own a
    // pigment blob and crowd out the actual coloured printing underneath.
    if (sample.proportion <= 0 ||
        hsl.saturation < .12 ||
        hsl.lightness < .025 ||
        hsl.lightness > .85) {
      continue;
    }
    var match = -1;
    for (var i = 0; i < families.length; i++) {
      final family = families[i];
      final other = HSLColor.fromColor(family.color);
      // Changing the representative must not drift the family hue anchor.
      final delta = (hsl.hue - familyHues[i]).abs();
      if ((delta > 180 ? 360 - delta : delta) <= 18 &&
          (hsl.saturation - other.saturation).abs() <= .24 &&
          (hsl.lightness - other.lightness).abs() <= .20) {
        match = i;
        break;
      }
    }
    if (match < 0) {
      families.add(sample);
      familyHues.add(hsl.hue);
    } else {
      final family = families[match];
      double chroma(Color c) {
        final values = [c.r, c.g, c.b]..sort();
        return values.last - values.first;
      }

      families[match] = FluidColorSample(
        chroma(sample.color) > chroma(family.color)
            ? sample.color
            : family.color,
        family.proportion + sample.proportion,
      );
    }
  }
  // A sole pigment cannot supply two distinct roles. Keep the original
  // monochromatic/pale auxiliaries instead of duplicating it over both slots.
  if (families.length < 2) return null;
  double areaScore(FluidColorSample s) =>
      s.proportion * (.75 + .25 * HSLColor.fromColor(s.color).saturation);
  families.sort((a, b) => areaScore(b).compareTo(areaScore(a)));
  final lead = families.first;
  final total = samples.fold<double>(
    0,
    (sum, sample) => sum + sample.proportion,
  );
  var companion = lead;
  var bestScore = -1.0;
  final leadHue = HSLColor.fromColor(lead.color).hue;
  for (final sample in families.skip(1)) {
    if (sample.proportion < total * .03) continue;
    // The dedicated warm slot already owns gold. Prefer another observed hue
    // for its companion when available, keeping four distinguishable fields.
    if (reservedAccent != null &&
        _colorDistance(
              _normalizeFluidColor(sample.color, profile),
              reservedAccent,
            ) <
            .06) {
      continue;
    }
    final delta = (leadHue - HSLColor.fromColor(sample.color).hue).abs();
    final hue = (delta > 180 ? 360 - delta : delta) / 180;
    final score = (sample.proportion / lead.proportion) * (.45 + .55 * hue);
    if (score > bestScore) {
      bestScore = score;
      companion = sample;
    }
  }
  Color pigment(Color color) {
    return _normalizeFluidColor(color, profile);
  }

  return (pigment(lead.color), pigment(companion.color));
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
    this.bright = false,
  });

  final bool vivid;
  final bool dark;
  final bool monochrome;
  final bool bright;
}

_FluidArtworkProfile _classifyArtwork(
  List<FluidColorSample> samples, {
  bool bright = false,
}) {
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
    dark: !bright && lightness / total < .28,
    monochrome: !chromatic,
    bright: bright,
  );
}

Color _normalizeFluidColor(Color color, _FluidArtworkProfile profile) {
  final hsl = HSLColor.fromColor(color);
  // A genuinely black cover region is meaningful visual information. Keep it
  // black instead of coercing every artwork into a coloured grey background.
  if (!profile.bright && hsl.lightness < .018 && hsl.saturation < .08) {
    return Colors.black;
  }
  if (profile.monochrome) {
    return hsl
        .withSaturation(0)
        .withLightness(
          hsl.lightness.clamp(
            profile.bright ? .42 : 0.0,
            profile.bright ? .52 : .38,
          ),
        )
        .toColor();
  }
  // Never brighten a shadow to the vivid-cover .38 floor. It removes actual
  // dark regions and makes pale auxiliary bins look like white light sources.
  final normalizedLightness = profile.bright
      ? (hsl.lightness * .94).clamp(
          hsl.saturation < .12 ? .42 : .28,
          profile.vivid ? .58 : .52,
        )
      : profile.dark
      ? hsl.lightness.clamp(0.0, .38)
      : (hsl.lightness < .28 ? hsl.lightness : hsl.lightness * .90).clamp(
          0.0,
          profile.vivid ? .58 : .48,
        );
  final normalizedSaturation = hsl.saturation < .20
      ? hsl.saturation
      : profile.vivid
      ? (hsl.saturation * 1.08).clamp(0.0, .94)
      : (hsl.saturation * 1.06).clamp(0.0, .65);
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
            (source.lightness * (1 - .12 * selected.length)).clamp(
              profile.bright ? (source.saturation < .12 ? .42 : .28) : 0.0,
              1.0,
            ),
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
