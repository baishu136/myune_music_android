import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/services/artwork_memory_cache.dart';

void main() {
  test('LRU keeps recently accessed thumbnails', () {
    final cache = ArtworkMemoryCache(maximumEntries: 2, maximumBytes: 20);
    cache['a'] = Uint8List.fromList([1]);
    cache['b'] = Uint8List.fromList([2]);
    expect(cache['a'], isNotNull);
    cache['c'] = Uint8List.fromList([3]);

    expect(cache.containsKey('a'), isTrue);
    expect(cache.containsKey('b'), isFalse);
    expect(cache.containsKey('c'), isTrue);
  });

  test('LRU also respects its byte budget', () {
    final cache = ArtworkMemoryCache(maximumEntries: 10, maximumBytes: 4);
    cache['a'] = Uint8List(3);
    cache['b'] = Uint8List.fromList([1, 1, 1]);
    expect(cache.containsKey('a'), isFalse);
    expect(cache.bytes, 3);
  });

  test('identical artwork shares one canonical byte object', () {
    final cache = ArtworkMemoryCache(maximumEntries: 10, maximumBytes: 20);
    cache['a'] = Uint8List.fromList([1, 2, 3]);
    cache['b'] = Uint8List.fromList([1, 2, 3]);
    expect(identical(cache['a'], cache['b']), isTrue);
    expect(cache.bytes, 3);
  });
}
