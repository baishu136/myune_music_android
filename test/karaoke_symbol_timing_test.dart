import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/widgets/synthetic_karaoke_timing.dart';

void main() {
  test('device Reminder line uses its actual 39.10 to 41.86 LRC interval', () {
    final source = LyricLine(
      timestamp: const Duration(milliseconds: 39100),
      texts: ['Goddamn, *****, I am not a bleach boy'],
    );
    final timed = synthesizeKaraokeTiming(
      source,
      nextTimestamp: const Duration(milliseconds: 41860),
    );
    final stars = timed.tokens!.first.singleWhere(
      (t) => t.text.startsWith('*****'),
    );
    expect((stars.end - stars.start).inMilliseconds, greaterThan(200));
    expect(timed.timestamp, source.timestamp);
    expect(timed.texts, source.texts);
    expect(
      timed.tokens!.first.last.end,
      const Duration(microseconds: 41804800),
    );
  });
  test(
    'standalone symbols are visible while ordinary punctuation stays a short beat',
    () {
      for (final symbol in ['*', '＊', '✱', '★']) {
        final line = synthesizeKaraokeTiming(
          LyricLine(timestamp: Duration.zero, texts: ['a $symbol , b']),
          nextTimestamp: const Duration(seconds: 3),
        );
        final tokens = line.tokens!.first;
        final sung = tokens.singleWhere((t) => t.text.trim() == symbol);
        final comma = tokens.singleWhere((t) => t.text.trim() == ',');
        expect(
          sung.end - sung.start,
          greaterThan((comma.end - comma.start) * 3),
        );
      }
    },
  );
  test(
    'censored symbol words receive a visible sweep, not a punctuation beat',
    () {
      for (final symbols in ['*****', '✱✱✱✱✱', '＊＊＊＊＊']) {
        final line = synthesizeKaraokeTiming(
          LyricLine(
            timestamp: Duration.zero,
            texts: ['Goddamn, $symbols, I am not a bleach boy'],
          ),
          nextTimestamp: const Duration(seconds: 3),
        );
        final token = line.tokens!.first.singleWhere(
          (t) => t.text.startsWith(symbols),
        );
        expect(
          (token.end - token.start).inMicroseconds,
          greaterThan(200000),
          reason:
              'a censored word must remain visible over multiple display frames',
        );
        for (final hz in [60, 90, 120]) {
          final duration = (token.end - token.start).inMicroseconds;
          var previous = 0.0;
          var intermediate = 0;
          for (
            var elapsed = 0;
            elapsed < duration;
            elapsed += (1e6 / hz).round()
          ) {
            final progress = elapsed / duration;
            expect(progress, greaterThanOrEqualTo(previous));
            if (progress > 0 && progress < 1) intermediate++;
            previous = progress;
          }
          expect(intermediate, greaterThanOrEqualTo(10));
        }
      }
    },
  );
  test(
    'actual symbol timestamps take precedence over synthetic allocation',
    () {
      final real = LyricLine(
        timestamp: Duration.zero,
        texts: ['*****'],
        tokens: [
          [
            LyricToken(
              text: '*****',
              start: const Duration(milliseconds: 50),
              end: const Duration(milliseconds: 100),
            ),
          ],
        ],
      );
      expect(
        synthesizeKaraokeTiming(
          real,
          nextTimestamp: const Duration(seconds: 4),
        ),
        same(real),
      );
    },
  );
}
