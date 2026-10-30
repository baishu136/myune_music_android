import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'playback_control_sheet_surface.dart';

/// Compact setting with a downward-revealing menu on the root overlay.
class SideSelectionMenu<T> extends StatefulWidget {
  const SideSelectionMenu({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.title,
    this.style,
    this.inlineLabel = true,
    this.showSelectedIcon = true,
    this.expandedInsets,
    this.minimumSize = const Size(0, 36),
  });
  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final String? title;
  final ButtonStyle? style;
  final bool inlineLabel;
  final bool showSelectedIcon;
  final EdgeInsets? expandedInsets;
  final Size minimumSize;
  @override
  State<SideSelectionMenu<T>> createState() => _SideSelectionMenuState<T>();
}

class _SideSelectionMenuState<T> extends State<SideSelectionMenu<T>> {
  final _anchor = GlobalKey();
  bool _opening = false;
  static const _radius = BorderRadius.all(Radius.circular(8));
  BorderSide _border(ThemeData theme) =>
      widget.style?.side?.resolve({}) ??
      theme.outlinedButtonTheme.style?.side?.resolve({}) ??
      BorderSide(color: theme.colorScheme.outline);
  String _text(ButtonSegment<T> option) => option.label is Text
      ? ((option.label as Text).data ??
            (option.label as Text).textSpan?.toPlainText() ??
            option.tooltip ??
            option.value.toString())
      : option.tooltip ?? option.value.toString();
  Color _foreground(ThemeData theme, bool translucent) => translucent
      ? (ThemeData.estimateBrightnessForColor(theme.colorScheme.onSurface) ==
                Brightness.light
            ? Colors.white
            : Colors.black)
      : (theme.brightness == Brightness.dark ? Colors.white : Colors.black);
  Rect? _anchorRect(RenderBox overlay) {
    final box = _anchor.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }

