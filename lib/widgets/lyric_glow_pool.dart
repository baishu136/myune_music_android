part of 'mobile_lyrics_list.dart';

const _normalGlowRasterPixelLimit = 8 * 1024 * 1024;
int _normalGlowRasterPixels = 0;
int get debugMobileLyricGlowRasterPixels => _normalGlowRasterPixels;
final _normalGlowClients = <_CachedMobileLyricGlowState>{};
bool _normalGlowPoolScheduled = false;
int _nextNormalGlowClient = 0;

int _normalGlowRank(int distance, bool visible) =>
    (visible ? 0 : 10000) +
    switch (distance) {
      0 => 0,
      1 => 1,
      -1 => 2,
      2 => 3,
      _ => 4 + distance.abs(),
    };

class _NormalGlowReservation {
  _NormalGlowReservation(this.owner, this.pixels) {
    _normalGlowRasterPixels += pixels;
  }
  final _CachedMobileLyricGlowState owner;
  final int pixels;
  bool released = false;
  void release() {
    if (released) return;
    released = true;
    _normalGlowRasterPixels -= pixels;
    if (owner._reservation == this) {
      owner._normalFailed = true;
    }
    _scheduleNormalGlowPool();
  }
}

void _scheduleNormalGlowPool() {
  if (_normalGlowPoolScheduled) return;
  _normalGlowPoolScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _normalGlowPoolScheduled = false;
    final clients =
        _normalGlowClients
            .where((client) => client.mounted && client._normalDemand > 0)
            .toList()
          ..sort((a, b) {
            final rank = a._normalRank.compareTo(b._normalRank);
            return rank != 0
                ? rank
                : a._normalSequence.compareTo(b._normalSequence);
          });
    var planned = 0;
    final wanted = <_CachedMobileLyricGlowState>{};
    for (final client in clients) {
      if (planned + client._normalDemand > _normalGlowRasterPixelLimit) {
        continue;
      }
      planned += client._normalDemand;
      wanted.add(client);
    }
    for (final client in _normalGlowClients.toList()) {
      if (client._reservation == null || wanted.contains(client)) continue;
      client._evictNormalRaster();
    }
    for (final client in clients) {
      if (!wanted.contains(client) || client._reservation != null) continue;
      if (_normalGlowRasterPixels + client._normalDemand <=
          _normalGlowRasterPixelLimit) {
        client._reserveNormalRaster();
      }
    }
  });
  WidgetsBinding.instance.scheduleFrame();
}
