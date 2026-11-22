import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:hgame_manager/core/utils/scraped_image_reference_rewriter.dart';
import 'package:hgame_manager/scraper/dlsite_parser.dart';
import 'package:hgame_manager/scraper/html_parser.dart';

const _url = 'https://www.dlsite.com/maniax/work/=/product_id/RJ01169914.html';

String _structuredData(Object data) =>
    '<script type="application/ld+json">${jsonEncode(data)}</script>';

Map<String, Object> _product({String id = 'RJ01169914'}) => {
      '@type': 'Product',
      'sku': id,
      'name': '备用标题',
      'description': '结构化短简介',
      'brand': {
        '@type': 'Brand',
        'name': '备用社团',
        'url': '/maniax/circle/fallback'
      },
      'image': [
        '//img.dlsite.jp/cover.jpg',
        for (var index = 1; index <= 5; index++)
          '//img.dlsite.jp/sample$index.jpg',
      ],
    };

const _legacyPage = '''
<h1 id="work_name">【简体中文】测试游戏 [动作]</h1>
<meta property="og:image" content="//img.dlsite.jp/cover-small.jpg">
<div class="product-slider-data">
  <div data-src="//img.dlsite.jp/cover.jpg"></div>
  <div data-src="//img.dlsite.jp/sample.jpg"></div>
</div>
<div class="maker_name"><a href="/maniax/circle/test">测试社团</a></div>
<div class="main_genre"><a>动作</a></div>
<div itemprop="description">
  <div class="work_parts"><h3>游戏简介</h3>
    <p>探索关卡<br>解开谜题</p>
    <img data-original="//img.dlsite.jp/detail.jpg" src="placeholder.jpg">
  </div>
</div>
''';

// 2026-11-14 三个真实作品的服务端 HTML 使用以下新版容器。
const _currentPage = '''
<h1 id="work_name">【简体中文】测试游戏 [动作]</h1>
<meta property="og:image" content="//img.dlsite.jp/cover-small.jpg">
<div id="work_visual">
  <div class="slider_body">
    <div class="keen-slider__slide"><img src="//img.dlsite.jp/cover.jpg"></div>
    <div class="keen-slider__slide"><img src="//img.dlsite.jp/sample.jpg"></div>
  </div>
  <ul class="key-visual-slider-controller__items">
    <li><img src="//img.dlsite.jp/cover_100x100.jpg"></li>
    <li><img src="//img.dlsite.jp/sample_100x100.jpg"></li>
  </ul>
</div>
<div class="c-productInfo__item c-productInfo__item--maker">
  <a class="c-productInfo__makerName" href="/maniax/circle/test">测试社团</a>
</div>
<div class="c-productInfo__item">
  <a class="tag_game">动作</a><a class="tag_general">简体中文</a>
</div>
<div class="c-productInfo__inner">
  <div><div>
    <div class="c-productContent"><h3>游戏简介</h3>
      <div class="c-productContent__text">探索关卡<br>解开谜题</div>
    </div>
    <div class="c-productContent"><h3>操作说明</h3>
      <div class="c-productContent__image">
        <div class="c-productContent__file"><a href="//img.dlsite.jp/detail.jpg">
          <img src="//img.dlsite.jp/detail.jpg">
        </a></div>
        <div class="c-productContent__text">方向键移动</div>
      </div>
    </div>
  </div></div>
</div>
<aside><img src="//img.dlsite.jp/recommendation.jpg">推荐作品</aside>
''';

