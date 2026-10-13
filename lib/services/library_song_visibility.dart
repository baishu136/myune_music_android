import 'package:path/path.dart' as p;

/// Shared by normal publication and saved-order recovery: hidden paths must
/// remain filtered even if metadata is unresolved or every row is hidden.
class LibrarySongVisibility {
  final paths = <String>{};
  final identities = <String>{};
  bool showHidden = false;

  bool get hasHidden => paths.isNotEmpty || identities.isNotEmpty;

  bool hide(Iterable<String> newPaths, Iterable<String> newIdentities) {
    var changed = false;
    for (final path in newPaths) {
      changed = paths.add(p.normalize(path).toLowerCase()) || changed;
    }
    for (final identity in newIdentities) {
      changed = identities.add(identity) || changed;
    }
    return changed;
  }

  bool isHidden(String path, [String? identity]) =>
      paths.contains(p.normalize(path).toLowerCase()) ||
      (identity != null && identities.contains(identity));

  bool restore(
    Iterable<String> restoredPaths,
    Iterable<String> restoredIdentities,
  ) {
    var changed = false;
    for (final path in restoredPaths) {
      changed = paths.remove(p.normalize(path).toLowerCase()) || changed;
    }
    for (final identity in restoredIdentities) {
      changed = identities.remove(identity) || changed;
    }
    return changed;
  }

  bool includes(String path, [String? identity]) =>
      showHidden || !isHidden(path, identity);
}

bool shouldRecoverSavedLibraryOrder({
  required bool hasSourcePaths,
  required bool sourceWasSeen,
}) => !hasSourcePaths && !sourceWasSeen;
