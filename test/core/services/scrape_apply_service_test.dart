import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/services/scrape_apply_service.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';

void main() {
  group('stripVersionFromTitle', () {
    test('去除精确版本号', () {
      expect(
        ScrapeApplyService.stripVersionFromTitle('禁闭乐园 V1.5 中文版', 'V1.5'),
        '禁闭乐园 中文版',
      );
    });

    test('去除通用版本号模式', () {
      expect(
        ScrapeApplyService.stripVersionFromTitle('游戏名 ver2.1 完整版'),
        '游戏名 完整版',
      );
    });

    test('无版本号时原样返回', () {
      expect(
        ScrapeApplyService.stripVersionFromTitle('普通标题'),
        '普通标题',
      );
    });
  });

  group('resolveCategoryName', () {
    test('按优先级匹配分类', () {
      final tags = [
        Tag(name: 'slg', type: Tag.typeCustom),
        Tag(name: 'RPG', type: Tag.typeCustom),
      ];
      expect(ScrapeApplyService.resolveCategoryName(tags), 'RPG');
    });

    test('无匹配时返回 Unclassified', () {
      expect(
        ScrapeApplyService.resolveCategoryName(
            [Tag(name: '汉化', type: Tag.typeCustom)]),
        'Unclassified',
      );
    });

    test('空标签返回 Unclassified', () {
      expect(ScrapeApplyService.resolveCategoryName([]), 'Unclassified');
    });
  });

  group('mergeGameInfo', () {
    test('合并非空字段并去除标题版本号', () {
      final game = Game(path: r'C:\Games\A', title: '旧标题', version: 'V1.0');
      final info = GameInfo(
        title: '新标题 v2.0',
        version: 'V2.0',
        description: '简介',
        features: ['特点1'],
        changelog: '日志',
        downloads: [],
        sourceUrl: 'https://example.com/1',
        maker: '厂商',
        makerUrl: 'https://example.com/maker',
      );
      final merged = ScrapeApplyService.mergeGameInfo(game, info);
      expect(merged.title, '新标题');
      expect(merged.version, 'V2.0');
      expect(merged.intro, '简介');
      expect(merged.features, '特点1');
      expect(merged.changelog, '日志');
      expect(merged.maker, '厂商');
      expect(merged.makerUrl, 'https://example.com/maker');
    });

    test('空字段保留原值', () {
      final game = Game(
        path: r'C:\Games\A',
        title: '旧标题',
        intro: '旧简介',
        downloadUrl: 'https://pan.baidu.com/x',
      );
      final info = GameInfo(sourceUrl: 'https://example.com/1');
      final merged = ScrapeApplyService.mergeGameInfo(game, info);
      expect(merged.title, '旧标题');
      expect(merged.intro, '旧简介');
      expect(merged.downloadUrl, 'https://pan.baidu.com/x');
    });

    test('sourceUrl 覆盖参数生效', () {
      final game = Game(path: r'C:\Games\A', sourceUrl: 'https://old.com');
      final info = GameInfo(sourceUrl: 'https://example.com/1');
      final merged = ScrapeApplyService.mergeGameInfo(game, info,
          sourceUrl: 'https://new.com');
      expect(merged.sourceUrl, 'https://new.com');
    });
  });

  group('buildMetadataJson', () {
    test('基础字段与覆盖字段', () {
      final info = GameInfo(
        title: '标题',
        description: '原简介',
        descriptionHtml: '<p>原</p>',
        sourceUrl: 'https://example.com/1',
      );
      final json = ScrapeApplyService.buildMetadataJson(info,
          intro: '重写简介', introHtml: '<p>重写</p>');
      expect(json['title'], '标题');
      expect(json['intro'], '重写简介');
      expect(json['intro_html'], '<p>重写</p>');
      expect(json['source_url'], 'https://example.com/1');
    });

    test('不传覆盖时保留 gameInfo 原值', () {
      final info = GameInfo(title: '标题', description: '原简介',
          sourceUrl: 'https://example.com/1');
      final json = ScrapeApplyService.buildMetadataJson(info);
      expect(json['intro'], '原简介');
      expect(json.containsKey('intro_html'), isFalse);
    });
  });

  group('已刮削标识 scraped_at', () {
    test('markScraped 写入 ISO 时间戳', () {
      final json = ScrapeApplyService.markScraped({'title': '标题'},
          at: DateTime(2026, 10, 6, 12, 30));
      expect(json[ScrapeApplyService.scrapedAtKey], '2026-10-06T12:30:00.000');
      expect(json['title'], '标题');
    });

    test('isScrapedMetadata 仅在 scraped_at 非空字符串时为真', () {
      expect(ScrapeApplyService.isScrapedMetadata({'scraped_at': '2026-10-06T12:30:00.000'}), isTrue);
      expect(ScrapeApplyService.isScrapedMetadata({'scraped_at': ''}), isFalse);
      expect(ScrapeApplyService.isScrapedMetadata({'scraped_at': null}), isFalse);
      expect(ScrapeApplyService.isScrapedMetadata({'title': '标题'}), isFalse);
      expect(ScrapeApplyService.isScrapedMetadata(null), isFalse);
    });

    test('isGameScraped 读取游戏目录 metadata.json 判断标识', () async {
      final tempDir = await Directory.systemTemp.createTemp('hgm_scraped_test');
      try {
        final gamePath = tempDir.path;
        expect(await ScrapeApplyService.isGameScraped(gamePath), isFalse);

        await GameDataPaths.ensureDataDir(gamePath);
        await GameDataPaths.metadataFile(gamePath).writeAsString(
            jsonEncode({'title': '未刮削'}), flush: true);
        expect(await ScrapeApplyService.isGameScraped(gamePath), isFalse);

        await GameDataPaths.metadataFile(gamePath).writeAsString(
            jsonEncode(ScrapeApplyService.markScraped({'title': '已刮削'})),
            flush: true);
        expect(await ScrapeApplyService.isGameScraped(gamePath), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('isGameScraped 对损坏的 metadata.json 返回 false', () async {
      final tempDir = await Directory.systemTemp.createTemp('hgm_scraped_test');
      try {
        await GameDataPaths.ensureDataDir(tempDir.path);
        await GameDataPaths.metadataFile(tempDir.path)
            .writeAsString('not-json', flush: true);
        expect(await ScrapeApplyService.isGameScraped(tempDir.path), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('buildNumberedUrlMapping', () {
    test('按编号匹配本地图片并生成协议变体', () {
      final mapping = ScrapeApplyService.buildNumberedUrlMapping(
        ['https://img.com/a.jpg', 'https://img.com/b.png'],
        [r'C:\G\A\images\1.jpg', r'C:\G\A\images\2.png'],
      );
      expect(mapping['https://img.com/a.jpg'], r'C:\G\A\images\1.jpg');
      expect(mapping['//img.com/a.jpg'], r'C:\G\A\images\1.jpg');
      expect(mapping['https://img.com/b.png'], r'C:\G\A\images\2.png');
    });

    test('编号不匹配时返回空', () {
      final mapping = ScrapeApplyService.buildNumberedUrlMapping(
        ['https://img.com/a.jpg'],
        [r'C:\G\A\images\9.jpg'],
      );
      expect(mapping, isEmpty);
    });
  });
}
