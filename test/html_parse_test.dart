import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import '../lib/scraper/parse_utils.dart';

void main() {
  print('=' * 80);
  print('使用 web 文件夹下的 HTML 进行解析测试');
  print('=' * 80);

  testAcgYing();
  testFeiXue1();
  testFeiXue2();
}

void testAcgYing() {
  print('\n${'=' * 80}');
  print('测试文件: web/ACG嘤嘤怪.html');
  print('=' * 80);

  final file = File('web/ACG嘤嘤怪.html');
  if (!file.existsSync()) {
    print('❌ 文件不存在');
    return;
  }

  final html = file.readAsStringSync();
  final doc = html_parser.parse(html);

  // 提取标题
  final titleEl = doc.querySelector('h3.post-title');
  final rawTitle = titleEl?.text.trim();
  print('\n📋 原始标题: $rawTitle');

  if (rawTitle != null) {
    // 提取标签
    final tags = extractBracketsFromTitle(rawTitle);
    print('🏷️ 标签: $tags');

    // 清理标题
    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();
    print('📝 清理后标题: $cleanTitle');

    // 提取版本
    final version = extractVersion(cleanTitle);
    print('📌 版本: $version');
  }

  // 提取发布日期
  final postMeta = doc.querySelector('div.post-meta');
  if (postMeta != null) {
    final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(postMeta.text);
    print('📅 发布日期: ${dateMatch?.group(1) ?? "未提取"}');
  }

  // 提取内容
  final postContent = doc.querySelector('div.post-content');
  if (postContent != null) {
    final fullText = postContent.text;

    // 提取各部分
    final sections = splitSections(fullText);
    print('\n📂 内容分区:');
    for (final entry in sections.entries) {
      final preview = entry.value.length > 100
          ? '${entry.value.substring(0, 100)}...'
          : entry.value;
      print('  【${entry.key}】: $preview');
    }

    // 提取下载链接
    final linksSection = sections['链接'];
    if (linksSection != null) {
      final downloads = extractDownloadLinks(linksSection);
      print('\n📥 下载链接 (${downloads.length} 个):');
      for (final dl in downloads) {
        print('  - [${dl.provider ?? "未知"}] ${dl.url}');
        if (dl.password != null) print('    提取码: ${dl.password}');
      }
    }

    // 提取解压码
    final unzipCode = extractUnzipCode(fullText);
    print('\n🔓 解压码: ${unzipCode ?? "未提取"}');

    // 提取截图
    final images = postContent.querySelectorAll('img');
    final screenshots = images
        .map((img) => img.attributes['src'] ?? '')
        .where((src) => src.isNotEmpty && src.contains('wp-content/uploads'))
        .toList();
    print('\n🖼️ 截图 (${screenshots.length} 张):');
    for (final img in screenshots.take(3)) {
      print('  - $img');
    }
  }
}

void testFeiXue1() {
  print('\n${'=' * 80}');
  print('测试文件: web/飞雪ACG.html');
  print('=' * 80);

  final file = File('web/飞雪ACG.html');
  if (!file.existsSync()) {
    print('❌ 文件不存在');
    return;
  }

  final html = file.readAsStringSync();
  final doc = html_parser.parse(html);

  // 提取标题
  final titleEl = doc.querySelector('span#thread_subject');
  final rawTitle = titleEl?.text.trim();
  print('\n📋 原始标题: $rawTitle');

  if (rawTitle != null) {
    final tags = extractBracketsFromTitle(rawTitle);
    print('🏷️ 标签: $tags');

    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();
    print('📝 清理后标题: $cleanTitle');

    final version = extractVersion(cleanTitle);
    print('📌 版本: $version');
  }

  // 提取分类信息
  final typeOption = doc.querySelector('div.typeoption table');
  if (typeOption != null) {
    print('\n📊 分类信息:');
    for (final row in typeOption.querySelectorAll('tr')) {
      final th = row.querySelector('th');
      final td = row.querySelector('td');
      if (th != null && td != null) {
        print('  ${th.text.trim()}: ${td.text.trim()}');
      }
    }
  }

  // 提取下载链接
  final showhideDiv = doc.querySelector('div.showhide');
  if (showhideDiv != null) {
    var showhideText = showhideDiv.text;
    showhideText = showhideText.replaceAll('本帖隱藏的內容', '').trim();
    final downloads = extractDownloadLinks(showhideText);
    print('\n📥 下载链接 (${downloads.length} 个):');
    for (final dl in downloads) {
      print('  - [${dl.provider ?? "未知"}] ${dl.url}');
      if (dl.label != null) print('    标签: ${dl.label}');
    }
  }

  // 提取解压码
  final signDiv = doc.querySelector('div.sign');
  if (signDiv != null) {
    final unzipCode = extractUnzipCode(signDiv.text);
    print('\n🔓 解压码: ${unzipCode ?? "未提取"}');
  }

  // 提取描述
  final metaDesc = doc.querySelector('meta[name="description"]');
  if (metaDesc != null) {
    final desc = metaDesc.attributes['content'] ?? '';
    print('\n📝 描述: ${desc.length > 150 ? desc.substring(0, 150) : desc}...');
  }
}

