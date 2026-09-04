import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/setting/theme_selection_screen.dart';

void main() {
  test('theme color hex accepts common RGB color number forms', () {
    expect(parseThemeColorHex('12ABEF'), const Color(0xFF12ABEF));
    expect(parseThemeColorHex('#12abef'), const Color(0xFF12ABEF));
    expect(parseThemeColorHex('0x12ABEF'), const Color(0xFF12ABEF));
    expect(parseThemeColorHex('abc'), const Color(0xFFAABBCC));
  });

  test('theme color hex rejects incomplete or invalid color numbers', () {
    expect(parseThemeColorHex('12ABE'), isNull);
    expect(parseThemeColorHex('ZZZZZZ'), isNull);
    expect(parseThemeColorHex('12345678'), isNull);
  });

  test('theme colors format as an uppercase six-digit RGB number', () {
    expect(formatThemeColorHex(const Color(0xFF0A1B2C)), '0A1B2C');
  });
}
