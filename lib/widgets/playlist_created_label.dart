import 'package:flutter/material.dart';

String? playlistCreatedDate(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}.${two(local.month)}.${two(local.day)}';
}

class PlaylistCreatedLabel extends StatelessWidget {
  const PlaylistCreatedLabel({super.key, required this.date});
  final DateTime? date;
  @override
  Widget build(BuildContext context) {
    final text = playlistCreatedDate(date);
    return text == null
        ? const SizedBox.shrink()
        : Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          );
  }
}
