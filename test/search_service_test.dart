import 'package:flutter_test/flutter_test.dart';
import 'package:myune_music/page/playlist/playlist_models.dart';
import 'package:myune_music/services/search_service.dart';

void main() {
  final songs = [
    Song(
      title: '光辉岁月',
      artist: 'Beyond',
      album: '命运派对',
      filePath: '/music/guang-hui.mp3',
    ),
    Song(
      title: '打上花火',
      artist: 'DAOKO',
      album: 'THANK YOU BLUE',
      filePath: '/music/uchiage.mp3',
    ),
  ];

  test('searches title using full pinyin and initials', () {
    final service = SearchService()..rebuild(songs);

    expect(service.search('guanghuisuiyue', songs).first.title, '光辉岁月');
    expect(service.search('ghsy', songs).first.title, '光辉岁月');
  });

  test('searches artist and album, then tolerates skipped characters', () {
    final service = SearchService()..rebuild(songs);

    expect(service.search('daoko', songs).single.title, '打上花火');
    expect(service.search('thank blue', songs).single.title, '打上花火');
    expect(service.search('打花', songs).single.title, '打上花火');
  });
}
