import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum AppNoticeKind { info, success, warning, error }

class AppNotice {
  const AppNotice(this.message, this.kind);
  final String message;
  final AppNoticeKind kind;
}

/// A small queue shared by every page, so messages remain visible across routes.
class NotificationService extends ChangeNotifier {
  final Queue<AppNotice> _queue = Queue<AppNotice>();
  AppNotice? _current;
  Timer? _timer;

  AppNotice? get current => _current;

  void info(String message) => show(message, AppNoticeKind.info);
  void success(String message) => show(message, AppNoticeKind.success);
  void warning(String message) => show(message, AppNoticeKind.warning);
  void error(String message) => show(message, AppNoticeKind.error);

  void show(String message, AppNoticeKind kind) {
    final value = message.trim();
    if (value.isEmpty) return;
    _queue.add(AppNotice(value, kind));
    _showNext();
  }

  void dismiss() {
    _timer?.cancel();
    _current = null;
    notifyListeners();
    _showNext();
  }

  void _showNext() {
    if (_current != null || _queue.isEmpty) return;
    _current = _queue.removeFirst();
    notifyListeners();
    _timer = Timer(
      _current!.kind == AppNoticeKind.error
          ? const Duration(seconds: 5)
          : const Duration(seconds: 3),
      dismiss,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class GlobalNoticeOverlay extends StatelessWidget {
  const GlobalNoticeOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService>();
    final notice = service.current;
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 12,
          right: 12,
          child: SafeArea(
            child: IgnorePointer(
              ignoring: notice == null,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                offset: notice == null ? const Offset(0, -1.4) : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: notice == null ? 0 : 1,
                  child: notice == null
                      ? const SizedBox.shrink()
                      : Dismissible(
                          key: ValueKey('${notice.kind}:${notice.message}'),
                          direction: DismissDirection.up,
                          onDismissed: (_) => service.dismiss(),
                          child: _NoticeCard(notice: notice),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});
  final AppNotice notice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (notice.kind) {
      AppNoticeKind.success => (Icons.check_circle_outline, Colors.green),
      AppNoticeKind.warning => (Icons.warning_amber_rounded, Colors.orange),
      AppNoticeKind.error => (Icons.error_outline, scheme.error),
      AppNoticeKind.info => (Icons.info_outline, scheme.primary),
    };
    return Card(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(notice.message)),
            Semantics(
              button: true,
              label: '关闭',
              child: InkResponse(
                radius: 24,
                onTap: context.read<NotificationService>().dismiss,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.close),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
