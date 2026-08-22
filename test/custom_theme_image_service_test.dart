import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/custom_theme_image_service.dart';

void main() {
  test(
    'theme histories are independent and retain only the latest eight',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'myune-theme-history-',
      );
      addTearDown(() => directory.delete(recursive: true));

      for (var index = 0; index < 10; index++) {
        await CustomThemeImageService.save(
          CustomThemeSurface.home,
          Uint8List.fromList([index]),
          targetDirectory: directory,
        );
      }
      await CustomThemeImageService.save(
        CustomThemeSurface.playback,
        Uint8List.fromList([99]),
        targetDirectory: directory,
      );

      final home = await CustomThemeImageService.history(
        CustomThemeSurface.home,
        targetDirectory: directory,
      );
      final playback = await CustomThemeImageService.history(
        CustomThemeSurface.playback,
        targetDirectory: directory,
      );

      expect(home, hasLength(CustomThemeImageService.maxHistoryCount));
      expect(playback, hasLength(1));
      expect(home, orderedEquals([...home]..sort((a, b) => b.compareTo(a))));
      expect(playback.single, contains('playback_'));
    },
  );

  test('removing a history entry permanently deletes its file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'myune-theme-delete-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = await CustomThemeImageService.save(
      CustomThemeSurface.home,
      Uint8List.fromList([1, 2, 3]),
      targetDirectory: directory,
    );

    await CustomThemeImageService.remove(path);

    expect(File(path).existsSync(), isFalse);
    expect(
      await CustomThemeImageService.history(
        CustomThemeSurface.home,
        targetDirectory: directory,
      ),
      isEmpty,
    );
  });
}
