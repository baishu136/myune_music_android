const legacyArtistSeparators = [';', '、', '；', '，', ','];
const defaultArtistSeparators = [...legacyArtistSeparators, '/', '／'];

final _artistWhitespace = RegExp(r'\s+');

String artistMatchKey(String name) =>
    name.trim().replaceAll(_artistWhitespace, ' ').toLowerCase();

class ArtistNameParser {
  ArtistNameParser(Iterable<String> separators) {
    final valid =
        separators
            .where((separator) => separator.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    _pattern = valid.isEmpty
        ? null
        : RegExp(valid.map(RegExp.escape).join('|'));
  }

  late final RegExp? _pattern;

  List<String> split(String value) {
    final seen = <String>{};
    final names = <String>[];
    for (final part in _pattern == null ? [value] : value.split(_pattern)) {
      final name = part.trim().replaceAll(_artistWhitespace, ' ');
      if (name.isNotEmpty && seen.add(artistMatchKey(name))) names.add(name);
    }
    return names.isEmpty ? ['未知歌手'] : names;
  }
}

Map<String, List<T>> groupByArtist<T>(
  Iterable<T> items,
  String Function(T item) artistOf,
  ArtistNameParser parser,
) {
  final displayNames = <String, String>{};
  final groups = <String, List<T>>{};
  for (final item in items) {
    for (final name in parser.split(artistOf(item))) {
      final display = displayNames.putIfAbsent(
        artistMatchKey(name),
        () => name,
      );
      groups.putIfAbsent(display, () => []).add(item);
    }
  }
  return groups;
}
