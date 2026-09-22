import 'package:flutter/widgets.dart';

/// Focus loss (notification shade, permission UI) is not backgrounding.
/// When returning via inactive, wait for resumed before restarting UI work.
bool foregroundAfterLifecycle(AppLifecycleState state, bool wasForeground) =>
    switch (state) {
      AppLifecycleState.resumed => true,
      AppLifecycleState.inactive => wasForeground,
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => false,
    };
