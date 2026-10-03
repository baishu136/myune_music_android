import 'dart:async';

import 'package:flutter/material.dart';

import '../services/interaction_performance_controller.dart';

/// Layout the adjacent tab before it slides into view. Retain each bounded
/// home page and its raster boundary rather than rebuilding it on selection.
class HomeTabViewport extends StatefulWidget {
  const HomeTabViewport({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.onPageChanged,
    this.scrollEnabled = true,
  });
  final PageController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;
  final bool scrollEnabled;

  @override
  State<HomeTabViewport> createState() => _HomeTabViewportState();
}

class _HomeTabViewportState extends State<HomeTabViewport> {
  bool _prepareNeighbors = true;
  bool _scrolling = false;
  bool _waitingForIdle = false;
  int _preparationRevision = 0;
  Timer? _preparationTimer;
  final Set<int> _preparedPages = <int>{};

  @override
  void didUpdateWidget(covariant HomeTabViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.itemCount != widget.itemCount) {
      _preparationRevision++;
      _preparationTimer?.cancel();
      _preparationTimer = null;
      _preparedPages.clear();
      _scrolling = false;
      _prepareNeighbors = true;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
      _preparationRevision++;
      _preparationTimer?.cancel();
      _preparationTimer = null;
      // Once every bounded page has mounted, keep the existing cache policy:
      // toggling it on warm slides adds two unnecessary viewport layouts.
      if (_prepareNeighbors && _preparedPages.length < widget.itemCount) {
        setState(() => _prepareNeighbors = false);
      }
    } else if (notification is ScrollEndNotification) {
      _scrolling = false;
      _preparationRevision++;
      if (!_prepareNeighbors) _schedulePreparation();
    }
    return false;
  }

  void _schedulePreparation() {
    _preparationTimer?.cancel();
    // Also let the 380 ms header animation finish after the 320 ms page slide.
    _preparationTimer = Timer(const Duration(milliseconds: 180), () {
      _preparationTimer = null;
      unawaited(_prepareWhenIdle());
    });
  }

  Future<void> _prepareWhenIdle() async {
    if (_waitingForIdle || !mounted || _scrolling || _prepareNeighbors) return;
    _waitingForIdle = true;
    final revision = _preparationRevision;
    final lease = await InteractionPerformanceController.instance
        .acquireIdleWork(
          priority: InteractionWorkPriority.userVisible,
          isStillNeeded: () => mounted && !_scrolling && !_prepareNeighbors,
        );
    try {
      if (!lease.isGranted ||
          !mounted ||
          _scrolling ||
          revision != _preparationRevision) {
        return;
      }
      setState(() => _prepareNeighbors = true);
      // Keep the lease until the actual layout finishes; releasing before the
      // next frame would start multiple kinds of cold work together again.
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      lease.release();
      _waitingForIdle = false;
      if (mounted && !_scrolling && !_prepareNeighbors) _schedulePreparation();
    }
  }

  @override
  void dispose() {
    _preparationRevision++;
    _preparationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: PageView.builder(
          controller: widget.controller,
          // A whole-viewport cache while moving builds the invisible third page
          // during a 0 -> 1 slide. The retained visible endpoints still paint.
          allowImplicitScrolling: _prepareNeighbors,
          physics: widget.scrollEnabled
              ? const PageScrollPhysics(parent: BouncingScrollPhysics())
              : const NeverScrollableScrollPhysics(),
          onPageChanged: widget.onPageChanged,
          itemCount: widget.itemCount,
          itemBuilder: (context, index) {
            _preparedPages.add(index);
            return _RetainedHomePage(
              key: ValueKey('home-page-$index'),
              child: widget.itemBuilder(context, index),
            );
          },
        ),
      );
}

class _RetainedHomePage extends StatefulWidget {
  const _RetainedHomePage({super.key, required this.child});
  final Widget child;
  @override
  State<_RetainedHomePage> createState() => _RetainedHomePageState();
}

class _RetainedHomePageState extends State<_RetainedHomePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}