void main() {
  group('DLsite 解析', () {
    test('限定页不把宣传摘要和占位图当成完整刮削结果', () {
      final product = _product()
        ..['image'] = [
          'https://www.dlsite.com/images/web/home/no_img_main.gif',
          'https://www.dlsite.com/images/web/home/no_img.gif',
        ];
      final info = DlsiteParser().parseGameInfo(html_parser.parse('''
        <h1 id="work_name">测试作品</h1>
        <section class="p-restricted"><div class="error_message">访问受限</div></section>
        <meta property="og:image" content="https://www.dlsite.com/modpub/images/web/home/summary_large_image_ja_jp.png">
        <div class="c-productContent">非作品正文</div>
        ${_structuredData(product)}
      '''), _url)!;

      expect(info.isDlsiteUserOnly, isTrue);
      expect(info.description, isNull);
      expect(info.descriptionHtml, isNull);
      expect(info.screenshots, isEmpty);
    });

    test('精确限定提示可补识别，普通页面中的脚本标记不误判', () {
      const notice = '\u3053\u306e\u4f5c\u54c1\u306fDLsite'
          '\u30e6\u30fc\u30b6\u30fc\u9650\u5b9a'
          '\u30b3\u30f3\u30c6\u30f3\u30c4\u3067\u3059\u3002';
      final restricted = DlsiteParser().parseGameInfo(
          html_parser.parse('<h1 id="work_name">测试作品</h1>'
              '<div class="error_message">$notice</div>'),
          _url)!;
      expect(restricted.isDlsiteUserOnly, isTrue);

      final normal = DlsiteParser().parseGameInfo(
          html_parser
              .parse('$_currentPage<script>var user_only = true;</script>'
                  '<script>const notice = "$notice";</script>'
                  '<p>说明用户限定功能</p>'),
          _url)!;
      expect(normal.isDlsiteUserOnly, isFalse);
      expect(normal.description, contains('方向键移动'));
    });

    test('所有图片来源排除站点占位图并从简介 HTML 删除占位节点', () {
      final product = _product()
        ..['image'] = [
          'https://www.dlsite.com/images/web/home/no_img_main.gif',
          '//img.dlsite.jp/additional.jpg',
        ];
      final info = DlsiteParser().parseGameInfo(html_parser.parse('''
        <h1 id="work_name">测试作品</h1>
        <div class="work_slider">
          <img src="https://www.dlsite.com/images/web/home/no_img.gif">
          <img src="//img.dlsite.jp/cover.jpg">
        </div>
        <div itemprop="description"><p>完整正文</p>
          <img src="https://www.dlsite.com/images/web/home/no_img_main.gif?size=1">
          <img data-src="//img.dlsite.jp/detail.jpg">
        </div>
        ${_structuredData(product)}
      '''), _url)!;
      expect(info.isDlsiteUserOnly, isFalse);
      expect(info.screenshots, [
        'https://img.dlsite.jp/cover.jpg',
        'https://img.dlsite.jp/additional.jpg',
        'https://img.dlsite.jp/detail.jpg',
      ]);
      expect(info.description, isNot(contains('no_img')));
      expect(info.descriptionHtml, isNot(contains('no_img')));
      expect(info.description, contains('完整正文'));
    });

    test('旧版保留简介、原图、厂商和标题标签', () {
      final info =
          DlsiteParser().parseGameInfo(html_parser.parse(_legacyPage), _url)!;

      expect(info.title, '测试游戏');
      expect(info.description, contains('探索关卡\n解开谜题'));
      expect(info.descriptionHtml, contains('work_parts'));
      expect(info.screenshots, [
        'https://img.dlsite.jp/cover.jpg',
        'https://img.dlsite.jp/sample.jpg',
        'https://img.dlsite.jp/detail.jpg',
      ]);
      expect(info.maker, '测试社团');
      expect(info.makerUrl, 'https://www.dlsite.com/maniax/circle/test');
      expect(info.tags, containsAll(['简体中文', '动作', '测试社团']));
      expect(info.sourceUrl, _url);
    });

    test('新版提取全部简介区块和原图并排除控制栏缩略图', () {
      final info =
          DlsiteParser().parseGameInfo(html_parser.parse(_currentPage), _url)!;

      expect(info.description, contains('探索关卡\n解开谜题'));
      expect(info.description, contains('操作说明'));
      expect(info.description, contains('方向键移动'));
      expect(
          info.description, contains('[图片:https://img.dlsite.jp/detail.jpg]'));
      expect(info.description, isNot(contains('推荐作品')));
      expect(info.descriptionHtml, contains('c-productContent__image'));
      expect(info.screenshots, [
        'https://img.dlsite.jp/cover.jpg',
        'https://img.dlsite.jp/sample.jpg',
        'https://img.dlsite.jp/detail.jpg',
      ]);
      expect(info.maker, '测试社团');
      expect(info.tags, containsAll(['简体中文', '动作', '测试社团']));
    });

    test('新版简介中的图片可在下载后统一替换为本地引用', () {
      final info =
          DlsiteParser().parseGameInfo(html_parser.parse(_currentPage), _url)!;
      const mapping = {
        'https://img.dlsite.jp/detail.jpg': 'HGMDatas/images/1.jpg'
      };

      final localized = ScrapedImageReferenceRewriter.replaceHtmlImages(
          info.descriptionHtml!, mapping);
      expect(localized, contains('src="HGMDatas/images/1.jpg"'));
      expect(localized, isNot(contains('//img.dlsite.jp/detail.jpg')));
    });

    test('空的旧简介容器回退到新版正文', () {
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse('<div itemprop="description"></div>$_currentPage'),
          _url)!;

      expect(info.description, contains('方向键移动'));
      expect(info.screenshots, hasLength(3));
    });

    test('图片在画廊和正文中重复时只下载一次', () {
      final info = DlsiteParser().parseGameInfo(
          html_parser
              .parse(_currentPage.replaceAll('detail.jpg', 'sample.jpg')),
          _url)!;

      expect(info.screenshots, hasLength(2));
      expect(
          info.description, contains('[图片:https://img.dlsite.jp/sample.jpg]'));
    });

    test('画廊视频不作为图片下载', () {
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse(_legacyPage.replaceFirst(
              '<div class="product-slider-data">',
              '<div class="product-slider-data">'
                  '<div data-src="//img.dlsite.jp/trailer.mp4"></div>')),
          _url)!;

      expect(info.screenshots.first, 'https://img.dlsite.jp/cover.jpg');
      expect(info.screenshots, hasLength(3));
    });

    test('画廊缺失时保留 OG 封面', () {
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse('<h1 id="work_name">测试游戏</h1>'
              '<meta property="og:image" content="//img.dlsite.jp/cover.jpg">'),
          _url)!;

      expect(info.screenshots, ['https://img.dlsite.jp/cover.jpg']);
      expect(info.description, isNull);
    });

    test('同一解析器连续解析不会混入前一次正文图片', () {
      final parser = DlsiteParser();
      parser.parseGameInfo(html_parser.parse(_currentPage), _url);
      final info = parser.parseGameInfo(
          html_parser.parse('<h1 id="work_name">另一个游戏</h1>'), _url)!;

      expect(info.screenshots, isEmpty);
      expect(info.description, isNull);
    });

    test('仅有 OG 缩略封面时仍保留最后可用图片', () {
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse('<h1 id="work_name">测试游戏</h1>'
              '<meta property="og:image" '
              'content="//img.dlsite.jp/resize/cover_240x240.jpg">'),
          _url)!;

      expect(
          info.screenshots, ['https://img.dlsite.jp/resize/cover_240x240.jpg']);
    });

    test('URL 刮削和导入使用同一内置解析器', () {
      final info = HtmlScraper().scrapeGameInfo(_currentPage, _url)!;

      expect(info.description, contains('方向键移动'));
      expect(info.screenshots, hasLength(3));
    });

    test('没有作品标题时返回空结果', () {
      expect(
          DlsiteParser().parseGameInfo(
              html_parser.parse('<html><body>无作品信息</body></html>'), _url),
          isNull);
    });

    test('work_slider 支持懒加载和 src 原图，排除 resize 缩略图和视频', () {
      final info = DlsiteParser().parseGameInfo(html_parser.parse('''
        <h1 id="work_name">测试游戏</h1>
        <div class="work_slider">
          <img data-src="//img.dlsite.jp/resize/cover_100x100.jpg">
          <img data-src="//img.dlsite.jp/cover.jpg" src="placeholder.jpg">
          <img src="//img.dlsite.jp/sample.jpg">
          <img data-src="//img.dlsite.jp/trailer.mp4?download=1">
        </div>
        <dl><dd class="c-productInfo__value">
          <a class="tag_game">动作</a><a class="tag_general">探索</a>
        </dd></dl>
        <aside><a class="tag_general">推荐标签</a></aside>
      '''), _url)!;

      expect(info.screenshots, [
        'https://img.dlsite.jp/cover.jpg',
        'https://img.dlsite.jp/sample.jpg'
      ]);
      expect(info.tags, containsAll(['动作', '探索']));
      expect(info.tags, isNot(contains('推荐标签')));
    });

    test('正文和画廊缺失时采用当前 Product 短简介和六张原图', () {
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse(
            '<h1 id="work_name">页面标题</h1>'
            '<meta property="og:image" content="//img.dlsite.jp/small.jpg">'
            '${_structuredData(_product())}',
          ),
          _url)!;

      expect(info.title, '页面标题');
      expect(info.description, '结构化短简介');
      expect(info.descriptionHtml, contains('结构化短简介'));
      expect(info.screenshots, hasLength(6));
      expect(info.screenshots.first, 'https://img.dlsite.jp/cover.jpg');
      expect(
          info.screenshots, isNot(contains('https://img.dlsite.jp/small.jpg')));
      expect(info.maker, '备用社团');
      expect(info.makerUrl, 'https://www.dlsite.com/maniax/circle/fallback');
    });

    test('完整正文和社团优先，结构化原图只补漏并去重', () {
      final product = _product()
        ..['image'] = [
          '//img.dlsite.jp/cover.jpg',
          '//img.dlsite.jp/sample.jpg',
          '//img.dlsite.jp/additional.jpg',
        ];
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse('$_currentPage${_structuredData(product)}'), _url)!;

      expect(info.description, contains('方向键移动'));
      expect(info.description, isNot(contains('结构化短简介')));
      expect(info.maker, '测试社团');
      expect(info.screenshots, [
        'https://img.dlsite.jp/cover.jpg',
        'https://img.dlsite.jp/sample.jpg',
        'https://img.dlsite.jp/additional.jpg',
        'https://img.dlsite.jp/detail.jpg'
      ]);
    });

    test('标题缺失也可从匹配 Product 恢复', () {
      final info = DlsiteParser()
          .parseGameInfo(html_parser.parse(_structuredData(_product())), _url)!;
      expect(info.title, '备用标题');
      expect(info.screenshots, hasLength(6));
    });

    test('数组和 graph 中按作品 ID 选择 Product，不混入推荐作品', () {
      final current = _product()..remove('sku');
      current['@type'] = ['CreativeWork', 'Product'];
      current['offers'] = {'url': _url};
      current['image'] = [
        {'@type': 'ImageObject', 'contentUrl': '//img.dlsite.jp/cover.jpg'},
        {'@type': 'ImageObject', 'url': '/sample.jpg'},
      ];
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse(_structuredData([
            {'@type': 'WebSite', 'name': '站点名称'},
            {
              '@graph': [_product(id: 'RJ99999999'), current]
            },
          ])),
          _url)!;

      expect(info.title, '备用标题');
      expect(info.screenshots, [
        'https://img.dlsite.jp/cover.jpg',
        'https://www.dlsite.com/sample.jpg'
      ]);
    });

    test('唯一 Product 明确属于其他作品时不采用', () {
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse(
            '<h1 id="work_name">页面标题</h1>${_structuredData(_product(id: 'RJ99999999'))}',
          ),
          _url)!;
      expect(info.description, isNull);
      expect(info.maker, isNull);
      expect(info.screenshots, isEmpty);
    });

    test('多条无 ID Product 仅接受与页面标题对应的一条', () {
      final wrong = _product()..remove('sku');
      final current = _product()..remove('sku');
      current['name'] = '页面标题';
      current['description'] = '标题匹配的简介';
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse(
            '<h1 id="work_name">页面标题</h1>${_structuredData([wrong, current])}',
          ),
          _url)!;
      expect(info.description, '标题匹配的简介');
      final ambiguous = DlsiteParser().parseGameInfo(
          html_parser.parse(
            '<h1 id="work_name">其他标题</h1>${_structuredData([wrong, current])}',
          ),
          _url)!;
      expect(ambiguous.description, isNull);
      expect(ambiguous.screenshots, isEmpty);
    });

    test('只有正文图片时补短简介，同时保留内嵌图与本地化能力', () {
      final info = DlsiteParser().parseGameInfo(html_parser.parse('''
        <h1 id="work_name">测试游戏</h1>
        <section class="c-productContent"><h3>作品内容</h3><div class="c-productContent__image">
          <img src="//img.dlsite.jp/detail.jpg">
        </div></section>${_structuredData(_product())}
      '''), _url)!;

      expect(info.description, contains('结构化短简介'));
      expect(info.description, contains('作品内容'));
      expect(
          info.description, contains('[图片:https://img.dlsite.jp/detail.jpg]'));
      expect(info.descriptionHtml, contains('c-productContent__image'));
      expect(info.screenshots, hasLength(7));
    });

    test('损坏或无关 JSON-LD 不影响页面，也不会阻止后一条 Product', () {
      const broken = '<script type="application/ld+json">{not-json</script>';
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse(
            '$broken${_structuredData(12)}${_structuredData(_product())}',
          ),
          _url)!;
      expect(info.description, '结构化短简介');
      final dom = DlsiteParser()
          .parseGameInfo(html_parser.parse('$_currentPage$broken'), _url)!;
      expect(dom.description, contains('方向键移动'));
    });

    test('结构化图片拒绝非 HTTP 地址、缩略图及视频，空字段回退 OG', () {
      final product = _product()
        ..['image'] = [
          'data:image/png;base64,aaaa',
          'javascript:alert(1)',
          '//img.dlsite.jp/resize/cover.jpg',
          '//img.dlsite.jp/trailer.webm',
          '',
          null,
          {'url': '//img.dlsite.jp/icon.svg'},
        ];
      product['description'] = '   ';
      final info = DlsiteParser().parseGameInfo(
          html_parser.parse(
              '<meta property="og:image" content="//img.dlsite.jp/og.jpg">'
              '${_structuredData(product)}'),
          _url)!;
      expect(info.description, isNull);
      expect(info.screenshots, ['https://img.dlsite.jp/og.jpg']);
    });

    test('结构化摘要作为文字转义写入 HTML', () {
      final product = _product()..['description'] = '探索 <森林> & 解谜';
      final info = DlsiteParser()
          .parseGameInfo(html_parser.parse(_structuredData(product)), _url)!;
      expect(info.description, '探索 <森林> & 解谜');
      expect(info.descriptionHtml, contains('&lt;森林&gt; &amp;'));
      expect(
          html_parser.parse(info.descriptionHtml).querySelector('森林'), isNull);
    });
  });
}
