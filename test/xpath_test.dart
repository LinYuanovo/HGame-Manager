import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import '../lib/scraper/xpath_evaluator.dart';

void main() {
  final output = StringBuffer();
  output.writeln('XPath 求值器测试');
  output.writeln('=' * 80);

  var passed = 0;
  var failed = 0;

  void check(String name, bool condition) {
    if (condition) {
      output.writeln('  ✓ $name');
      passed++;
    } else {
      output.writeln('  ✗ $name');
      failed++;
    }
  }

  // Test 1: 飞雪ACG HTML
  output.writeln('\n--- 飞雪ACG HTML 测试 ---');
  final fxFile = File('web/飞雪ACG.html');
  if (fxFile.existsSync()) {
    final doc = html_parser.parse(fxFile.readAsStringSync());

    // 绝对路径: 标题
    final titleEl = XPathEvaluator.query(doc, '/html/body//span[@id="thread_subject"]');
    check('绝对路径标题 span#thread_subject', titleEl != null);
    if (titleEl != null) {
      output.writeln('    → ${titleEl.text.trim().substring(0, titleEl.text.trim().length.clamp(0, 50))}');
    }

    // text() 查询
    final titleText = XPathEvaluator.queryText(doc, '//span[@id="thread_subject"]/text()');
    check('text() 查询标题', titleText != null && titleText.isNotEmpty);
    if (titleText != null) {
      output.writeln('    → $titleText');
    }

    // 帖子内容 td.t_f
    final postContent = XPathEvaluator.query(doc, '//td[@class="t_f"]');
    check('帖子内容 td.t_f', postContent != null);
    if (postContent != null) {
      output.writeln('    → 内容长度: ${postContent.text.length} 字符');
    }

    // 签名区域
    final sign = XPathEvaluator.query(doc, '//div[@class="sign"]');
    check('签名区域 div.sign', sign != null);

    // 图片提取（注意：飞雪ACG的图片可能使用 zoomfile/file 属性而非 src）
    final images = XPathEvaluator.queryAllAttributes(doc, '//td[@class="t_f"]//img/@src');
    output.writeln('  ℹ 图片 src 属性: 找到 ${images.length} 张 (此页面图片可能使用 zoomfile/file 属性)');

    // 类型选项表
    final typeTable = XPathEvaluator.query(doc, '//div[@class="typeoption"]//table');
    check('类型选项表', typeTable != null);

    // 标签（注意：此页面的 .ptg 内容由 JS 动态生成，静态 HTML 中可能不存在）
    final tags = XPathEvaluator.queryAll(doc, '//div[@class="ptg"]//a');
    output.writeln('  ℹ 标签链接: 找到 ${tags.length} 个 (部分内容由 JS 动态生成)');
  } else {
    output.writeln('  ⚠ 飞雪ACG.html 不存在，跳过');
  }

  // Test 2: ACG嘤嘤怪 HTML
  output.writeln('\n--- ACG嘤嘤怪 HTML 测试 ---');
  final acgFile = File('web/ACG嘤嘤怪.html');
  if (acgFile.existsSync()) {
    final doc = html_parser.parse(acgFile.readAsStringSync());

    final titleEl = XPathEvaluator.query(doc, '//h3[@class="post-title"]');
    check('标题 h3.post-title', titleEl != null);
    if (titleEl != null) {
      output.writeln('    → ${titleEl.text.trim().substring(0, titleEl.text.trim().length.clamp(0, 50))}');
    }

    final content = XPathEvaluator.query(doc, '//div[@class="post-content"]');
    check('帖子内容 div.post-content', content != null);
    if (content != null) {
      output.writeln('    → 内容长度: ${content.text.length} 字符');
    }

    // 图片
    final images = XPathEvaluator.queryAllAttributes(doc, '//div[@class="post-content"]//img/@src');
    check('图片 src 属性', images.isNotEmpty);
    output.writeln('    → 找到 ${images.length} 张图片');
  } else {
    output.writeln('  ⚠ ACG嘤嘤怪.html 不存在，跳过');
  }

  // Test 3: 微咔ACG HTML
  output.writeln('\n--- 微咔ACG HTML 测试 ---');
  final vikFile = File('web/微咔ACG.htm');
  if (vikFile.existsSync()) {
    final doc = html_parser.parse(vikFile.readAsStringSync());

    final ogTitle = XPathEvaluator.queryAttribute(doc, '//meta[@property="og:title"]/@content');
    check('og:title 属性', ogTitle != null && ogTitle.isNotEmpty);
    if (ogTitle != null) {
      output.writeln('    → $ogTitle');
    }

    final ogDesc = XPathEvaluator.queryAttribute(doc, '//meta[@property="og:description"]/@content');
    check('og:description 属性', ogDesc != null);
  } else {
    output.writeln('  ⚠ 微咔ACG.htm 不存在，跳过');
  }

  // Test 4: XPath 解析器语法测试
  output.writeln('\n--- XPath 语法解析测试 ---');
  final testHtml = '<html><body><div id="main"><p class="intro">Hello</p><p class="content">World</p></div></body></html>';
  final testDoc = html_parser.parse(testHtml);

  check('基本标签查询 html', XPathEvaluator.query(testDoc, '/html') != null);
  check('绝对路径 /html/body', XPathEvaluator.query(testDoc, '/html/body') != null);
  check('属性匹配 div[@id="main"]', XPathEvaluator.query(testDoc, '//div[@id="main"]') != null);
  check('索引 p[1]', XPathEvaluator.query(testDoc, '//p[1]') != null);
  check('text() 查询', XPathEvaluator.queryText(testDoc, '//p[@class="intro"]/text()') == 'Hello');
  check('所有 p 标签', XPathEvaluator.queryAll(testDoc, '//p').length == 2);
  check('不存在的元素返回 null', XPathEvaluator.query(testDoc, '//span[@id="none"]') == null);
  check('空 xpath 返回空', XPathEvaluator.queryAll(testDoc, '').isEmpty);

  // Summary
  output.writeln('\n${'=' * 80}');
  output.writeln('测试结果: $passed 通过, $failed 失败');

  final resultFile = File('test/xpath_test_result.txt');
  resultFile.writeAsStringSync(output.toString());
  print(output.toString());
}
