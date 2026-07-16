import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:hgame_manager/scraper/dlsite_parser.dart';

void main() {
  group('DlsiteParser', () {
    test('should parse dlsite1.html correctly', () async {
      final html = await File('web/dlsite1.html').readAsString();
      final document = html_parser.parse(html);

      final parser = DlsiteParser();
      final gameInfo = parser.parseGameInfo(document, 'https://www.dlsite.com/maniax/work/=/product_id/RJ01169914.html');

      expect(gameInfo, isNotNull);
      expect(gameInfo!.title, isNotEmpty);
      expect(gameInfo.title, contains('SiNiSistar2'));
      expect(gameInfo.description, isNotEmpty);
      expect(gameInfo.screenshots, isNotEmpty);
      expect(gameInfo.tags, isNotEmpty);
      expect(gameInfo.sourceUrl, contains('RJ01169914'));
    });

    test('should parse dlsite2.html correctly', () async {
      final html = await File('web/dlsite2.html').readAsString();
      final document = html_parser.parse(html);

      final parser = DlsiteParser();
      final gameInfo = parser.parseGameInfo(document, 'https://www.dlsite.com/maniax/work/=/product_id/RJ01263980.html');

      expect(gameInfo, isNotNull);
      expect(gameInfo!.title, isNotEmpty);
      expect(gameInfo.title, contains('傲慢的怪兽公主'));
      expect(gameInfo.description, isNotEmpty);
      expect(gameInfo.screenshots, isNotEmpty);
    });

    test('should return null for invalid HTML', () {
      final document = html_parser.parse('<html><body>No game info</body></html>');

      final parser = DlsiteParser();
      final gameInfo = parser.parseGameInfo(document, 'https://www.dlsite.com/maniax/work/=/product_id/RJ99999999.html');

      expect(gameInfo, isNull);
    });

    test('should clean title brackets', () async {
      final html = await File('web/dlsite1.html').readAsString();
      final document = html_parser.parse(html);

      final parser = DlsiteParser();
      final gameInfo = parser.parseGameInfo(document, 'https://www.dlsite.com/maniax/work/=/product_id/RJ01169914.html');

      expect(gameInfo, isNotNull);
      expect(gameInfo!.title, isNot(contains('【')));
      expect(gameInfo.title, isNot(contains('】')));
    });
  });
}
