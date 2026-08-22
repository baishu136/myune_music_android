import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/app_version.dart';

void main() {
  test('Android display version follows package metadata', () {
    expect(
      AppVersion.format(version: '0.9.8', buildNumber: '114', android: true),
      '0.9.8-android.114',
    );
  });

  test('Android split APK ABI offset is hidden from the display version', () {
    expect(
      AppVersion.format(version: '0.9.8', buildNumber: '2114', android: true),
      '0.9.8-android.114',
    );
  });

  test('desktop display version keeps the package build number', () {
    expect(
      AppVersion.format(version: '0.9.8', buildNumber: '114', android: false),
      '0.9.8+114',
    );
  });
}
