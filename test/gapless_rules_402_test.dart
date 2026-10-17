import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:myune_music/services/audio/audio_service.dart';

class _Events extends Fake implements PlayerStream {
  @override
  Stream<AudioParams> get audioParams => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
}

class _Player extends Fake implements PlayerApi {
  var current = const PlayerState(
    playlist: Playlist([Media('current'), Media('old-next')]),
  );
  final events = _Events();
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  PlayerState get state => current;
  @override
  PlayerStream get stream => events;
  @override
  Future<void> remove(int index) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final items = List<Media>.of(current.playlist.items)..removeAt(index);
    current = current.copyWith(playlist: Playlist(items));
  }

  @override
  Future<void> add(Media media) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    current = current.copyWith(
      playlist: Playlist([...current.playlist.items, media]),
    );
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  for (final latest in <String?>['latest', null]) {
    test(
      'rapid rule changes retain only the latest preloaded path: $latest',
      () async {
        final p = _Player();
        final audio = AudioService(player: p);
        await audio.init();
        final first = audio.replaceNext('outdated');
        await p.entered.future;
        final second = audio.replaceNext(latest);
        p.release.complete();
        await Future.wait([first, second]);
        expect(p.state.playlist.items.map((m) => m.uri), [
          'current',
          if (latest != null) latest,
        ]);
        await audio.dispose();
      },
    );
  }
}
