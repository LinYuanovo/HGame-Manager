import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import '../lib/scraper/site_parsers.dart';
import '../lib/scraper/html_parser.dart';
import '../lib/scraper/parse_utils.dart';

void main() {
  registerAllParsers();

  print('=' * 80);
  print('站点解析器测试报告');
  print('=' * 80);

  testAcgYing();
  testFeiXueAcg();
}

void testAcgYing() {
  print('\n${'=' * 80}');
  print('测试 ACG嘤嘤怪 (acgyyg.ru)');
  print('=' * 80);

  final file = File('web/ACG嘤嘤怪.html');
  if (!file.existsSync()) {
    print('❌ 测试文件不存在: web/ACG嘤嘤怪.html');
    return;
  }

  final html = file.readAsStringSync();
  final document = html_parser.parse(html);
  final parser = AcgYingParser();
  final url = 'https://acgyyg.ru/2026/04/10/test/';

  final gameInfo = parser.parseGameInfo(document, url);

  if (gameInfo == null) {
    print('❌ 解析失败: 返回 null');
    return;
  }

  print('\n✅ 解析成功!');
  print('\n📋 基本信息:');
  print('  标题: ${gameInfo.title ?? "未提取"}');
  print('  版本: ${gameInfo.version ?? "未提取"}');
  print('  分类: ${gameInfo.category ?? "未提取"}');
  print('  发布日期: ${gameInfo.publishDate ?? "未提取"}');

  print('\n🏷️ 标签:');
  if (gameInfo.tags.isEmpty) {
    print('  无标签');
  } else {
    for (final tag in gameInfo.tags) {
      print('  - $tag');
    }
  }

  print('\n📝 描述:');
  if (gameInfo.description != null && gameInfo.description!.isNotEmpty) {
    final preview = gameInfo.description!.length > 200
        ? '${gameInfo.description!.substring(0, 200)}...'
        : gameInfo.description!;
    print('  $preview');
  } else {
    print('  未提取');
  }

  print('\n✨ 特点:');
  if (gameInfo.features.isEmpty) {
    print('  未提取');
  } else {
    for (final f in gameInfo.features) {
      print('  - $f');
    }
  }

  print('\n🔄 更新日志:');
  if (gameInfo.changelog != null && gameInfo.changelog!.isNotEmpty) {
    final preview = gameInfo.changelog!.length > 200
        ? '${gameInfo.changelog!.substring(0, 200)}...'
        : gameInfo.changelog!;
    print('  $preview');
  } else {
    print('  未提取');
  }

  print('\n🖼️ 截图 (${gameInfo.screenshots.length} 张):');
  for (final img in gameInfo.screenshots.take(3)) {
    print('  - $img');
  }
  if (gameInfo.screenshots.length > 3) {
    print('  ... 还有 ${gameInfo.screenshots.length - 3} 张');
  }

  print('\n📥 下载链接 (${gameInfo.downloads.length} 个):');
  for (final dl in gameInfo.downloads) {
    print('  - [${dl.provider ?? "未知"}] ${dl.url}');
    if (dl.password != null) print('    提取码: ${dl.password}');
    if (dl.unzipCode != null) print('    解压码: ${dl.unzipCode}');
  }

  print('\n📊 统计:');
  print('  标签数: ${gameInfo.tags.length}');
  print('  截图数: ${gameInfo.screenshots.length}');
  print('  下载链接数: ${gameInfo.downloads.length}');
  print('  特点数: ${gameInfo.features.length}');
}

void testFeiXueAcg() {
  print('\n${'=' * 80}');
  print('测试 飞雪ACG (feixueacg.org)');
  print('=' * 80);

  final testFiles = [
    {'file': 'web/飞雪ACG.html', 'name': '飞雪ACG'},
    {'file': 'web/fx1.html', 'name': '飞雪ACG - 驱动妖精'},
    {'file': 'web/fx2.html', 'name': '飞雪ACG - 恶意'},
  ];

  for (final testCase in testFiles) {
    print('\n${'-' * 60}');
    print('测试: ${testCase['name']}');
    print('-' * 60);

    final file = File(testCase['file']!);
    if (!file.existsSync()) {
      print('❌ 测试文件不存在: ${testCase['file']}');
      continue;
    }

    final html = file.readAsStringSync();
    final document = html_parser.parse(html);
    final parser = FeiXueAcgParser();
    final url = 'https://feixueacg.org/thread-test-1-1.html';

    final gameInfo = parser.parseGameInfo(document, url);

    if (gameInfo == null) {
      print('❌ 解析失败: 返回 null');
      continue;
    }

    print('\n✅ 解析成功!');
    print('\n📋 基本信息:');
    print('  标题: ${gameInfo.title ?? "未提取"}');
    print('  版本: ${gameInfo.version ?? "未提取"}');
    print('  分类: ${gameInfo.category ?? "未提取"}');

    print('\n🏷️ 标签:');
    if (gameInfo.tags.isEmpty) {
      print('  无标签');
    } else {
      for (final tag in gameInfo.tags) {
        print('  - $tag');
      }
    }

    print('\n🎮 平台:');
    if (gameInfo.platforms.isEmpty) {
      print('  未提取');
    } else {
      for (final p in gameInfo.platforms) {
        print('  - $p');
      }
    }

    print('\n📝 描述:');
    if (gameInfo.description != null && gameInfo.description!.isNotEmpty) {
      final preview = gameInfo.description!.length > 150
          ? '${gameInfo.description!.substring(0, 150)}...'
          : gameInfo.description!;
      print('  $preview');
    } else {
      print('  未提取');
    }

    print('\n🖼️ 截图 (${gameInfo.screenshots.length} 张):');
    for (final img in gameInfo.screenshots.take(3)) {
      print('  - $img');
    }
    if (gameInfo.screenshots.length > 3) {
      print('  ... 还有 ${gameInfo.screenshots.length - 3} 张');
    }

    print('\n📥 下载链接 (${gameInfo.downloads.length} 个):');
    for (final dl in gameInfo.downloads) {
      print('  - [${dl.provider ?? "未知"}] ${dl.url}');
      if (dl.label != null) print('    标签: ${dl.label}');
      if (dl.password != null) print('    提取码: ${dl.password}');
      if (dl.unzipCode != null) print('    解压码: ${dl.unzipCode}');
    }

    print('\n📊 统计:');
    print('  标签数: ${gameInfo.tags.length}');
    print('  截图数: ${gameInfo.screenshots.length}');
    print('  下载链接数: ${gameInfo.downloads.length}');
    print('  平台数: ${gameInfo.platforms.length}');
  }
}
