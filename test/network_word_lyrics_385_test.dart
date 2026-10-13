import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myune_music/services/network_lyric_client.dart';
import 'package:myune_music/services/network_qrc_cipher.dart';
import 'package:myune_music/services/network_timed_lyrics.dart';

String _krc(String text) {
  const key = [
    64,
    71,
    97,
    119,
    94,
    50,
    116,
    71,
    81,
    54,
    49,
    45,
    206,
    210,
    110,
    105,
  ];
  final raw = zlib.encode(utf8.encode(text));
  return base64Encode([
    107,
    114,
    99,
    49,
    for (var i = 0; i < raw.length; i++) raw[i] ^ key[i % 16],
  ]);
}

http.Response _json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('YRC preserves absolute word starts, durations and spaces', () {
    final lines = parseNetworkTimedLyrics(
      '[1000,800](1000,300,0)甲 (1300,500,0)乙',
      'yrc',
    );
    expect(lines.single.texts, ['甲 乙']);
    expect(lines.single.tokens!.single.map((t) => t.start.inMilliseconds), [
      1000,
      1300,
    ]);
    expect(lines.single.tokens!.single.map((t) => t.end.inMilliseconds), [
      1300,
      1800,
    ]);
  });
  test('KRC words are relative to the row and global offset applies once', () {
    final lines = parseNetworkTimedLyrics(
      '[offset:50]\n[1000,800]<0,300,0>甲<300,500,0>乙',
      'krc',
    );
    expect(lines.single.timestamp.inMilliseconds, 1050);
    expect(lines.single.tokens!.single.first.start.inMilliseconds, 1050);
    expect(lines.single.tokens!.single.last.end.inMilliseconds, 1850);
  });
  test('QRC reads XML entities and suffix timing without estimating words', () {
    final data = decodeNetworkLyrics((
      'qq',
      {
        'qrc': 1,
        'lyric':
            '<QrcInfos><LyricInfo><Lyric_1 LyricContent="[1000,800]甲&amp;(1000,300)乙(1300,500)&#10;[5000,400]丙(5000,400)"/></LyricInfo></QrcInfos>',
      },
      false,
    ));
    expect(data.timed, hasLength(2));
    expect(data.timed.first.texts, ['甲&乙']);
    expect(data.timed.first.tokens!.single.last.end.inMilliseconds, 1800);
  });
  test('KRC header, XOR and zlib decode multilingual text', () {
    const text = '[1000,800]<0,300,0>甲<300,500,0>乙';
    expect(decodeKrc(_krc(text)), text);
    final data = decodeNetworkLyrics(('krc', {'content': _krc(text)}, false));
    expect(data.timed.single.tokens!.single, hasLength(2));
  });
  test('decreasing word timestamps cannot produce a backwards highlight', () {
    expect(
      parseNetworkTimedLyrics('[1000,800](1300,400,0)甲(1000,300,0)乙', 'yrc'),
      isEmpty,
    );
  });
  test(
    'QQ XML translation is optional and malformed translation keeps words',
    () {
      final payload = {
        'qrc': 1,
        'lyric': '[1000,800]甲(1000,800)',
        'trans': '<QrcInfos><Lyric_1 LyricContent="[00:01.00]译文"/></QrcInfos>',
      };
      final translated = decodeNetworkLyrics(('qq', payload, true));
      expect(translated.timed.single.texts, ['甲', '译文']);
      final malformed = decodeNetworkLyrics((
        'qq',
        {...payload, 'trans': '<bad'},
        true,
      ));
      expect(malformed.timed.single.texts, ['甲']);
      expect(
        malformed.timed.single.tokens!.single.single.end.inMilliseconds,
        1800,
      );
    },
  );
  test('ordinary LRC is not falsely classified as platform word timing', () {
    expect(parseNetworkTimedLyrics('[00:01.00]甲乙', 'yrc'), isEmpty);
    final data = decodeNetworkLyrics((
      'qq',
      {'qrc': 0, 'lyric': base64Encode(utf8.encode('[00:01.00]甲乙'))},
      false,
    ));
    expect(data.timed, isEmpty);
    expect(data.lrc, ['[00:01.00]甲乙']);
  });
  test('Kugou fallback splits BOM, CRLF and all rows', () {
    final data = decodeNetworkLyrics((
      'kugouLrc',
      {
        'content': base64Encode(
          utf8.encode('\uFEFF[00:01.00]甲\r\n[00:02.00]乙\r[00:03.00]丙'),
        ),
      },
      false,
    ));
    expect(data.lrc, ['[00:01.00]甲', '[00:02.00]乙', '[00:03.00]丙']);
  });
  test(
    'YRC translation is optional and cannot create timed translation tokens',
    () {
      final payload = {
        'yrc': {'lyric': '[1000,800](1000,300,0)甲(1300,500,0)乙'},
        'tlyric': {'lyric': '[00:01.10]译文'},
      };
      final off = decodeNetworkLyrics(('netease', payload, false));
      final on = decodeNetworkLyrics(('netease', payload, true));
      expect(off.timed.single.texts, ['甲乙']);
      expect(on.timed.single.texts, ['甲乙', '译文']);
      expect(on.timed.single.tokens!.length, 1);
      expect(
        on.timed.single.tokens!.single.last.end,
        off.timed.single.tokens!.single.last.end,
      );
    },
  );
  test(
    'distant translation rows are not attached to unrelated singing rows',
    () {
      final data = decodeNetworkLyrics((
        'netease',
        {
          'yrc': {'lyric': '[1000,800](1000,800,0)甲'},
          'tlyric': {'lyric': '[00:03.00]其他行'},
        },
        true,
      ));
      expect(data.timed.single.texts, ['甲']);
    },
  );
  test(
    'KRC language translations preserve genuine word tracks and respect toggle',
    () {
      final language = base64Encode(
        utf8.encode(
          jsonEncode({
            'content': [
              {
                'type': 1,
                'lyricContent': [
                  ['译文甲'],
                  ['译文乙'],
                ],
              },
            ],
          }),
        ),
      );
      final content = _krc(
        '[language:$language]\n[1000,400]<0,400,0>甲\n[5000,400]<0,400,0>乙',
      );
      final off = decodeNetworkLyrics(('krc', {'content': content}, false));
      final on = decodeNetworkLyrics(('krc', {'content': content}, true));
      expect(off.timed.first.texts, ['甲']);
      expect(on.timed.first.texts, ['甲', '译文甲']);
      expect(on.timed.last.tokens!.single.single.start.inMilliseconds, 5000);
    },
  );
  test(
    'corrupt compressed, encrypted or impossible timing responses fail closed',
    () {
      expect(
        decodeNetworkLyrics((
          'krc',
          {
            'content': base64Encode([1, 2, 3, 4]),
          },
          false,
        )).isEmpty,
        isTrue,
      );
      expect(
        decodeNetworkLyrics((
          'qq',
          {'qrc': 1, 'lyric': '0000000000000000'},
          false,
        )).isEmpty,
        isTrue,
      );
      expect(
        parseNetworkTimedLyrics('[9999999999,600](9999999999,600,0)甲', 'yrc'),
        isEmpty,
      );
      expect(parseNetworkTimedLyrics('[1000,0](1000,0,0)甲', 'yrc'), isEmpty);
      expect(() => decryptQrcCloud(Uint8List(7)), throwsFormatException);
    },
  );
  test('decompression and row text have bounded resource use', () {
    final huge = '甲' * (networkLyricByteLimit ~/ 3 + 1);
    expect(() => decodeKrc(_krc(huge)), throwsFormatException);
    expect(
      () => parseNetworkTimedLyrics('x' * (networkLyricByteLimit + 1), 'yrc'),
      throwsFormatException,
    );
  });
  test(
    'NetEase requests YRC and keeps ordinary fallback on the selected id',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        if (r.url.path.contains('search')) {
          return _json({
            'result': {
              'songs': [
                {
                  'id': 3,
                  'name': '甲',
                  'artists': [
                    {'name': '歌手'},
                  ],
                },
              ],
            },
          });
        }
        if (r.url.path.endsWith('/v1')) {
          return _json({
            'yrc': {'lyric': '[1000,400](1000,400,0)甲'},
            'lrc': {'lyric': '[00:01.00]甲'},
          });
        }
        throw StateError('unexpected ordinary retry');
      });
      final data = await NetworkLyricClient(
        client: client,
      ).fetch(source: 'netease', title: '甲', artist: '歌手');
      expect(
        data.timed.single.tokens!.single.single.start.inMilliseconds,
        1000,
      );
      expect(requests, hasLength(2));
      expect(requests.last.bodyFields['yv'], '0');
      client.close();
    },
  );
  test(
    'failed modern NetEase request retries ordinary lyrics without searching again',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        if (r.url.path.contains('search')) {
          return _json({
            'result': {
              'songs': [
                {
                  'id': 3,
                  'name': '甲',
                  'artists': [
                    {'name': '歌手'},
                  ],
                },
              ],
            },
          });
        }
        if (r.url.path.endsWith('/v1')) {
          return http.Response('', 503);
        }
        expect(r.url.queryParameters['id'], '3');
        return _json({
          'lrc': {'lyric': '[00:01.00]甲\n[00:02.00]乙'},
        });
      });
      final data = await NetworkLyricClient(
        client: client,
      ).fetch(source: 'netease', title: '甲', artist: '歌手');
      expect(data.timed, isEmpty);
      expect(data.lrc, hasLength(2));
      expect(requests, hasLength(3));
      client.close();
    },
  );
  test(
    'a wrong artist search hit cannot silently become the current song lyric',
    () async {
      var calls = 0;
      final client = MockClient((r) async {
        calls++;
        return _json({
          'result': {
            'songs': [
              {
                'id': 3,
                'name': '甲',
                'artists': [
                  {'name': '其他歌手'},
                ],
              },
            ],
          },
        });
      });
      final data = await NetworkLyricClient(
        client: client,
      ).fetch(source: 'netease', title: '甲', artist: '歌手甲');
      expect(data.isEmpty, isTrue);
      expect(calls, 1);
      client.close();
    },
  );
  test('Kugou prefers KRC over ordinary lyrics using HTTPS', () async {
    final client = MockClient((r) async {
      expect(r.url.scheme, 'https');
      if (r.url.path.contains('search/song')) {
        throw StateError('direct lyric search should not search song hashes');
      }
      if (r.url.path == '/search') {
        expect(r.url.host, 'lyrics.kugou.com');
        expect(r.url.queryParameters.containsKey('duration'), isFalse);
        expect(r.headers.containsKey('user-agent'), isFalse);
        return _json({
          'candidates': [
            {
              'id': '1',
              'accesskey': 'fixture-public-key',
              'song': '甲',
              'singer': '歌手',
            },
          ],
        });
      }
      expect(r.url.queryParameters['fmt'], 'krc');
      return _json({'content': _krc('[1000,400]<0,400,0>甲')});
    });
    final data = await NetworkLyricClient(
      client: client,
    ).fetch(source: 'kugou', title: '甲', artist: '歌手');
    expect(data.timed.single.tokens!.single.single.start.inMilliseconds, 1000);
    client.close();
  });
  test(
    'Kugou HTTPS alias and broken KRC still recover complete multiline LRC',
    () async {
      var downloads = 0;
      final client = MockClient((r) async {
        if (r.url.host == 'lyrics.kugou.com' && r.url.path == '/search') {
          return _json({'candidates': []});
        }
        if (r.url.host == 'mobilecdnbj.kugou.com') {
          return http.Response('', 503);
        }
        if (r.url.path.contains('search/song')) {
          expect(r.url.host, 'mobilecdn.kugou.com');
          return _json({
            'data': {
              'info': [
                {'hash': 'h', 'songname': '甲', 'singername': '歌手'},
              ],
            },
          });
        }
        if (r.url.path == '/search') {
          expect(r.url.host, 'krcs.kugou.com');
          return _json({
            'candidates': [
              {'id': '1', 'accesskey': 'fixture-public-key'},
            ],
          });
        }
        downloads++;
        return _json({
          'content': r.url.queryParameters['fmt'] == 'krc'
              ? 'broken'
              : base64Encode(utf8.encode('[00:01.00]甲\n[00:02.00]乙')),
        });
      });
      final data = await NetworkLyricClient(
        client: client,
      ).fetch(source: 'kugou', title: '甲', artist: '歌手');
      expect(downloads, 2);
      expect(data.timed, isEmpty);
      expect(data.lrc, hasLength(2));
      client.close();
    },
  );
  test(
    'Kugou title-only retry keeps artist matching and millisecond duration',
    () async {
      var searches = 0;
      final client = MockClient((r) async {
        if (r.url.path == '/search') {
          searches++;
          expect(r.url.queryParameters['duration'], '269000');
          if (searches == 1) {
            expect(r.url.queryParameters['keyword'], '甲 歌手');
            return _json({'candidates': []});
          }
          expect(r.url.queryParameters['keyword'], '甲');
          return _json({
            'candidates': [
              {
                'id': '1',
                'accesskey': 'fixture-key',
                'song': '甲',
                'singer': '其他歌手',
              },
              {
                'id': '2',
                'accesskey': 'fixture-key',
                'song': '甲',
                'singer': '歌手',
              },
            ],
          });
        }
        expect(r.url.queryParameters['id'], '2');
        return _json({'content': _krc('[1000,400]<0,400,0>甲')});
      });
      final data = await NetworkLyricClient(client: client).fetch(
        source: 'kugou',
        title: '甲',
        artist: '歌手',
        duration: const Duration(seconds: 269),
      );
      expect(data.timed, hasLength(1));
      expect(searches, 2);
      client.close();
    },
  );
  test(
    'QQ rejected desktop search uses matching official song suggestions',
    () async {
      final calls = <String>[];
      final client = MockClient((r) async {
        calls.add(r.url.path);
        if (r.url.path.contains('smartbox')) {
          expect(r.url.queryParameters['key'], '甲');
          return _json({
            'data': {
              'song': {
                'itemlist': [
                  {'id': '4', 'mid': 'wrong', 'name': '甲', 'singer': '其他歌手'},
                  {'id': '3', 'mid': 'mid', 'name': '甲', 'singer': '歌手'},
                ],
              },
            },
          });
        }
        final body = jsonDecode(r.body);
        if (body['music.search.SearchCgiService'] != null) {
          return _json({
            'music.search.SearchCgiService': {'code': 2001},
          });
        }
        expect(body['req_0']['param']['songId'], 3);
        expect(body['req_0']['param']['songMid'], 'mid');
        return _json({
          'req_0': {
            'code': 0,
            'data': {'qrc': 1, 'lyric': '[1000,400]甲(1000,400)'},
          },
        });
      });
      final data = await NetworkLyricClient(
        client: client,
      ).fetch(source: 'qq', title: '甲', artist: '歌手');
      expect(
        data.timed.single.tokens!.single.single.start.inMilliseconds,
        1000,
      );
      expect(calls, hasLength(3));
      client.close();
    },
  );
  test('QQ suggestion fallback rejects a different artist', () async {
    var calls = 0;
    final client = MockClient((r) async {
      calls++;
      if (r.url.path.contains('smartbox')) {
        return _json({
          'data': {
            'song': {
              'itemlist': [
                {'id': '3', 'mid': 'mid', 'name': '甲', 'singer': '其他歌手'},
              ],
            },
          },
        });
      }
      return _json({
        'music.search.SearchCgiService': {'code': 2001},
      });
    });
    final data = await NetworkLyricClient(
      client: client,
    ).fetch(source: 'qq', title: '甲', artist: '歌手甲');
    expect(data.isEmpty, isTrue);
    expect(calls, 2);
    client.close();
  });
  test(
    'QQ corrupt QRC falls back to Base64 LRC of the same id and respects translation',
    () async {
      var searches = 0, requests = 0;
      final client = MockClient((r) async {
        requests++;
        if (r.method == 'POST') {
          final body = jsonDecode(r.body);
          if (body['music.search.SearchCgiService'] != null) {
            searches++;
            return _json({
              'music.search.SearchCgiService': {
                'data': {
                  'body': {
                    'song': {
                      'list': [
                        {
                          'id': 3,
                          'mid': 'mid',
                          'title': '甲',
                          'singer': [
                            {'name': '歌手'},
                          ],
                        },
                      ],
                    },
                  },
                },
              },
            });
          }
          expect(body['req_0']['param']['qrc'], 1);
          return _json({
            'req_0': {
              'code': 0,
              'data': {'qrc': 1, 'lyric': '0000000000000000'},
            },
          });
        }
        expect(r.url.queryParameters['songmid'], 'mid');
        return _json({
          'lyric': base64Encode(utf8.encode('[00:01.00]甲\n[00:02.00]乙')),
          'trans': base64Encode(utf8.encode('[00:01.00]译文')),
        });
      });
      final data = await NetworkLyricClient(
        client: client,
      ).fetch(source: 'qq', title: '甲', artist: '歌手');
      expect(searches, 1);
      expect(requests, 3);
      expect(data.lrc, hasLength(2));
      expect(data.translation, isEmpty);
      client.close();
    },
  );
}
