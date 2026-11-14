import 'package:flutter/material.dart';

const playbackSheetOpacityCurve = Curves.easeInCubic;
const playbackSheetTextOpacityCurve = Curves.easeOutCubic;

/// Fade only the backdrop/fill. Foreground content stays opaque and follows
/// the sheet's original slide. One reversible mapping also supports drag cancel.
class PlaybackSheetBackgroundFade extends StatelessWidget {
  const PlaybackSheetBackgroundFade({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null) return child;
    return FadeTransition(
      key: const ValueKey('playback-sheet-background-fade'),
      opacity: animation.drive(CurveTween(curve: playbackSheetOpacityCurve)),
      child: child,
    );
  }
}

Future<T?> showPlaybackBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool fromRight = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  Clip? clipBehavior,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  AnimationStyle? sheetAnimationStyle,
  Widget Function(BuildContext, Widget)? surfaceBuilder,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final theme = Theme.of(context);
  final sheetTheme = theme.bottomSheetTheme;
  final fill =
      backgroundColor ??
      sheetTheme.modalBackgroundColor ??
      sheetTheme.backgroundColor ??
      (theme.useMaterial3
          ? theme.colorScheme.surfaceContainerLow
          : theme.canvasColor);
  final outline =
      shape ??
      sheetTheme.shape ??
      (theme.useMaterial3
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            )
          : const RoundedRectangleBorder());
  final handle =
      showDragHandle ?? (enableDrag && (sheetTheme.showDragHandle ?? false));
  Widget panelBuilder(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (handle)
          SizedBox(
            height: kMinInteractiveDimension,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color:
                      sheetTheme.dragHandleColor ??
                      theme.colorScheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: SizedBox(
                  width: sheetTheme.dragHandleSize?.width ?? 32,
                  height: sheetTheme.dragHandleSize?.height ?? 4,
                ),
              ),
            ),
          ),
        Flexible(fit: FlexFit.loose, child: builder(context)),
      ],
    );
    final animation = ModalRoute.of(context)!.animation!;
    final content = reduceMotion
        ? body
        : FadeTransition(
            key: const ValueKey('playback-sheet-foreground-fade'),
            opacity: animation.drive(
              CurveTween(curve: playbackSheetTextOpacityCurve),
            ),
            child: body,
          );
    final surface = surfaceBuilder != null
        ? surfaceBuilder(context, content)
        : Stack(
            children: [
              Positioned.fill(
                child: PlaybackSheetBackgroundFade(
                  child: Material(
                    color: fill,
                    shape: outline,
                    elevation:
                        sheetTheme.modalElevation ??
                        sheetTheme.elevation ??
                        (theme.useMaterial3 ? 1 : 0),
                    shadowColor:
                        sheetTheme.shadowColor ??
                        (theme.useMaterial3 ? Colors.transparent : null),
                    surfaceTintColor:
                        sheetTheme.surfaceTintColor ??
                        (theme.useMaterial3 ? Colors.transparent : null),
                  ),
                ),
              ),
              content,
            ],
          );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations:
            reduceMotion || MediaQuery.disableAnimationsOf(context),
      ),
      child: surface,
    );
  }

  if (fromRight) {
    return navigator.push<T>(
      RawDialogRoute<T>(
        barrierDismissible: isDismissible,
        barrierLabel: localizations.scrimLabel,
        barrierColor: sheetTheme.modalBarrierColor ?? Colors.black54,
        transitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 260),
        pageBuilder: (routeContext, _, _) => InheritedTheme.captureAll(
          context,
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              key: const ValueKey('playback-side-panel'),
              width: MediaQuery.sizeOf(routeContext).width * .88,
              height: MediaQuery.sizeOf(routeContext).height,
              child: panelBuilder(routeContext),
            ),
          ),
        ),
        transitionBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }
  return navigator.push<T>(
    _PlaybackBottomSheetRoute<T>(
      builder: panelBuilder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: sheetTheme.modalBarrierColor,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: outline,
      clipBehavior: clipBehavior ?? sheetTheme.clipBehavior ?? Clip.none,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: false,
      useSafeArea: useSafeArea,
      sheetAnimationStyle: reduceMotion
          ? AnimationStyle.noAnimation
          : sheetAnimationStyle,
    ),
  );
}

class _PlaybackBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _PlaybackBottomSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    super.useSafeArea,
    super.sheetAnimationStyle,
  });
  @override
  Curve get barrierCurve => playbackSheetOpacityCurve;
}
