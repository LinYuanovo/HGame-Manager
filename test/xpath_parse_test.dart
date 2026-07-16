import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import '../lib/scraper/xpath_evaluator.dart';
import '../lib/scraper/parse_utils.dart';

void main() {
  final output = StringBuffer();
  output.writeln('飞雪ACG XPath 解析测试');
  output.writeln('=' * 80);

  const titleXpath = '/html/body/div[8]/div[4]/div[2]/div[2]/table[1]/tbody/tr/td/h1/a[2]/span';
  const contentXpath = '/html/body/div[8]/div[4]/div[2]/div[2]/div[1]/table/tbody/tr[1]/td/div[2]/div/div[2]/table/tbody/tr/td';

  final files = ['web/fx1.html', 'web/fx2.html', 'web/fx3.html'];

  for (final filePath in files) {
    output.writeln('\n--- $filePath ---');
    final file = File(filePath);
    if (!file.existsSync()) {
      output.writeln('  ⚠ 文件不存在');
      continue;
    }

    final htmlContent = file.readAsStringSync();
    final doc = html_parser.parse(htmlContent);

    final titleEl = XPathEvaluator.query(doc, titleXpath);
    if (titleEl != null) {
      final rawTitle = titleEl.text.trim();
      output.writeln('  标题原始: $rawTitle');
      final tags = extractBracketsFromTitle(rawTitle) ?? [];
      final cleanTitle = rawTitle
          .replaceAll(RegExp(r'【[^】]*】'), '')
          .replaceAll(RegExp(r'\[[^\]]*\]'), '')
          .trim();
      final version = extractVersion(cleanTitle);
      output.writeln('  标题清理: $cleanTitle');
      output.writeln('  版本: ${version ?? "无"}');
      output.writeln('  标签: ${tags.isEmpty ? "无" : tags.join(", ")}');
    } else {
      output.writeln('  标题: 未匹配');
    }

    final contentEl = XPathEvaluator.query(doc, contentXpath);
    if (contentEl != null) {
      final fullText = contentEl.text;
      output.writeln('  内容长度: ${fullText.length} 字符');

      final description = _extractSection(fullText, '概要') ??
          _extractSection(fullText, '游戏介绍') ??
          _extractSection(fullText, '简介');
      final String filteredDesc;
      if (description != null) {
        filteredDesc = filterDescription(description);
      } else {
        filteredDesc = filterDescription(fullText);
        output.writeln('  (无 section 标记，全文作为游戏介绍兜底)');
      }
      if (filteredDesc.isNotEmpty) {
        final preview = filteredDesc.length > 300 ? '${filteredDesc.substring(0, 300)}...' : filteredDesc;
        output.writeln('  游戏介绍:\n    $preview');
      } else {
        output.writeln('  游戏介绍: 无');
      }

      final changelog = _extractSection(fullText, '更新日志') ??
          _extractSection(fullText, '更新内容');
      if (changelog != null) {
        final filtered = filterCommonNoise(changelog);
        output.writeln('  更新日志:\n    ${filtered.substring(0, filtered.length.clamp(0, 200))}');
      } else {
        output.writeln('  更新日志: 无');
      }

      final images = <String>[];
      for (final img in contentEl.querySelectorAll('img')) {
        final src = img.attributes['zoomfile'] ??
            img.attributes['file'] ??
            img.attributes['data-original'] ??
            img.attributes['src'] ??
            '';
        if (src.isNotEmpty &&
            !src.contains('static/image/common') &&
            !src.contains('smiley') &&
            !src.endsWith('.svg') &&
            !src.endsWith('.ico') &&
            !images.contains(src)) {
          images.add(src);
        }
      }
      output.writeln('  自动匹配图片数量: ${images.length}');
      for (var i = 0; i < images.length && i < 5; i++) {
        output.writeln('    [$i] ${images[i]}');
      }
      if (images.length > 5) {
        output.writeln('    ... 还有 ${images.length - 5} 张');
      }

      final signDiv = doc.querySelector('div.sign');
      String? unzipCode;
      if (signDiv != null) {
        unzipCode = extractUnzipCode(signDiv.text);
        output.writeln('  签名区解压码: ${unzipCode ?? "无"}');
      }

      final downloadLinks = extractDownloadLinks(fullText);
      output.writeln('  下载链接数量: ${downloadLinks.length}');
      for (final dl in downloadLinks) {
        output.writeln('    ${dl.provider ?? "?"} | ${dl.url}');
        if (dl.password != null) output.writeln('      提取码: ${dl.password}');
      }

      final showhide = contentEl.querySelector('div.showhide');
      if (showhide != null) {
        var showhideText = showhide.text
            .replaceAll('本帖隱藏的內容', '')
            .replaceAll(RegExp(r'[^\n]*(优惠码|折扣码|优惠卷)[^\n]*'), '')
            .replaceAll(RegExp(r'[^\n]*(VIP|vip|免飞猫)[^\n]*'), '')
            .trim();
        final showhideLinks = extractDownloadLinks(showhideText);
        output.writeln('  showhide 区域下载链接: ${showhideLinks.length}');
        for (final dl in showhideLinks) {
          output.writeln('    ${dl.provider ?? "?"} | ${dl.url}');
          if (dl.password != null) output.writeln('      提取码: ${dl.password}');
        }
      }
    } else {
      output.writeln('  内容: 未匹配');
    }
  }

  output.writeln('\n${'=' * 80}');
  output.writeln('测试完成');

  final resultFile = File('test/xpath_parse_result.txt');
  resultFile.writeAsStringSync(output.toString());
  print(output.toString());
}

String? _extractSection(String fullText, String sectionName) {
  final patterns = ['$sectionName：', '$sectionName:'];
  int? contentStart;
  for (final pattern in patterns) {
    final index = fullText.indexOf(pattern);
    if (index != -1) {
      contentStart = index + pattern.length;
      break;
    }
  }
  if (contentStart == null) return null;
  final nextSectionMatch = RegExp(
    r'(?:^|\n)\s*(游戏介绍[：:]|游戏特点[：:]|更新日志[：:]|更新内容[：:]|链接[：:]|下载链接[：:]|解压码[：:]|解压密码[：:])',
    multiLine: true,
  ).firstMatch(fullText.substring(contentStart));
  final contentEnd = nextSectionMatch != null
      ? contentStart + nextSectionMatch.start
      : fullText.length;
  return fullText.substring(contentStart, contentEnd).trim();
}
