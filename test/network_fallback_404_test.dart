import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/services/network_lyric_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'ordinary match is presented before slow timed lookup finishes and only final timing resolves',
    () async {
      final entered = Completer<void>(), pending = Completer<List<LyricLine>>();
      final ordinary = [
        LyricLine(timestamp: Duration.zero, texts: ['ordinary']),
      ];
      final timed = [
        LyricLine(
          timestamp: Duration.zero,
          texts: ['timed'],
          tokens: [
            [
              LyricToken(
                text: 'timed',
                start: Duration.zero,
                end: const Duration(seconds: 1),
              ),
            ],
          ],
        ),
      ];
      final shown = <List<LyricLine>>[];
      var resolved = false;
      final result =
          resolveNetworkLyrics(
            selectedSource: 'netease',
            enableFallback: false,
            enableTimedFallback: true,
            onFallback: shown.add,
            fetch: (source) async {
              if (source == 'netease') return ordinary;
              entered.complete();
              return pending.future;
            },
          ).then((lyrics) {
            resolved = true;
            return lyrics;
          });
      await entered.future;
      expect(shown, [ordinary]);
      expect(resolved, false);
      pending.complete(timed);
      expect(await result, same(timed));
      expect(shown, hasLength(1));
    },
  );
  test(
    'canceled timed search starts no further platforms and returns no partial cache candidate',
    () async {
      var needed = true;
      final calls = <String>[];
      final result = await resolveNetworkLyrics(
        selectedSource: 'netease',
        enableFallback: true,
        enableTimedFallback: true,
        isStillNeeded: () => needed,
        fetch: (source) async {
          calls.add(source);
          needed = false;
          return [
            LyricLine(timestamp: Duration.zero, texts: ['ordinary']),
          ];
        },
      );
      expect(calls, ['netease']);
      expect(result, isEmpty);
    },
  );
  List<LyricLine> plain(String text) => [
    LyricLine(
      timestamp: Duration.zero,
      texts: [text],
      allowSyntheticKaraoke: false,
    ),
  ];
  List<LyricLine> timed(String text) => [
    LyricLine(
      timestamp: Duration.zero,
      texts: [text],
      tokens: [
        [
          LyricToken(
            text: text,
            start: Duration.zero,
            end: const Duration(seconds: 1),
          ),
        ],
      ],
    ),
  ];
  for (final selected in ['netease', 'qq', 'kugou']) {
    test(
      '$selected keeps first choice but seeks timed lyrics once per other source in fixed order',
      () async {
        final order = networkLyricSourceOrder(selected);
        final calls = <String>[];
        final result = await resolveNetworkLyrics(
          selectedSource: selected,
          enableFallback: false,
          enableTimedFallback: true,
          fetch: (source) async {
            calls.add(source);
            return source == order.last ? timed(source) : plain(source);
          },
        );
        expect(calls, order);
        expect(calls.toSet(), hasLength(3));
        expect(result.single.texts, [order.last]);
        expect(result.single.hasTimedWords, isTrue);
      },
    );
    test('$selected ordinary match stops when timed fallback is off', () async {
      final calls = <String>[];
      final result = await resolveNetworkLyrics(
        selectedSource: selected,
        enableFallback: true,
        enableTimedFallback: false,
        fetch: (source) async {
          calls.add(source);
          return plain(source);
        },
      );
      expect(calls, [selected]);
      expect(result.single.texts, [selected]);
    });
  }
  test('timed first choice never fetches another platform', () async {
    final calls = <String>[];
    await resolveNetworkLyrics(
      selectedSource: 'qq',
      enableFallback: true,
      enableTimedFallback: true,
      fetch: (source) async {
        calls.add(source);
        return timed(source);
      },
    );
    expect(calls, ['qq']);
  });
  test(
    'all ordinary results retain selected match rather than losing lyrics',
    () async {
      final result = await resolveNetworkLyrics(
        selectedSource: 'kugou',
        enableFallback: false,
        enableTimedFallback: true,
        fetch: (source) async => plain(source),
      );
      expect(result.single.texts, ['kugou']);
    },
  );
  test(
    'missing-only fallback stops at first ordinary result and does not revisit selected',
    () async {
      final calls = <String>[];
      final result = await resolveNetworkLyrics(
        selectedSource: 'netease',
        enableFallback: true,
        enableTimedFallback: false,
        fetch: (source) async {
          calls.add(source);
          return source == 'netease' ? [] : plain(source);
        },
      );
      expect(calls, ['netease', 'qq']);
      expect(result.single.texts, ['qq']);
    },
  );
  test(
    'empty selected plus timed fallback seeks true timing; errors do not discard ordinary backup',
    () async {
      final calls = <String>[], failures = <String>[];
      final result = await resolveNetworkLyrics(
        selectedSource: 'qq',
        enableFallback: false,
        enableTimedFallback: true,
        fetch: (source) async {
          calls.add(source);
          if (source == 'qq') throw StateError('provider failed');
          return plain(source);
        },
        onError: (source, _) => failures.add(source),
      );
      expect(calls, ['qq', 'netease', 'kugou']);
      expect(failures, ['qq']);
      expect(result.single.texts, ['netease']);
    },
  );
  test('both toggles off fetch selected only even when empty', () async {
    final calls = <String>[];
    expect(
      await resolveNetworkLyrics(
        selectedSource: 'qq',
        enableFallback: false,
        enableTimedFallback: false,
        fetch: (source) async {
          calls.add(source);
          return [];
        },
      ),
      isEmpty,
    );
    expect(calls, ['qq']);
  });
  test(
    'invalid or translation-only word timestamps do not satisfy timed fallback',
    () async {
      final invalid = LyricLine(
        timestamp: Duration.zero,
        texts: ['original', 'translated'],
        tokens: [
          [],
          [
            LyricToken(
              text: 'translated',
              start: Duration.zero,
              end: const Duration(seconds: 1),
            ),
          ],
        ],
      );
      final calls = <String>[];
      final result = await resolveNetworkLyrics(
        selectedSource: 'netease',
        enableFallback: false,
        enableTimedFallback: true,
        fetch: (source) async {
          calls.add(source);
          return source == 'netease' ? [invalid] : timed(source);
        },
      );
      expect(calls, ['netease', 'qq']);
      expect(result.single.hasTimedWords, true);
    },
  );
  test(
    'new preference defaults off, persists independently, preserves old selection',
    () async {
      SharedPreferences.setMockInitialValues({
        'enableLyricSourceFallback': true,
        'primaryLyricSource': 'kugou',
      });
      final settings = SettingsProvider();
      await settings.initializationFuture;
      expect(settings.enableTimedLyricSourceFallback, false);
      await settings.setEnableTimedLyricSourceFallback(true);
      await settings.setEnableLyricSourceFallback(false);
      final restored = SettingsProvider();
      await restored.initializationFuture;
      expect(restored.enableTimedLyricSourceFallback, true);
      expect(restored.enableLyricSourceFallback, false);
      expect(restored.primaryLyricSource, 'kugou');
      settings.dispose();
      restored.dispose();
    },
  );
}
