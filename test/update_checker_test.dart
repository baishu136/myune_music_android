import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/update_checker.dart';

void main() {
  group('UpdateChecker.isVersionNewer', () {
    test('compares normal semantic versions', () {
      expect(UpdateChecker.isVersionNewer('0.9.4', '0.9.3'), isTrue);
      expect(UpdateChecker.isVersionNewer('0.9.2', '0.9.3'), isFalse);
    });

    test('compares Android revision suffixes', () {
      expect(
        UpdateChecker.isVersionNewer('v0.9.3-android.3', '0.9.3-android.2'),
        isTrue,
      );
      expect(
        UpdateChecker.isVersionNewer('0.9.3-android.1', '0.9.3-android.2'),
        isFalse,
      );
    });

    test('treats equivalent versions as current', () {
      expect(
        UpdateChecker.isVersionNewer('v0.9.3-android.2', '0.9.3-android.2'),
        isFalse,
      );
    });
  });
}
