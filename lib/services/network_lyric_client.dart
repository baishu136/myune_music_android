import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;

import 'network_timed_lyrics.dart';

Map<String, dynamic> _networkJson(Uint8List bytes) {
  final value = jsonDecode(utf8.decode(bytes));
  return value is Map<String, dynamic> ? value : const {};
}

String _requestJson(Object? body) {
  final buffer = StringBuffer();
  for (final unit in jsonEncode(body).codeUnits) {
    if (unit > 127) {
      buffer.write(r'\u');
      buffer.write(unit.toRadixString(16).padLeft(4, '0'));
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

class NetworkLyricClient {
  NetworkLyricClient({http.Client? client}) : _client = client;
  final http.Client? _client;
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/102.0.0.0 Safari/537.36',
  };

  Future<NetworkLyricContent> fetch({
    required String source,
    required String title,
    required String artist,
    Duration? duration,
    bool translation = false,
  }) async {
    final client = _client ?? http.Client();
    final performer = artist.startsWith('未知歌手') ? '' : artist.trim();
    try {
      final request = switch (source) {
        'netease' => _netease(
          client,
          title.trim(),
          performer,
          duration,
          translation,
        ),
        'qq' => _qq(client, title.trim(), performer, duration, translation),
        _ => _kugou(client, title.trim(), performer, duration, translation),
      };
      return await request.timeout(const Duration(seconds: 35));
    } catch (_) {
      return const NetworkLyricContent();
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<Map<String, dynamic>> _json(
    http.Client client,
    Uri uri, {
    Object? body,
    String? referer,
    bool form = false,
  }) async {
    try {
      final headers = {
        if (!uri.host.endsWith('.kugou.com')) ..._headers,
        if (referer != null) 'Referer': referer,
        if (body != null && !form)
          'Content-Type': 'application/json; charset=utf-8',
      };
      final response =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(
                      uri,
                      headers: headers,
                      body: form ? body : _requestJson(body),
                    ))
              .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > networkLyricByteLimit) {
        return const {};
      }
      return await compute(_networkJson, response.bodyBytes);
    } catch (_) {
      return const {};
    }
  }

  Future<NetworkLyricContent> _decode(
    String format,
    Map<String, dynamic> data,
    bool translation,
  ) => compute(decodeNetworkLyrics, (format, data, translation));

  Map<String, dynamic>? _song(
    List<dynamic> songs,
    String title,
    String artist,
    Duration? duration,
    String source,
  ) {
    String normalized(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[\s\-_.·／/]+'), '');
    final wantedTitle = normalized(title), wantedArtist = normalized(artist);
    Map<String, dynamic>? best;
    var bestScore = -double.infinity;
    for (final item in songs) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final filename = (item['filename'] ?? '').toString().split(' - ');
      final name = normalized(
        (item['name'] ??
                item['title'] ??
                item['songname'] ??
                item['song'] ??
                (filename.length > 1
                    ? filename.skip(1).join(' - ')
                    : filename.first))
            .toString(),
      );
      final performers = item['artists'] ?? item['singer'];
      final rawSinger = performers is List
          ? performers.map((s) => s is Map ? s['name'] ?? '' : s).join(' ')
          : (performers is String
                    ? performers
                    : item['singername'] ??
                          (filename.length > 1 ? filename.first : ''))
                .toString();
      final singer = normalized(rawSinger);
      List<String> artistNames(String value) => value
          .split(RegExp(r'[/／,，、;&＆]+'))
          .map(normalized)
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
      final singers = performers is List
          ? performers
                .map(
                  (s) =>
                      normalized((s is Map ? s['name'] ?? '' : s).toString()),
                )
                .toList(growable: false)
          : artistNames(rawSinger);
      final artistMatches =
          singer == wantedArtist || artistNames(artist).every(singers.contains);
      if (name.isNotEmpty &&
          !name.contains(wantedTitle) &&
          !wantedTitle.contains(name)) {
        continue;
      }
      if (wantedArtist.isNotEmpty && singer.isNotEmpty && !artistMatches) {
        continue;
      }
      var score = name == wantedTitle
          ? 10.0
          : name.contains(wantedTitle)
          ? 3.0
          : 0.0;
      if (wantedArtist.isNotEmpty && singer.isNotEmpty && artistMatches) {
        score += 6;
      }
      final rawDuration = item['duration'] ?? item['dt'] ?? item['interval'];
      if (duration != null && rawDuration is num) {
        final milliseconds =
            rawDuration.toDouble() *
            (source == 'netease' || rawDuration > 10000 ? 1 : 1000);
        score -=
            ((milliseconds - duration.inMilliseconds).abs() / 1000).clamp(
              0,
              20,
            ) *
            .2;
      }
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return best;
  }

  Future<NetworkLyricContent> _netease(
    http.Client client,
    String title,
    String artist,
    Duration? duration,
    bool translation,
  ) async {
    final search = await _json(
      client,
      Uri.https('music.163.com', '/api/search/get/', {
        's': '$title $artist'.trim(),
        'type': '1',
        'limit': '5',
      }),
      referer: 'https://music.163.com',
    );
    final song = _song(
      search['result']?['songs'] as List? ?? const [],
      title,
      artist,
      duration,
      'netease',
    );
    if (song?['id'] == null) return const NetworkLyricContent();
    final id = song!['id'].toString();
    final modern = await _json(
      client,
      Uri.https('music.163.com', '/api/song/lyric/v1'),
      referer: 'https://music.163.com',
      form: true,
      body: {
        'id': id,
        'cp': 'false',
        'lv': '0',
        'tv': '0',
        'rv': '0',
        'kv': '0',
        'yv': '0',
        'ytv': '0',
        'yrv': '0',
      },
    );
    final decoded = await _decode('netease', modern, translation);
    if (!decoded.isEmpty) return decoded;
    final old = await _json(
      client,
      Uri.https('music.163.com', '/api/song/lyric', {
        'os': 'pc',
        'id': id,
        'lv': '-1',
        if (translation) 'tv': '-1',
      }),
      referer: 'https://music.163.com',
    );
    return _decode('netease', old, translation);
  }

  Future<NetworkLyricContent> _qq(
    http.Client client,
    String title,
    String artist,
    Duration? duration,
    bool translation,
  ) async {
    final search = await _json(
      client,
      Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg'),
      body: {
        'comm': {'ct': '19', 'cv': '1873', 'uin': '0'},
        'music.search.SearchCgiService': {
          'module': 'music.search.SearchCgiService',
          'method': 'DoSearchForQQMusicDesktop',
          'param': {
            'grp': 1,
            'num_per_page': 40,
            'page_num': 1,
            'query': artist.isEmpty ? title : '$artist - $title',
            'search_type': 0,
          },
        },
      },
    );
    var song = _song(
      search['music.search.SearchCgiService']?['data']?['body']?['song']?['list']
              as List? ??
          const [],
      title,
      artist,
      duration,
      'qq',
    );
    if (song == null) {
      final suggestions = await _json(
        client,
        Uri.https('c.y.qq.com', '/splcloud/fcgi-bin/smartbox_new.fcg', {
          'key': title,
          'format': 'json',
        }),
        referer: 'https://y.qq.com/',
      );
      song = _song(
        suggestions['data']?['song']?['itemlist'] as List? ?? const [],
        title,
        artist,
        duration,
        'qq',
      );
    }
    if (song == null || song['id'] == null || song['mid'] == null) {
      return const NetworkLyricContent();
    }
    final songId = int.tryParse(song['id'].toString());
    if (songId == null) return const NetworkLyricContent();
    final modern = await _json(
      client,
      Uri.https('u.y.qq.com', '/cgi-bin/musicu.fcg'),
      referer: 'https://y.qq.com/',
      body: {
        'comm': {'ct': 19, 'cv': 1873, 'uin': '0'},
        'req_0': {
          'module': 'music.musichallSong.PlayLyricInfo',
          'method': 'GetPlayLyricInfo',
          'param': {
            'songId': songId,
            'songMid': song['mid'],
            'qrc': 1,
            'crypt': 1,
            'trans': translation ? 1 : 0,
            'roma': 0,
          },
        },
      },
    );
    final data = modern['req_0']?['data'];
    if (modern['req_0']?['code'] == 0 && data is Map<String, dynamic>) {
      final decoded = await _decode('qq', data, translation);
      if (!decoded.isEmpty) {
        return decoded;
      }
    }
    final old = await _json(
      client,
      Uri.https('c.y.qq.com', '/lyric/fcgi-bin/fcg_query_lyric_new.fcg', {
        'songmid': song['mid'].toString(),
        'musicid': song['id'].toString(),
        'format': 'json',
        'g_tk': '5381',
      }),
      referer: 'https://y.qq.com/n/ryqq/player',
    );
    return _decode('qqLrc', old, translation);
  }

  Future<NetworkLyricContent> _kugou(
    http.Client client,
    String title,
    String artist,
    Duration? duration,
    bool translation,
  ) async {
    var response = await _json(
      client,
      Uri.https('lyrics.kugou.com', '/search', {
        'ver': '1',
        'man': 'yes',
        'client': 'pc',
        'keyword': '$title $artist'.trim(),
        if (duration != null) 'duration': duration.inMilliseconds.toString(),
      }),
    );
    var candidates = response['candidates'];
    if ((candidates is! List || candidates.isEmpty) && artist.isNotEmpty) {
      response = await _json(
        client,
        Uri.https('lyrics.kugou.com', '/search', {
          'ver': '1',
          'man': 'yes',
          'client': 'pc',
          'keyword': title,
          if (duration != null) 'duration': duration.inMilliseconds.toString(),
        }),
      );
      candidates = response['candidates'];
    }
    if (candidates is! List || candidates.isEmpty) {
      final query = {
        'keyword': '$title $artist'.trim(),
        'page': '1',
        'pagesize': '5',
      };
      var search = await _json(
        client,
        Uri.https('mobilecdnbj.kugou.com', '/api/v3/search/song', query),
      );
      if (search['data']?['info'] is! List) {
        search = await _json(
          client,
          Uri.https('mobilecdn.kugou.com', '/api/v3/search/song', query),
        );
      }
      final song = _song(
        search['data']?['info'] as List? ?? const [],
        title,
        artist,
        duration,
        'kugou',
      );
      if (song == null || song['hash'] == null) {
        return const NetworkLyricContent();
      }
      response = await _json(
        client,
        Uri.https('krcs.kugou.com', '/search', {
          'man': 'yes',
          'hash': song['hash'].toString(),
        }),
      );
      candidates = response['candidates'];
    }
    if (candidates is! List) {
      return const NetworkLyricContent();
    }
    final chosen = _song(candidates, title, artist, duration, 'kugou');
    if (chosen == null) return const NetworkLyricContent();
    final eligible = [
      chosen,
      ...candidates.where(
        (candidate) =>
            !identical(candidate, chosen) &&
            _song([candidate], title, artist, duration, 'kugou') != null,
      ),
    ];
    var ordinary = const NetworkLyricContent();
    for (final candidate in eligible.take(3)) {
      if (candidate is! Map ||
          candidate['id'] == null ||
          candidate['accesskey'] == null) {
        continue;
      }
      final base = {
        'ver': '1',
        'id': candidate['id'].toString(),
        'accesskey': candidate['accesskey'].toString(),
        'charset': 'utf8',
      };
      final krc = await _json(
        client,
        Uri.https('lyrics.kugou.com', '/download', {...base, 'fmt': 'krc'}),
      );
      final timed = await _decode('krc', krc, translation);
      if (!timed.isEmpty) {
        return timed;
      }
      final lrc = await _json(
        client,
        Uri.https('lyrics.kugou.com', '/download', {...base, 'fmt': 'lrc'}),
      );
      final fallback = await _decode('kugouLrc', lrc, translation);
      if (ordinary.isEmpty && !fallback.isEmpty) {
        ordinary = fallback;
      }
    }
    return ordinary;
  }
}
