import 'package:flutter/material.dart';

/// The player's Material sheet, using the same route for movement and opacity.
Future<T?> showPlaybackBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  Clip? clipBehavior,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  AnimationStyle? sheetAnimationStyle,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return navigator.push<T>(
    _PlaybackBottomSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      backgroundColor: backgroundColor,
      shape: shape,
      clipBehavior: clipBehavior,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      sheetAnimationStyle: reduceMotion
          ? AnimationStyle.noAnimation
          : sheetAnimationStyle,
      reduceMotion: reduceMotion,
    ),
  );
}

class _PlaybackBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _PlaybackBottomSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    required this.reduceMotion,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
    super.backgroundColor,
    super.shape,
    super.clipBehavior,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    super.useSafeArea,
    super.sheetAnimationStyle,
  });

  final bool reduceMotion;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion || MediaQuery.disableAnimationsOf(context)) return child;
    // Fade the complete Material surface, including handle/border/blur. The
    // existing sheet route owns the clock and drag; no second controller or
    // direction-dependent curve can jump when a dismissal is cancelled.
    return FadeTransition(
      key: const ValueKey('playback-bottom-sheet-fade'),
      opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
      child: child,
    );
  }
}
