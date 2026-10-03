import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:provider/provider.dart';

import '../services/interaction_performance_controller.dart';
import '../theme/theme_motion.dart';
import '../theme/theme_provider.dart';
import 'artwork_image.dart';

/// Maps the existing user-facing 0–40 strength to a true Gaussian standard
/// deviation. A wider sigma removes recognizable cover details while keeping
/// the setting range and persisted values backward compatible.
double backgroundGaussianSigma(double strength) {
  final normalized = strength.clamp(0.0, 40.0);
  if (normalized <= 0) return 0;
  return (normalized * 2.25).clamp(0.0, 90.0);
}

final Map<double, ui.ImageFilter> _backgroundBlurFilters = {};
final LinkedHashMap<String, Uint8List> _preblurredBackgrounds = LinkedHashMap();
const _maximumPreblurredBackgrounds = 4;

ui.ImageFilter _cachedBackgroundBlur(double sigma) {
  final cacheKey = (sigma * 4).round() / 4;
  return _backgroundBlurFilters.putIfAbsent(
    cacheKey,
    () => ui.ImageFilter.blur(
      sigmaX: cacheKey,
      sigmaY: cacheKey,
      tileMode: TileMode.mirror,
    ),
  );
}

class CustomThemeBackground extends StatefulWidget {
  const CustomThemeBackground({
    super.key,
    required this.path,
    required this.enabled,
    required this.dim,
    required this.child,
    this.coverBytes,
    this.coverEnabled = false,
    this.blurSigma = 22,
    this.coverBlurSigma = 22,
    this.coverDim = 0.56,
    this.brightnessOverride,
  });

  final String? path;
  final bool enabled;
  final double dim;
  final Widget child;
  final Uint8List? coverBytes;
  final bool coverEnabled;
  final double blurSigma;
  final double coverBlurSigma;
  final double coverDim;
  final Brightness? brightnessOverride;

  @override
  State<CustomThemeBackground> createState() => _CustomThemeBackgroundState();
}

class _CustomThemeBackgroundState extends State<CustomThemeBackground> {
  String? _requestedBlurKey;
  Uint8List? _preblurredBytes;
  Object? _preparationInputs;
  int _preblurGeneration = 0;

  bool get _canShowCover =>
      widget.coverEnabled &&
      widget.coverBytes != null &&
      widget.coverBytes!.isNotEmpty;

  bool get _canShowCustomImage {
    final value = widget.path;
    return widget.enabled && value != null && value.isNotEmpty;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePreblurPreparation();
  }

  @override
  void didUpdateWidget(covariant CustomThemeBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePreblurPreparation();
  }