  Future<void> _open() async {
    if (_opening ||
        widget.onSelectionChanged == null ||
        widget.segments.isEmpty) {
      return;
    }
    _opening = true;
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      final overlay = navigator.overlay?.context.findRenderObject();
      if (overlay is! RenderBox) return;
      var anchor = _anchorRect(overlay);
      if (anchor == null) return;
      final reduced = MediaQuery.disableAnimationsOf(context);
      final media = MediaQuery.of(context);
      final below =
          media.size.height -
          math.max(media.viewInsets.bottom, media.viewPadding.bottom) -
          anchor.bottom;
      if (below < math.min(180, widget.segments.length * 44 + 16) &&
          Scrollable.maybeOf(context) != null) {
        await Scrollable.ensureVisible(
          _anchor.currentContext!,
          alignment: .12,
          duration: reduced ? Duration.zero : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
        anchor = _anchorRect(overlay);
        if (anchor == null) return;
      }
      if (!mounted) return;
      final themes = InheritedTheme.capture(
        from: context,
        to: navigator.context,
      );
      final surface = context
          .findAncestorWidgetOfExactType<PlaybackControlSheetSurface>();
      final theme = Theme.of(context);
      final border = _border(theme);
      final foreground = _foreground(theme, surface != null);
      final textStyle = theme.textTheme.labelLarge!.copyWith(color: foreground);
      var longest = 0.0;
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      );
      for (final option in widget.segments) {
        painter.text = TextSpan(text: _text(option), style: textStyle);
        painter.layout();
        longest = math.max(longest, painter.width);
      }
      painter.dispose();
      final width = math.max(
        anchor.width,
        longest + 40 + (widget.showSelectedIcon ? 26 : 0),
      );
      final lastAnchor = anchor;
      var closing = false;
      final route = RawDialogRoute<T>(
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        transitionDuration: reduced
            ? Duration.zero
            : const Duration(milliseconds: 180),
        pageBuilder: (rootContext, animation, secondary) => themes.wrap(
          LayoutBuilder(
            builder: (context, constraints) {
              final media = MediaQuery.of(context);
              final safe = EdgeInsets.fromLTRB(
                math.max(media.viewPadding.left, media.viewInsets.left) + 8,
                math.max(media.viewPadding.top, media.viewInsets.top) + 8,
                math.max(media.viewPadding.right, media.viewInsets.right) + 8,
                math.max(media.viewPadding.bottom, media.viewInsets.bottom) + 8,
              );
              final progress = animation.drive(
                CurveTween(curve: Curves.easeOutCubic),
              );
              final content = Padding(
                padding: const EdgeInsets.all(6),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final option in widget.segments)
                        OutlinedButton(
                          key: ValueKey('side-selection-${option.value}'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: foreground,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: !option.enabled
                              ? null
                              : () {
                                  if (closing) return;
                                  closing = true;
                                  navigator.pop(option.value);
                                },
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _text(option),
                                  style: textStyle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.showSelectedIcon) ...[
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 18,
                                  child: widget.selected.contains(option.value)
                                      ? const Icon(Icons.check, size: 18)
                                      : null,
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
              final panel = surface == null
                  ? Material(
                      key: const ValueKey('selection-menu-panel'),
                      color: theme.colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: _radius,
                        side: border,
                      ),
                      clipBehavior: Clip.antiAlias,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      child: content,
                    )
                  : PlaybackControlSheetSurface(
                      key: const ValueKey('selection-menu-panel'),
                      fluid: surface.fluid,
                      borderRadius: _radius,
                      borderSide: border,
                      child: content,
                    );
              return CustomSingleChildLayout(
                delegate: SelectionMenuLayout(
                  anchor: _anchorRect(overlay) ?? lastAnchor,
                  safe: safe,
                  width: width,
                ),
                child: AnimatedBuilder(
                  animation: progress,
                  child: panel,
                  builder: (_, child) => FadeTransition(
                    opacity: progress,
                    child: ClipRect(
                      clipper: _DownReveal(progress.value),
                      child: child,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      final result = await navigator.push<T>(route);
      await route.completed;
      if (mounted &&
          result != null &&
          widget.segments.any((s) => s.value == result)) {
        widget.onSelectionChanged?.call({result});
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = _foreground(theme, true);
    final option = widget.segments
        .where((s) => widget.selected.contains(s.value))
        .firstOrNull;
    final entry = OutlinedButton(
      key: _anchor,
      onPressed: widget.onSelectionChanged == null ? null : _open,
      style: (widget.style ?? const ButtonStyle()).copyWith(
        foregroundColor: WidgetStatePropertyAll(foreground),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
        minimumSize: WidgetStatePropertyAll(widget.minimumSize),
        side: WidgetStatePropertyAll(_border(theme)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: _radius),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              option == null ? widget.selected.first.toString() : _text(option),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
    if (!widget.inlineLabel || widget.title == null) return entry;
    return LayoutBuilder(
      builder: (context, constraints) => InkWell(
        onTap: widget.onSelectionChanged == null ? null : _open,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Expanded(
              child: Text(widget.title!, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * .5),
              child: entry,
            ),
          ],
        ),
      ),
    );
  }
}

class SelectionMenuLayout extends SingleChildLayoutDelegate {
  const SelectionMenuLayout({
    required this.anchor,
    required this.safe,
    required this.width,
  });
  final Rect anchor;
  final EdgeInsets safe;
  final double width;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final availableWidth = math.max(
      1.0,
      constraints.maxWidth - safe.horizontal,
    );
    final below = constraints.maxHeight - safe.bottom - anchor.bottom - 4;
    final availableHeight = math.max(
      1.0,
      constraints.maxHeight - safe.vertical,
    );
    return BoxConstraints.tightFor(
      width: width.clamp(1.0, availableWidth),
    ).copyWith(
      minHeight: 0,
      maxHeight: below >= 72
          ? math.min(below, availableHeight)
          : availableHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (anchor.right - childSize.width).clamp(
      safe.left,
      math.max(safe.left, size.width - safe.right - childSize.width),
    ),
    (anchor.bottom + 4).clamp(
      safe.top,
      math.max(safe.top, size.height - safe.bottom - childSize.height),
    ),
  );
  @override
  bool shouldRelayout(SelectionMenuLayout old) =>
      old.anchor != anchor || old.safe != safe || old.width != width;
}

class _DownReveal extends CustomClipper<Rect> {
  const _DownReveal(this.progress);
  final double progress;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width, size.height * progress);
  @override
  bool shouldReclip(_DownReveal old) => old.progress != progress;
}
