import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The bottom annotation wins independently of each route's status bar style.
/// Keep layout insets: only the OS contrast scrim/divider becomes transparent.
class AndroidSystemBars extends StatelessWidget {
  const AndroidSystemBars({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness:
          Theme.of(context).brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    ),
    child: child,
  );
}
