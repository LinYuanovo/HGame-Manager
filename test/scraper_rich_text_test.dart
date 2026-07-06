import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:hgame_manager/scraper/html_parser.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';
import 'package:hgame_manager/scraper/rich_text_extractor.dart';
import 'package:hgame_manager/scraper/site_parsers.dart';

void main() {
  group('非 Steam/DLsite 图文混排刮削', () {
    test('ACG嘤嘤怪真实样本保留简介图文结构', () async {
      final info = await _parseSample(
        'web/acgyyg/yyg.html',
        AcgYingParser(),
        'https://acgyyg.ru/2025/02/21/test/',
      );

      _expectRichDescription(info, containsText: '夏日风情');
      expect(info.descriptionHtml, contains('<img'));
      expect(info.descriptionHtml, contains('Compress_20241103_211921_1965'));
      expect(info.descriptionHtml, isNot(contains('链接')));
      expect(info.descriptionHtml, isNot(contains('提取码')));
    });

    test('飞雪ACG无简介标题样本保留首楼文本与图片', () async {
      final info = await _parseSample(
        'web/feixueacg/thread-81188-1-1.html',
        FeiXueAcgParser(),
        'https://feixueacg.org/thread-81188-1-1.html',
      );

      _expectRichDescription(info, containsText: '偷女友');
      expect(info.descriptionHtml, contains('<img'));
      expect(info.descriptionHtml, contains('RJ01244412.jpg'));
      expect(info.descriptionHtml, isNot(contains('VIP会员')));
    });

    test('飞雪ACG游戏简介样本从简介段开始并保留后续图片', () async {
      final info = await _parseSample(
        'web/feixueacg/thread-91135-1-1.html',
        FeiXueAcgParser(),
        'https://feixueacg.org/thread-91135-1-1.html',
      );

      _expectRichDescription(info, containsText: '二手回收店');
      expect(info.descriptionHtml, contains('<img'));
      expect(info.descriptionHtml, contains('134603all1zsplocul1vjs.png'));
      expect(info.descriptionHtml, isNot(contains('VIP会员')));
    });

    test('维咔真实样本 vik.htm 使用正文 HTML 而非仅 meta 描述', () async {
      final info = await _parseSample(
        'web/vikacg/vik.htm',
        VikAcgParser(),
        'https://www.vikacg.cc/p/330741',
      );

      _expectRichDescription(info, containsText: 'Aerisetta');
      expect(info.descriptionHtml, contains('<img'));
      expect(
          info.descriptionHtml, contains('Screenshot-2025-03-26-055041.webp'));
      expect(info.descriptionHtml, isNot(contains('下载链接')));
      expect(info.descriptionHtml, isNot(contains('解压码')));
    });

    test('维咔真实样本 574486.htm 保留正文图片', () async {
      final info = await _parseSample(
        'web/vikacg/574486.htm',
        VikAcgParser(),
        'https://www.vikacg.cc/p/574486',
      );

      _expectRichDescription(info, containsText: '苍龙社');
      expect(info.descriptionHtml, contains('<img'));
      expect(info.screenshots, contains(contains('4320cb158ace545d2.gif')));
    });

    test('自定义 XPath 描述按 DOM 顺序保留图文混排', () {
      final document = html_parser.parse('''
        <html>
          <body>
            <h1>[SLG/中文] 测试游戏 v1.0</h1>
            <article id="content">
              <p>游戏介绍：</p>
              <p>文本A<img data-src="/a.png">文本B</p>
              <p><img zoomfile="//cdn.example.com/b.jpg">文本C</p>
              <p>下载链接：</p>
              <p>https://pan.baidu.com/s/test 提取码: abcd</p>
            </article>
          </body>
        </html>
      ''');
      final parser = XpathParser('example.com', {
        'title': '//h1',
        'description': '//article[@id="content"]',
      });

      final info = parser.parseGameInfo(document, 'https://example.com/post/1');

      expect(info, isNotNull);
      _expectRichDescription(info!, containsText: '文本A');
      expect(info.description, contains('[图片:https://example.com/a.png]'));
      expect(info.description, contains('[图片:https://cdn.example.com/b.jpg]'));
      expect(
          info.description!.indexOf('文本A'),
          lessThan(
              info.description!.indexOf('[图片:https://example.com/a.png]')));
      expect(info.description!.indexOf('[图片:https://example.com/a.png]'),
          lessThan(info.description!.indexOf('文本B')));
      expect(info.descriptionHtml,
          contains('<img src="https://example.com/a.png">'));
      expect(info.descriptionHtml,
          contains('<img src="https://cdn.example.com/b.jpg">'));
      expect(info.descriptionHtml, isNot(contains('下载链接')));
    });

    test('富文本提取保留游戏介绍前正文并跳过顶部网盘噪音', () {
      final document = html_parser.parse('''
        <html>
          <body>
            <article id="content">
              <p>通过网盘分享的文件：cv4207282</p>
              <p>网页链接(pan.baidu.com)提取码: 8686<br>--来自百度网盘超级会员v2的分享</p>
              <p>前置文本<img src="/before.jpg"></p>
              <p>游戏介绍：</p>
              <p>正文A<br>正文B</p>
              <p>下载链接：</p>
              <p>https://pan.baidu.com/s/test 提取码: abcd</p>
            </article>
          </body>
        </html>
      ''');
      final rich = RichTextExtractor.extractDescription(
        document.querySelector('#content')!,
        'https://example.com/post/1',
      );

      expect(rich.plainText, contains('前置文本'));
      expect(rich.plainText, contains('[图片:https://example.com/before.jpg]'));
      expect(rich.plainText, contains('正文A'));
      expect(rich.plainText.indexOf('前置文本'),
          lessThan(rich.plainText.indexOf('正文A')));
      expect(rich.html, contains('<img src="https://example.com/before.jpg">'));
      expect(rich.html, isNot(contains('通过网盘分享')));
      expect(rich.html, isNot(contains('下载链接')));
      expect(rich.html, isNot(contains('提取码')));
    });
  });
}

Future<GameInfo> _parseSample(
  String filePath,
  SiteParser parser,
  String url,
) async {
  final html = await File(filePath).readAsString();
  final document = html_parser.parse(html);
  final info = parser.parseGameInfo(document, url);
  expect(info, isNotNull, reason: '$filePath 应该能解析出 GameInfo');
  return info!;
}

void _expectRichDescription(
  GameInfo info, {
  required String containsText,
}) {
  expect(info.description, isNotNull);
  expect(info.description, isNotEmpty);
  expect(info.description, contains(containsText));
  expect(info.descriptionHtml, isNotNull);
  expect(info.descriptionHtml, isNotEmpty);
  expect(info.screenshots, isNotEmpty);
  expect(info.screenshots.toSet().length, info.screenshots.length);
}
