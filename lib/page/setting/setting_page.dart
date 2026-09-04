import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/interaction_performance_controller.dart';
import 'tabs/general_tab.dart';
import 'tabs/personalization_tab.dart';
import 'tabs/playback_page_tab.dart';
import 'tabs/playback_settings_tab.dart';
import 'tabs/hotkeys_tab.dart';
import 'tabs/advanced_tab.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({
    super.key,
    this.onSectionChanged,
    this.onSwipeBackFromFirstSection,
  });

  final ValueChanged<String>? onSectionChanged;
  final VoidCallback? onSwipeBackFromFirstSection;

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  int _selectedIndex = 1;
  late final PageController _androidPageController;
  int? _programmaticSectionTarget;
  double _leadingEdgeDragDistance = 0;
  bool _leadingEdgeSwipeHandled = false;
  static const double _leadingEdgeSwipeTriggerDistance = 24;

  static const _androidDestinations = <(int, String, IconData)>[
    (1, '个性化', Icons.palette_outlined),
    (3, '播放', Icons.volume_up_outlined),
    (5, '高级', Icons.construction_outlined),
    (0, '常规', Icons.settings_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _androidPageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSectionChanged?.call(_androidDestinations.first.$2);
    });
  }

  @override
  void dispose() {
    _androidPageController.dispose();
    super.dispose();
  }

  void _selectAndroidSection((int, String, IconData) section) {
    if (_selectedIndex != section.$1) {
      setState(() => _selectedIndex = section.$1);
    }
    widget.onSectionChanged?.call(section.$2);
  }

  void _animateToAndroidSection(int pageIndex) {
    final section = _androidDestinations[pageIndex];
    _selectAndroidSection(section);
    if (!_androidPageController.hasClients) {
      _programmaticSectionTarget = null;
      return;
    }
    final currentPage = (_androidPageController.page ?? 0).round();
    if (currentPage == pageIndex) {
      _programmaticSectionTarget = null;
      return;
    }
    _programmaticSectionTarget = pageIndex;
    unawaited(_completeAndroidSectionAnimation(pageIndex));
  }

  Future<void> _completeAndroidSectionAnimation(int target) async {
    await _androidPageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    if (!mounted || _programmaticSectionTarget != target) return;
    _programmaticSectionTarget = null;
    final settledPage = (_androidPageController.page ?? target.toDouble())
        .round()
        .clamp(0, _androidDestinations.length - 1);
    _selectAndroidSection(_androidDestinations[settledPage]);
  }

  void _handleAndroidPageChanged(int index) {
    final target = _programmaticSectionTarget;
    if (target != null) {
      if (index != target) return;
      _programmaticSectionTarget = null;
    }
    _selectAndroidSection(_androidDestinations[index]);
  }

  Widget _androidPager() => NotificationListener<ScrollNotification>(
    onNotification: _handleAndroidPagerScroll,
    child: PageView.builder(
      controller: _androidPageController,
      physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
      onPageChanged: _handleAndroidPageChanged,
      itemCount: _androidDestinations.length,
      itemBuilder: (context, index) => _SettingsKeepAlivePage(
        key: ValueKey('android-setting-page-$index'),
        child: _contentFor(_androidDestinations[index].$1),
      ),
    ),
  );

  bool _handleAndroidPagerScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.horizontal) {
      InteractionPerformanceController.instance.pulse(
        InteractionPhase.transition,
        settleAfter: const Duration(milliseconds: 140),
      );
    }
    if (notification.metrics.axis != Axis.horizontal ||
        widget.onSwipeBackFromFirstSection == null) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _leadingEdgeDragDistance = 0;
      _leadingEdgeSwipeHandled = false;
      return false;
    }
    if (_selectedIndex != _androidDestinations.first.$1 ||
        _leadingEdgeSwipeHandled) {
      return false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      final atLeadingEdge =
          notification.metrics.pixels <=
          notification.metrics.minScrollExtent + 1;
      if (atLeadingEdge && delta < 0) {
        _leadingEdgeDragDistance += -delta;
      }
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0) {
      _leadingEdgeDragDistance += -notification.overscroll;
    }
    if (_leadingEdgeDragDistance >= _leadingEdgeSwipeTriggerDistance) {
      _leadingEdgeSwipeHandled = true;
      widget.onSwipeBackFromFirstSection?.call();
    }
    return false;
  }

  Widget _contentFor(int index) {
    switch (index) {
      case 0:
        return const GeneralTab(key: ValueKey('general'));
      case 1:
        return const PersonalizationTab(key: ValueKey('personalization'));
      case 2:
        return const PlaybackPageTab(key: ValueKey('playback'));
      case 3:
        return const PlaybackSettingsTab(key: ValueKey('playback_settings'));
      case 4:
        return const HotkeysTab(key: ValueKey('hotkeys'));
      case 5:
        return const AdvancedTab(key: ValueKey('advanced'));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _content() => AnimatedSwitcher(
    duration: const Duration(milliseconds: 120),
    child: _contentFor(_selectedIndex),
  );

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      final isTablet = MediaQuery.sizeOf(context).shortestSide >= 600;
      if (isTablet) {
        final wideTablet = MediaQuery.sizeOf(context).width >= 1180;
        final destinationIndex = _androidDestinations.indexWhere(
          (section) => section.$1 == _selectedIndex,
        );
        return Row(
          children: [
            ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: NavigationRail(
                extended: wideTablet,
                minExtendedWidth: 180,
                selectedIndex: destinationIndex < 0 ? 0 : destinationIndex,
                labelType: wideTablet
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.selected,
                groupAlignment: -0.75,
                onDestinationSelected: (index) {
                  _animateToAndroidSection(index);
                },
                destinations: _androidDestinations
                    .map(
                      (section) => NavigationRailDestination(
                        icon: Icon(section.$3),
                        selectedIcon: Icon(section.$3, size: 28),
                        label: Text(section.$2),
                      ),
                    )
                    .toList(),
              ),
            ),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: _androidPager(),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return Column(
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: _androidDestinations.map((section) {
                  final selected = _selectedIndex == section.$1;
                  final colors = Theme.of(context).colorScheme;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Tooltip(
                        message: section.$2,
                        child: Material(
                          color: selected
                              ? colors.secondaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _animateToAndroidSection(
                              _androidDestinations.indexOf(section),
                            ),
                            child: Center(
                              child: Icon(
                                section.$3,
                                size: 26,
                                color: selected
                                    ? colors.onSecondaryContainer
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _androidPager()),
        ],
      );
    }

    return Row(
      children: [
        // 左侧导航栏
        Container(
          width: 150,
          color: Colors.transparent,
          child: Column(
            children: [
              _SettingNavItem(
                index: 0,
                title: '常规',
                icon: Icons.settings_outlined,
                isSelected: _selectedIndex == 0,
                onTap: () => setState(() => _selectedIndex = 0),
              ),
              _SettingNavItem(
                index: 1,
                title: '个性化',
                icon: Icons.palette_outlined,
                isSelected: _selectedIndex == 1,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _SettingNavItem(
                index: 2,
                title: '播放页',
                icon: Icons.play_circle_outline,
                isSelected: _selectedIndex == 2,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
              _SettingNavItem(
                index: 3,
                title: '播放设置',
                icon: Icons.volume_up_outlined,
                isSelected: _selectedIndex == 3,
                onTap: () => setState(() => _selectedIndex = 3),
              ),
              _SettingNavItem(
                index: 4,
                title: '快捷键',
                icon: Icons.keyboard_outlined,
                isSelected: _selectedIndex == 4,
                onTap: () => setState(() => _selectedIndex = 4),
              ),
              _SettingNavItem(
                index: 5,
                title: '高级',
                icon: Icons.construction_outlined,
                isSelected: _selectedIndex == 5,
                onTap: () => setState(() => _selectedIndex = 5),
              ),
            ],
          ),
        ),
        // 垂直分割线
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        // 右侧实际设置项
        Expanded(child: _content()),
      ],
    );
  }
}

class _SettingsKeepAlivePage extends StatefulWidget {
  const _SettingsKeepAlivePage({super.key, required this.child});

  final Widget child;

  @override
  State<_SettingsKeepAlivePage> createState() => _SettingsKeepAlivePageState();
}

class _SettingsKeepAlivePageState extends State<_SettingsKeepAlivePage>
    with AutomaticKeepAliveClientMixin<_SettingsKeepAlivePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _SettingNavItem extends StatefulWidget {
  final int index;
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SettingNavItem({
    required this.index,
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SettingNavItem> createState() => _SettingNavItemState();
}

class _SettingNavItemState extends State<_SettingNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: widget.isSelected
            ? colorScheme.primary.withValues(alpha: 0.1)
            : _isHovered
            ? Colors.grey.withValues(alpha: 0.1)
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: ListTile(
            horizontalTitleGap: 8,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Icon(
              widget.icon,
              size: 20,
              color: widget.isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            title: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: widget.isSelected ? 1.05 : 1.0,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.isSelected ? colorScheme.primary : null,
                ),
              ),
            ),
            selected: widget.isSelected,
          ),
        ),
      ),
    );
  }
}
