import 'dart:io';
import 'package:path/path.dart' as p;
import '../page/playlist/playlist_models.dart';

bool songPathInFolder(String file, String root) {
  final path = p.normalize(file).toLowerCase();
  final folder = p.normalize(root).toLowerCase();
  return path == folder || p.isWithin(folder, path);
}

bool detachPlaylistFolder(Playlist playlist, String root) {
  final key = p.normalize(root).toLowerCase();
  if (!playlist.folderPaths.any(
    (folder) => p.normalize(folder).toLowerCase() == key,
  )) {
    return false;
  }
  playlist.folderPaths.removeWhere(
    (folder) => p.normalize(folder).toLowerCase() == key,
  );
  bool detached(String path) =>
      songPathInFolder(path, root) &&
      !playlist.folderPaths.any((folder) => songPathInFolder(path, folder));
  playlist.songFilePaths.removeWhere(detached);
  playlist.songs?.removeWhere((song) => detached(song.filePath));
  if (playlist.folderPaths.isEmpty) playlist.isFolderBased = false;
  return true;
}

/// A failed scan throws before the caller changes any playlist membership.
Future<Set<String>> scanPlaylistFolder(
  String root,
  Iterable<String> extensions,
) async {
  final directory = Directory(root);
  if (!await directory.exists()) throw FileSystemException('文件夹不可访问', root);
  final supported = extensions.toSet();
  final discovered = <String>{};
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File &&
        supported.contains(p.extension(entity.path).toLowerCase())) {
      discovered.add(p.normalize(entity.path));
    }
  }
  return discovered;
}
