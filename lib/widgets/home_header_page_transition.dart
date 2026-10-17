import 'package:flutter/material.dart';

class HomeHeaderPageTransition extends StatelessWidget {
  const HomeHeaderPageTransition({
    super.key,
    required this.animation,
    required this.incoming,
    required this.child,
  });
  final Animation<double> animation;
  final bool incoming;
  final Widget child;
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation.drive(
      CurveTween(curve: Interval(incoming ? .12 : .35, 1)),
    ),
    child: SlideTransition(
      position: Tween<Offset>(
        begin: Offset(incoming ? 1.1 : -1.1, 0),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  );
}
