import 'package:flutter/material.dart';

class InfoIcon extends StatelessWidget {
  const InfoIcon(
    this.message, {
    super.key,
    this.size = 20,
    this.icon = Icons.info_outline,
  });

  final String message;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final disabledColor = Theme.of(context).disabledColor;
    return Tooltip(
      message: message,
      child: IconButton(
        tooltip: message,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: const EdgeInsets.all(4),
        icon: Icon(icon, size: size, color: disabledColor),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('功能说明'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
