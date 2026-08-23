import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:hgame_manager/core/utils/dynamic_page_detector.dart';
import 'package:hgame_manager/scraper/html_parser.dart';
import 'package:hgame_manager/scraper/xpath_evaluator.dart';

const _renderedPerfectlifeHtml = '''
<html>
  <body>
    <div id="app">
      <div class="app">
        <main id="main-content">
          <div class="container">
            <div class="post-detail-page">
              <div class="post-layout">
                <article class="post-main">
                  <h1 id="post-title" class="article-title">
                    45号电车v1.0.5.1安卓直装版/45番電車
                  </h1>
                </article>
              </div>
            </div>
          </div>
        </main>
      </div>
    </div>
  </body>
</html>
''';

const _applicationShellHtml = '''
<html>
  <body>
    <div id="app"><div class="app"><main id="main-content"></main></div></div>
  </body>
</html>
''';

void main() {
  group('动态站点 XPath 解析', () {
    test('HTTP 200 前端应用壳会触发浏览器兜底判断', () {
      expect(looksLikeClientRenderedPage(_applicationShellHtml), isTrue);
    });

    test('已包含真实标题的静态 HTML 不会无条件触发浏览器', () {
      expect(looksLikeClientRenderedPage(_renderedPerfectlifeHtml), isFalse);
    });

    test('渲染后的 perfectlife 结构支持绝对路径、属性查询和标题提取', () {
      final document = html_parser.parse(_renderedPerfectlifeHtml);

      expect(
        XPathEvaluator.queryText(
          document,
          '/html/body/div[1]/div/main/div/div/div/article/h1',
        ),
        '45号电车v1.0.5.1安卓直装版/45番電車',
      );
      expect(
        XPathEvaluator.queryText(document, '//*[@id="post-title"]'),
        '45号电车v1.0.5.1安卓直装版/45番電車',
      );
      expect(
        XPathEvaluator.queryText(document, '//h1[@id="post-title"]'),
        '45号电车v1.0.5.1安卓直装版/45番電車',
      );
    });

    test('浏览器返回 HTML 后可继续使用 XpathParser 解析', () {
      final parser = XpathParser('perfectlife.cc', {
        'title': '/html/body/div[1]/div/main/div/div/div/article/h1',
      });
      final info = parser.parseGameInfo(
        html_parser.parse(_renderedPerfectlifeHtml),
        'https://perfectlife.cc/posts/9305',
      );

      expect(info?.title, '45号电车v1.0.5.1安卓直装版/45番電車');
    });

    test('当前 XPath 语法不强行扩展 contains()', () {
      final document = html_parser.parse(_renderedPerfectlifeHtml);
      expect(
        XPathEvaluator.query(
            document, '//h1[contains(@class, "article-title")]'),
        isNull,
      );
    });
  });
}
