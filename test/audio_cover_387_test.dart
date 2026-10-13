import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myune_music/page/setting/settings_provider.dart';
import 'package:myune_music/widgets/now_playing_cover_glow.dart';

void main() {
  test(
    'new cover choices restore 90 percent and migrate old 60 to 80',
    () async {
      for (final pair in [(0.9, 0.9), (0.8, 0.8), (0.6, 0.8), (1.0, 1.0)]) {
        SharedPreferences.setMockInitialValues({'playbackCoverScale': pair.$1});
        final settings = SettingsProvider();
        await settings.initializationFuture;
        expect(settings.playbackCoverScale, pair.$2);
        await settings.setPlaybackCoverScale(.9);
        expect(
          (await SharedPreferences.getInstance()).getDouble(
            'playbackCoverScale',
          ),
          .9,
        );
        await settings.setPlaybackCoverScale(.6);
        expect(settings.playbackCoverScale, .9);
        settings.dispose();
      }
    },
  );
  testWidgets(
    'cover halo is narrow white at ten percent and retains child identity',
    (tester) async {
      const child = SizedBox(
        key: ValueKey('retained-cover'),
        width: 100,
        height: 100,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: NowPlayingCoverGlow(enabled: true, child: child)),
        ),
      );
      await tester.pumpAndSettle();
      final decorator = find
          .descendant(
            of: find.byType(NowPlayingCoverGlow),
            matching: find.byType(DecoratedBox),
          )
          .first;
      final shadow =
          (tester.widget<DecoratedBox>(decorator).decoration as BoxDecoration)
              .boxShadow!
              .single;
      expect(shadow.color.r, 1);
      expect(shadow.color.g, 1);
      expect(shadow.color.b, 1);
      expect(shadow.color.a, closeTo(.1, .002));
      expect(shadow.blurRadius, lessThanOrEqualTo(12));
      expect(shadow.spreadRadius, lessThanOrEqualTo(.5));
      expect(shadow.blurStyle, BlurStyle.outer);
      final element = tester.element(
        find.byKey(const ValueKey('retained-cover')),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: NowPlayingCoverGlow(enabled: false, child: child),
          ),
        ),
      );
      expect(
        identical(
          element,
          tester.element(find.byKey(const ValueKey('retained-cover'))),
        ),
        isTrue,
      );
    },
  );
}
