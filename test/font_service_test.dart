import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/font_service.dart';

void main() {
  test('font metadata preserves a TTC collection index', () {
    final original = FontMeta(
      fileName: 'collection_3',
      fontFamily: 'Collection Face',
      displayName: 'Collection Face',
      filePath: '/fonts/collection.ttc',
      collectionIndex: 3,
    );

    final restored = FontMeta.fromJson(original.toJson());
    expect(restored.collectionIndex, 3);
  });

  test('legacy font metadata defaults to the first collection face', () {
    final restored = FontMeta.fromJson({
      'fileName': 'legacy',
      'fontFamily': 'Legacy',
      'displayName': 'Legacy',
      'filePath': '/fonts/legacy.ttf',
    });
    expect(restored.collectionIndex, 0);
  });
}
