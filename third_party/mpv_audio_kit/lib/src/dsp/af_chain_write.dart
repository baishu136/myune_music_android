/// A reply only confirms its captured string. Later runtime changes can have
/// committed while that write was awaiting the native response.
Future<void> synchronizeAfChain({
  required String chain,
  required Future<int> Function(String) write,
  required String Function() currentChain,
  required void Function(bool) markStale,
  required Object Function(int) rejection,
}) async {
  markStale(true);
  try {
    final rc = await write(chain);
    if (rc < 0) throw rejection(rc);
    markStale(chain != currentChain());
  } catch (_) {
    markStale(true);
    rethrow;
  }
}
