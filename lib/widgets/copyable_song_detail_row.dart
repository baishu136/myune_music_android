import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';

class CopyableSongDetailRow extends StatelessWidget {
  const CopyableSongDetailRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } on PlatformException {
      if (context.mounted) {
        context.read<NotificationService>().error('无法复制$label，请重试');
      }
      return;
    }
    if (!context.mounted) return;
    HapticFeedback.lightImpact().ignore();
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已复制歌曲信息', textAlign: TextAlign.center),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: hasValue ? () => _copy(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 104,
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  decoration: hasValue ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SongDetailsFeedbackSurface extends StatelessWidget {
  const SongDetailsFeedbackSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    child: Scaffold(backgroundColor: Colors.transparent, body: child),
  );
}
