import 'package:flutter/material.dart';

class HomeExpandableActions extends StatefulWidget {
  const HomeExpandableActions({
    super.key,
    required this.children,
    this.searchAction,
  });

  final List<Widget> children;
  final Widget? searchAction;

  @override
  State<HomeExpandableActions> createState() => _HomeExpandableActionsState();
}

class _HomeExpandableActionsState extends State<HomeExpandableActions>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  bool _expanded = false;

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sizing = IconButton.styleFrom(
      minimumSize: const Size(40, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final inherited = IconButtonTheme.of(context).style;
    return IconButtonTheme(
      data: IconButtonThemeData(style: inherited?.merge(sizing) ?? sizing),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.children.isNotEmpty) ...[
            IconButton(
              tooltip: _expanded ? '收起功能' : '展开功能',
              isSelected: _expanded,
              icon: RotationTransition(
                turns: Tween<double>(begin: 0, end: .5).animate(_animation),
                child: const Icon(Icons.chevron_left),
              ),
              onPressed: () => setState(() {
                _expanded = !_expanded;
                _expanded ? _controller.forward() : _controller.reverse();
              }),
            ),
            SizeTransition(
              axis: Axis.horizontal,
              alignment: Alignment.centerRight,
              sizeFactor: _animation,
              child: FadeTransition(
                opacity: _animation,
                child: IgnorePointer(
                  ignoring: !_expanded,
                  child: ExcludeFocus(
                    excluding: !_expanded,
                    child: ExcludeSemantics(
                      excluding: !_expanded,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.children,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (widget.searchAction != null) widget.searchAction!,
        ],
      ),
    );
  }
}
