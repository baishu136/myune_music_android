import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/widgets/library_entrance_motion.dart';

void main() {
  testWidgets(
    'late songs animate even after startup intent completed while hidden',
    (tester) async {
      var visible = false, loaded = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return TickerMode(
                enabled: visible,
                child: LibraryEntranceMotion(
                  animation: const AlwaysStoppedAnimation(1),
                  child: loaded
                      ? ListView(
                          children: [
                            buildLibrarySongEntranceTransition(
                              animation: const AlwaysStoppedAnimation(1),
                              order: 0,
                              child: const SizedBox(
                                height: 80,
                                child: Text('late song'),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox(),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      update(() => loaded = true);
      await tester.pump();
      update(() => visible = true);
      await tester.pump();
      await tester.pump();
      FadeTransition pose() => tester.widget<FadeTransition>(
        find.byKey(const ValueKey('library-entrance-0')),
      );
      expect(pose().opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(pose().opacity.value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(pose().opacity.value, 1);
      update(() => visible = false);
      await tester.pump();
      update(() => visible = true);
      await tester.pumpAndSettle();
      expect(pose().opacity.value, 1);
    },
  );
}
