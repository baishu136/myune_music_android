import 'package:flutter/widgets.dart';

/// One budget includes queued, in-flight and ready ordinary ink/glow images.
abstract interface class LyricRasterClient {
  int get rasterDemand;
  int get rasterRank;
  int get rasterSequence;
  bool get rasterReserved;
  void reserveRaster();
  void evictRaster();
}

class LyricRasterReservation {
  LyricRasterReservation(this.pixels) {
    assert(LyricRasterPool.pixels + pixels <= LyricRasterPool.limit);
    LyricRasterPool.pixels += pixels;
  }
  final int pixels;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    LyricRasterPool.pixels -= pixels;
    LyricRasterPool.schedule();
  }
}

class LyricRasterPool {
  static const limit = 8 * 1024 * 1024;
  static int pixels = 0;
  static int _sequence = 0;
  static bool _scheduled = false;
  static final _clients = <LyricRasterClient>{};

  static int register(LyricRasterClient client) {
    _clients.add(client);
    return _sequence++;
  }

  static void unregister(LyricRasterClient client) {
    _clients.remove(client);
    schedule();
  }

  static void schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final clients = _clients.where((c) => c.rasterDemand > 0).toList()
        ..sort((a, b) {
          final rank = a.rasterRank.compareTo(b.rasterRank);
          return rank != 0
              ? rank
              : a.rasterSequence.compareTo(b.rasterSequence);
        });
      var planned = 0;
      final wanted = <LyricRasterClient>{};
      for (final client in clients) {
        if (planned + client.rasterDemand > limit) continue;
        planned += client.rasterDemand;
        wanted.add(client);
      }
      for (final client in _clients.toList()) {
        if (client.rasterReserved && !wanted.contains(client)) {
          client.evictRaster();
        }
      }
      for (final client in clients) {
        if (wanted.contains(client) &&
            !client.rasterReserved &&
            pixels + client.rasterDemand <= limit) {
          client.reserveRaster();
        }
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}

class LyricRasterScope extends InheritedWidget {
  const LyricRasterScope({super.key, required this.rank, required super.child});
  final int rank;
  static int? rankOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LyricRasterScope>()?.rank;
  @override
  bool updateShouldNotify(LyricRasterScope oldWidget) => oldWidget.rank != rank;
}