  void _schedulePreblurPreparation() {
    // Widget tests use a fake clock and deliberately reject timers left by
    // deferred idle work. The optimized bitmap is only a runtime performance
    // cache, so keeping the deterministic live-blur fallback in tests is
    // sufficient and avoids making every unrelated widget test drain it.
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    final viewport = MediaQuery.sizeOf(context);
    final inputs = Object.hash(
      widget.path,
      widget.enabled,
      widget.coverEnabled,
      identityHashCode(widget.coverBytes),
      widget.blurSigma,
      widget.coverBlurSigma,
      viewport.width,
      viewport.height,
    );
    if (_preparationInputs == inputs) return;
    _preparationInputs = inputs;
    _requestedBlurKey = null;
    _preblurredBytes = null;
    final generation = ++_preblurGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _preblurGeneration) return;
      _preparePreblurredBackground(generation);
    });
  }

  Future<void> _preparePreblurredBackground(int generation) async {
    final showCover = _canShowCover;
    if (!showCover && !_canShowCustomImage) return;
    final strength = showCover ? widget.coverBlurSigma : widget.blurSigma;
    final effectiveBlur = backgroundGaussianSigma(strength);
    if (effectiveBlur < 8) {
      _requestedBlurKey = null;
      _preblurredBytes = null;
      return;
    }

    final viewport = MediaQuery.sizeOf(context);
    if (viewport.isEmpty ||
        !viewport.width.isFinite ||
        !viewport.height.isFinite) {
      return;
    }
    final targetWidth = (viewport.width * .9).round().clamp(320, 480).toInt();
    final targetHeight = (targetWidth * viewport.height / viewport.width)
        .round()
        .clamp(320, 960)
        .toInt();
    final radius = (effectiveBlur * targetWidth / viewport.width * .80)
        .round()
        .clamp(2, 72)
        .toInt();
    final sourceIdentity = showCover
        ? 'cover:${_sampledBytesFingerprint(widget.coverBytes!)}'
        : 'file:${widget.path}';
    final key = '$sourceIdentity@$targetWidth:$targetHeight:r$radius';
    if (_requestedBlurKey == key && _preblurredBytes != null) return;
    final cached = _preblurredBackgrounds.remove(key);
    if (cached != null) {
      _preblurredBackgrounds[key] = cached;
      if (!mounted || generation != _preblurGeneration) return;
      setState(() {
        _requestedBlurKey = key;
        _preblurredBytes = cached;
      });
      return;
    }

    _requestedBlurKey = key;
    final lease = await InteractionPerformanceController.instance
        .acquireIdleWork(
          priority: InteractionWorkPriority.background,
          isStillNeeded: () =>
              mounted &&
              generation == _preblurGeneration &&
              _requestedBlurKey == key,
        );
    try {
      if (!lease.isGranted ||
          !mounted ||
          generation != _preblurGeneration ||
          _requestedBlurKey != key) {
        return;
      }
      final source = showCover
          ? widget.coverBytes!
          : await File(widget.path!).readAsBytes();
      if (!mounted || generation != _preblurGeneration) return;
      final result = await compute(
        _createPreblurredBackground,
        <String, Object>{
          'bytes': source,
          'width': targetWidth,
          'height': targetHeight,
          'radius': radius,
        },
      );
      if (result == null ||
          !mounted ||
          generation != _preblurGeneration ||
          _requestedBlurKey != key) {
        return;
      }
      final provider = MemoryImage(result);
      await precacheImage(provider, context);
      if (!mounted || generation != _preblurGeneration) return;
      _preblurredBackgrounds.remove(key);
      _preblurredBackgrounds[key] = result;
      while (_preblurredBackgrounds.length > _maximumPreblurredBackgrounds) {
        _preblurredBackgrounds.remove(_preblurredBackgrounds.keys.first);
      }
      setState(() => _preblurredBytes = result);
    } catch (_) {
      // Keep the existing live blur as a visual fallback when a custom image
      // is unreadable or a device cannot complete the background preparation.
    } finally {
      lease.release();
    }
  }

  @override
  void dispose() {
    _preblurGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showCover = _canShowCover;
    if (!showCover && !_canShowCustomImage) return widget.child;
    final mode = context.watch<ThemeProvider?>()?.effectiveThemeMode;
    final dark = widget.brightnessOverride != null
        ? widget.brightnessOverride == Brightness.dark
        : switch (mode) {
            ThemeMode.light => false,
            ThemeMode.dark => true,
            ThemeMode.system =>
              MediaQuery.platformBrightnessOf(context) == Brightness.dark,
            null => Theme.of(context).brightness == Brightness.dark,
          };
    final effectiveBlur = backgroundGaussianSigma(
      showCover ? widget.coverBlurSigma : widget.blurSigma,
    );
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final customImageCacheWidth = effectiveBlur > 0
        ? 512
        : (viewportWidth * devicePixelRatio).round().clamp(720, 2048);
    final prepared = effectiveBlur >= 8 ? _preblurredBytes : null;
    Widget backgroundImage = prepared != null
        ? Image.memory(
            prepared,
            key: ValueKey('preblurred-theme-background-$_requestedBlurKey'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
          )
        : showCover
        ? ArtworkImage(
            bytes: widget.coverBytes!,
            size: ArtworkSize.medium,
            key: const ValueKey('cover-follow-background'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          )
        : Image.file(
            File(widget.path!),
            key: ValueKey('custom-theme-background-${widget.path}'),
            fit: BoxFit.cover,
            cacheWidth: customImageCacheWidth,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          );
    if (effectiveBlur > 0 && prepared == null) {
      backgroundImage = ClipRect(
        child: Transform.scale(
          scale: (1 + effectiveBlur / 450).clamp(1.0, 1.20),
          child: ImageFiltered(
            imageFilter: _cachedBackgroundBlur(effectiveBlur),
            child: backgroundImage,
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: backgroundImage),
        AnimatedContainer(
          duration: ThemeMotion.transitionDuration,
          curve: ThemeMotion.transitionCurve,
          color: (dark ? Colors.black : Colors.white).withValues(
            alpha: (showCover ? widget.coverDim : widget.dim).clamp(0.0, 0.92),
          ),
        ),
        widget.child,
      ],
    );
  }
}

int _sampledBytesFingerprint(Uint8List bytes) {
  var fingerprint = 0x811C9DC5;
  final stride = (bytes.length / 64).ceil().clamp(1, bytes.length);
  for (var index = 0; index < bytes.length; index += stride) {
    fingerprint ^= bytes[index];
    fingerprint = (fingerprint * 0x01000193) & 0xFFFFFFFF;
  }
  return Object.hash(bytes.length, fingerprint);
}

Uint8List? _createPreblurredBackground(Map<String, Object> request) {
  final source = image.decodeImage(request['bytes']! as Uint8List);
  if (source == null || source.width <= 0 || source.height <= 0) return null;
  final width = request['width']! as int;
  final height = request['height']! as int;
  final radius = request['radius']! as int;
  final scale = mathMax(width / source.width, height / source.height);
  final resizedWidth = (source.width * scale).ceil().clamp(width, 4096).toInt();
  final resizedHeight = (source.height * scale)
      .ceil()
      .clamp(height, 4096)
      .toInt();
  final resized = image.copyResize(
    source,
    width: resizedWidth,
    height: resizedHeight,
    interpolation: image.Interpolation.linear,
  );
  final cropped = image.copyCrop(
    resized,
    x: ((resized.width - width) / 2).round(),
    y: ((resized.height - height) / 2).round(),
    width: width,
    height: height,
  );
  final blurred = image.gaussianBlur(cropped, radius: radius);
  return Uint8List.fromList(image.encodeJpg(blurred, quality: 82));
}

double mathMax(double first, double second) => first > second ? first : second;
