part of 'mobile_lyrics_list.dart';

int _normalGlowRasterPixels = 0;
int get debugMobileLyricGlowRasterPixels => _normalGlowRasterPixels;

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
  _NormalGlowReservation(this.owner, this.pixels)
    : shared = LyricRasterReservation(pixels) {
    _normalGlowRasterPixels += pixels;
  }
  final _CachedMobileLyricGlowState owner;
  final int pixels;
  final LyricRasterReservation shared;
  bool released = false;
  void release() {
    if (released) return;
    released = true;
    _normalGlowRasterPixels -= pixels;
    shared.release();
    if (owner._reservation == this) {
      owner._normalFailed = true;
    }
    _scheduleNormalGlowPool();
  }
}

void _scheduleNormalGlowPool() => LyricRasterPool.schedule();