void testFeiXue2() {
  print('\n${'=' * 80}');
  print('测试文件: web/fx1.html');
  print('=' * 80);

  final file = File('web/fx1.html');
  if (!file.existsSync()) {
    print('❌ 文件不存在');
    return;
  }

  final html = file.readAsStringSync();
  final doc = html_parser.parse(html);

  // 提取标题
  final titleEl = doc.querySelector('span#thread_subject');
  final rawTitle = titleEl?.text.trim();
  print('\n📋 原始标题: $rawTitle');

  if (rawTitle != null) {
    final tags = extractBracketsFromTitle(rawTitle);
    print('🏷️ 标签: $tags');

    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();
    print('📝 清理后标题: $cleanTitle');

    final version = extractVersion(cleanTitle);
    print('📌 版本: $version');
  }

  // 提取分类信息
  final typeOption = doc.querySelector('div.typeoption table');
  if (typeOption != null) {
    print('\n📊 分类信息:');
    for (final row in typeOption.querySelectorAll('tr')) {
      final th = row.querySelector('th');
      final td = row.querySelector('td');
      if (th != null && td != null) {
        print('  ${th.text.trim()}: ${td.text.trim()}');
      }
    }
  }

  // 提取下载链接
  final showhideDiv = doc.querySelector('div.showhide');
  if (showhideDiv != null) {
    var showhideText = showhideDiv.text;
    showhideText = showhideText.replaceAll('本帖隱藏的內容', '').trim();
    final downloads = extractDownloadLinks(showhideText);
    print('\n📥 下载链接 (${downloads.length} 个):');
    for (final dl in downloads) {
      print('  - [${dl.provider ?? "未知"}] ${dl.url}');
      if (dl.label != null) print('    标签: ${dl.label}');
    }
  }

  // 提取解压码
  final signDiv = doc.querySelector('div.sign');
  if (signDiv != null) {
    final unzipCode = extractUnzipCode(signDiv.text);
    print('\n🔓 解压码: ${unzipCode ?? "未提取"}');
  }
}

Map<String, String> splitSections(String fullText) {
  final markers = ['游戏介绍：', '游戏特点：', '更新内容：', '链接：'];
  final result = <String, String>{};

  final positions = <_MarkerPos>[];
  for (final marker in markers) {
    var searchFrom = 0;
    while (true) {
      final index = fullText.indexOf(marker, searchFrom);
      if (index == -1) break;
      positions.add(_MarkerPos(marker, index));
      searchFrom = index + marker.length;
    }
  }
  positions.sort((a, b) => a.pos.compareTo(b.pos));

  for (var i = 0; i < positions.length; i++) {
    final contentStart = positions[i].pos + positions[i].marker.length;
    final contentEnd = i + 1 < positions.length
        ? positions[i + 1].pos
        : fullText.length;
    final content = fullText.substring(contentStart, contentEnd).trim();
    if (content.isNotEmpty) {
      final name = positions[i].marker.replaceAll('：', '');
      result[name] = content;
    }
  }

  if (!result.containsKey('游戏介绍')) {
    if (positions.isEmpty) {
      final trimmed = fullText.trim();
      if (trimmed.isNotEmpty) {
        result['游戏介绍'] = trimmed;
      }
    } else {
      final introText = fullText.substring(0, positions.first.pos).trim();
      if (introText.isNotEmpty) {
        result['游戏介绍'] = introText;
      }
    }
  }

  return result;
}

class _MarkerPos {
  final String marker;
  final int pos;
  _MarkerPos(this.marker, this.pos);
}
