import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/bili_fav_resource.dart';
import 'package:bilimusic/domain/bili_item.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/search_result.dart';
import 'package:bilimusic/shared/utils/title_meta_filter.dart';

/// 标题元数据过滤在 API 解析入口的接线测试。
///
/// 覆盖开关两侧：关闭时（默认）各解析入口行为与开启前逐字一致；
/// 开启时标题被过滤，其余字段（id / artist / 分区名等）不受影响。
/// 过滤只发生在「新拉取」的解析路径，本地落盘恢复走的 `Music.fromJson`
/// / `Page.fromJson` 不在这些入口里，不会被回溯改写。
void main() {
  group('Music.fromArchiveJson（推荐 / 相关 / 漫游）', () {
    const archiveJson = <String, dynamic>{
      'bvid': 'BV1xx411c7mD',
      'title': '【 作者 / MV 】Starlight【中字】',
      'owner': {'name': 'UP主'},
      'tname': '音乐',
      'pic': 'https://i0.hdslb.com/bfs/archive/x.jpg',
      'duration': 100,
    };

    test('关闭：标题原样', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = false;

      final music = Music.fromArchiveJson(archiveJson);
      expect(music.title, '【 作者 / MV 】Starlight【中字】');
    });

    test('开启：标题过滤，其余字段不受影响', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = true;

      final music = Music.fromArchiveJson(archiveJson);
      expect(music.title, '【作者】Starlight');
      expect(music.id, 'BV1xx411c7mD');
      expect(music.artist, 'UP主');
      // album 语义是分区名，不参与过滤
      expect(music.album, '音乐');
    });
  });

  group('BiliItem.fromViewApi（视频详情）', () {
    const singlePageJson = <String, dynamic>{
      'bvid': 'BV1y',
      'title': '夜に駆ける【中字】',
      'owner': {'mid': 1, 'name': 'UP主', 'face': ''},
      'stat': {},
      'videos': 1,
      'tname': '音乐',
      'duration': 100,
      'pages': [
        {'cid': 11, 'part': 'P1', 'duration': 100},
      ],
      'pubdate': 0,
    };

    const multiPageJson = <String, dynamic>{
      'bvid': 'BV1z',
      'title': '【合集】两只曲子【中字】',
      'owner': {'mid': 1, 'name': 'UP主', 'face': ''},
      'stat': {},
      'videos': 2,
      'tname': '音乐',
      'duration': 200,
      'pages': [
        {'cid': 11, 'part': '第一首【MV】', 'duration': 100},
        {'cid': 12, 'part': '第二首', 'duration': 100},
      ],
      'pubdate': 0,
    };

    test('关闭：单P标题 / album 原样', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = false;

      final item = BiliItem.fromViewApi(singlePageJson);
      expect(item.title, '夜に駆ける【中字】');
      expect(item.pages.single.title, '夜に駆ける【中字】');
      expect(item.pages.single.album, '夜に駆ける【中字】');
    });

    test('开启：单P标题与 album 一起过滤', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = true;

      final item = BiliItem.fromViewApi(singlePageJson);
      expect(item.title, '夜に駆ける');
      expect(item.pages.single.title, '夜に駆ける');
      expect(item.pages.single.album, '夜に駆ける');
    });

    test('开启：多P稿件过滤稿件标题与各分P标题', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = true;

      final item = BiliItem.fromViewApi(multiPageJson);
      expect(item.title, '【合集】两只曲子');
      expect(item.pages[0].title, '第一首');
      expect(item.pages[1].title, '第二首');
      expect(item.pages[0].album, '【合集】两只曲子');
    });
  });

  group('SearchResult.fromJson（搜索）', () {
    const videoJson = <String, dynamic>{
      'bvid': 'BV1a',
      'title': '曲名【自翻】',
      'author': '作者',
      'tag': '音乐',
      'pic': '',
    };

    const authorJson = <String, dynamic>{
      'mid': 5,
      'title': 'MV制作组',
      'fans': '10',
    };

    test('关闭：视频标题原样', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = false;

      final result = SearchResult.fromJson(videoJson, SearchResultType.video);
      expect(result.title, '曲名【自翻】');
    });

    test('开启：视频标题过滤，富文本实体处理不受影响', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = true;

      final result = SearchResult.fromJson(videoJson, SearchResultType.video);
      expect(result.title, '曲名');
      expect(result.subtitle, '作者 - 音乐');
    });

    test('开启：作者名不过滤（避免误伤「MV制作组」这类用户名）', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = true;

      final result = SearchResult.fromJson(authorJson, SearchResultType.author);
      expect(result.title, 'MV制作组');
    });
  });

  group('FavResource.fromJson（收藏夹资源）', () {
    const favJson = <String, dynamic>{
      'id': 1,
      'type': 2,
      'title': '曲名【自翻】',
      'bvid': 'BV1w',
      'duration': 10,
      'upper': {'name': 'u'},
    };

    test('关闭：标题原样', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = false;

      expect(FavResource.fromJson(favJson).title, '曲名【自翻】');
    });

    test('开启：标题过滤，其余字段不受影响', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = true;

      final resource = FavResource.fromJson(favJson);
      expect(resource.title, '曲名');
      expect(resource.bvid, 'BV1w');
      expect(resource.upperName, 'u');
    });
  });
}
