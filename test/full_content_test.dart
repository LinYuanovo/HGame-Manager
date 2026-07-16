import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../lib/scraper/parse_utils.dart';

void main() async {
  final url = 'https://feixueacg.org/thread-83410-1-1.html';
  const cookie = 'X_CACHE_KEY=6f79c552ad8d31a3aa82d8cf65dbc65a; acFt_cookie=acFt_1; bPvg_2132_saltkey=Ahf4KI88; bPvg_2132_lastvisit=1779681602; bPvg_2132_atarget=1; bPvg_2132_auth=a85dzUrgzFuY48W00Sd%2B2cfbauK4mjFB1V2ghaai3sXX8CnPtV0RoT%2BZs0s%2Fp2OHxB55i%2BAc5CArcACMgQ5jOsndO9Q; bPvg_2132_lastcheckfeed=183720%7C1779685277; bPvg_2132_nofavfid=1; bPvg_2132_smile=1D1; bPvg_2132_visitedfid=43D64; server_name_session=f0a8796083e63e25a066bfaadd47d480; bPvg_2132_seccodecSAA9N0=23913.59e10036f2c92fc895; bPvg_2132_seccodecSAdUX0=24235.81a119aeb35f34d890; bPvg_2132_st_t=183720%7C1779795460%7C2dcd3e24bc61f389201ea63e3dcfe2f4; bPvg_2132_forum_lastvisit=D_64_1779692273D_43_1779795460; bPvg_2132_ulastactivity=1779798762%7C0; bPvg_2132_st_p=183720%7C1779798807%7Cd8e39f4136c9509f8f88b67e36d1a9a1; bPvg_2132_viewid=tid_88994; bPvg_2132_seccodecS0=35372.6d18bf92ab1d258093; bPvg_2132_lastact=1779798809%09plugin.php%09';

  final output = StringBuffer();
  output.writeln('URL解析完整内容输出');
  output.writeln('=' * 80);
  output.writeln('测试URL: $url');
  output.writeln('=' * 80);

  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Cookie': cookie,
      },
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      output.writeln('请求失败: ${response.statusCode}');
      File('test/full_content_output.txt').writeAsStringSync(output.toString());
      return;
    }

    final doc = html_parser.parse(response.body);

    // 标题
    final titleEl = doc.querySelector('span#thread_subject');
    final rawTitle = titleEl?.text.trim();
    output.writeln('\n【原始标题】');
    output.writeln(rawTitle ?? '未提取');

    // 标签和版本
    if (rawTitle != null) {
      final tags = extractBracketsFromTitle(rawTitle);
      output.writeln('\n【标签】');
      output.writeln(tags?.join(', ') ?? '未提取');

      final cleanTitle = rawTitle
          .replaceAll(RegExp(r'【[^】]*】'), '')
          .replaceAll(RegExp(r'\[[^\]]*\]'), '')
          .trim();
      output.writeln('\n【清理后标题】');
      output.writeln(cleanTitle);

      final version = extractVersion(cleanTitle);
      output.writeln('\n【版本】');
      output.writeln(version ?? '未提取');
    }

    // 分类信息
    final typeOption = doc.querySelector('div.typeoption table');
    if (typeOption != null) {
      output.writeln('\n【分类信息】');
      for (final row in typeOption.querySelectorAll('tr')) {
        final th = row.querySelector('th');
        final td = row.querySelector('td');
        if (th != null && td != null) {
          output.writeln('  ${th.text.trim()}: ${td.text.trim()}');
        }
      }
    }

    // 帖子内容
    final postContent = doc.querySelector('td.t_f');
    if (postContent != null) {
      // 移除提示div
      for (final tipDiv in postContent.querySelectorAll('div.tip, div.tip_4, div.aimg_tip')) {
        tipDiv.remove();
      }
      for (final script in postContent.querySelectorAll('script')) {
        script.remove();
      }

      // 1. 原始内容（过滤前）
      output.writeln('\n' + '=' * 80);
      output.writeln('【原始内容 - 过滤前】');
      output.writeln('=' * 80);
      output.writeln(postContent.text.trim());

      // 2. showhide内容
      final showhideDiv = postContent.querySelector('div.showhide');
      if (showhideDiv != null) {
        output.writeln('\n' + '=' * 80);
        output.writeln('【showhide原始内容】');
        output.writeln('=' * 80);
        output.writeln(showhideDiv.text.trim());

        // 过滤后的内容
        var showhideText = showhideDiv.text;
        showhideText = showhideText.replaceAll('本帖隱藏的內容', '').trim();
        final lines = showhideText.split('\n').where((l) => l.trim().isNotEmpty).toList();
        final filteredLines = <String>[];
        final removedLines = <String>[];
        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.contains('优惠码')) {
            removedLines.add('[过滤: 优惠码] $trimmedLine');
            continue;
          }
          if (trimmedLine.contains('VIP') || trimmedLine.contains('免飞猫')) {
            removedLines.add('[过滤: VIP/免飞猫] $trimmedLine');
            continue;
          }
          filteredLines.add(trimmedLine);
        }

        output.writeln('\n' + '=' * 80);
        output.writeln('【showhide过滤后内容】');
        output.writeln('=' * 80);
        output.writeln(filteredLines.join('\n'));

        if (removedLines.isNotEmpty) {
          output.writeln('\n' + '-' * 40);
          output.writeln('【被过滤的行】');
          output.writeln('-' * 40);
          for (final line in removedLines) {
            output.writeln(line);
          }
        }

        // 提取的下载链接
        final downloads = extractDownloadLinks(filteredLines.join('\n'));
        output.writeln('\n' + '=' * 80);
        output.writeln('【提取的下载链接】');
        output.writeln('=' * 80);
        for (final dl in downloads) {
          output.writeln('  提供商: ${dl.provider ?? "未知"}');
          output.writeln('  URL: ${dl.url}');
          if (dl.label != null) output.writeln('  标签: ${dl.label}');
          if (dl.password != null) output.writeln('  提取码: ${dl.password}');
          output.writeln('  ---');
        }
      } else {
        output.writeln('\n【未找到 showhide 内容】');
      }

      // 3. locked内容
      final lockedDivs = postContent.querySelectorAll('div.locked');
      if (lockedDivs.isNotEmpty) {
        output.writeln('\n' + '=' * 80);
        output.writeln('【locked内容】');
        output.writeln('=' * 80);
        for (final div in lockedDivs) {
          output.writeln(div.text.trim());
          output.writeln('---');
        }
      }

      // 4. 概要部分
      var fullText = postContent.text;
      fullText = fullText.replaceAll(RegExp(r'[\w.]+\.\w+\s*\([^)]*KB[^)]*\)[^\n]*下載附件[^\n]*(?:\d+\s*天前|\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})\s*上傳'), '');
      fullText = fullText.replaceAll(RegExp(r'[\w.]+\.\w+\s*\([^)]*KB[^)]*\)[^\n]*下載附件'), '');
      final uploadMarker = RegExp(r'(?:\d+\s*天前|\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})\s*上傳');
      final allMarkers = uploadMarker.allMatches(fullText).toList();
      if (allMarkers.isNotEmpty) {
        fullText = fullText.substring(allMarkers.last.end).trim();
      }

      output.writeln('\n' + '=' * 80);
      output.writeln('【概要部分 - 过滤前】');
      output.writeln('=' * 80);
      final descBeforeFilter = _extractSection(fullText, '概要');
      output.writeln(descBeforeFilter ?? '未提取');

      // 过滤后的概要
      if (descBeforeFilter != null) {
        final descAfterFilter = descBeforeFilter
            .replaceAll(RegExp(r'[^\n]*(优惠码|折扣码|优惠卷)[^\n]*'), '')
            .replaceAll(RegExp(r'[^\n]*(解压码|解压密码|解压口令)[^\n]*'), '')
            .replaceAll(RegExp(r'[^\n]*提取码[^\n]*'), '')
            .replaceAll(RegExp(r'[^\n]*(VIP|vip|Vip)[^\n]*'), '')
            .replaceAll(RegExp(r'[^\n]*飞猫云[^\n]*'), '')
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim();

        output.writeln('\n' + '=' * 80);
        output.writeln('【概要部分 - 过滤后】');
        output.writeln('=' * 80);
        output.writeln(descAfterFilter.isEmpty ? '(空)' : descAfterFilter);
      }
    }

    // 解压码
    final signDiv = doc.querySelector('div.sign');
    if (signDiv != null) {
      output.writeln('\n' + '=' * 80);
      output.writeln('【签名区域内容】');
      output.writeln('=' * 80);
      output.writeln(signDiv.text.trim());

      final unzipCode = extractUnzipCode(signDiv.text);
      output.writeln('\n【提取的解压码】');
      output.writeln(unzipCode ?? '未提取');
    }

    // 发布信息
    final authorPost = doc.querySelector('em[id^="authorposton"]');
    if (authorPost != null) {
      output.writeln('\n【发布信息】');
      output.writeln(authorPost.text.trim());
    }

    // 写入文件
    File('test/full_content_output.txt').writeAsStringSync(output.toString());
    print('✅ 内容已输出到 test/full_content_output.txt');

  } catch (e) {
    output.writeln('错误: $e');
    File('test/full_content_output.txt').writeAsStringSync(output.toString());
    print('❌ 错误: $e');
  }
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
    '(游戏介绍[：:]|游戏特点[：:]|更新内容[：:]|链接[：:]|下载|解压)',
  ).firstMatch(fullText.substring(contentStart));

  final contentEnd = nextSectionMatch != null
      ? contentStart + nextSectionMatch.start
      : fullText.length;

  return fullText.substring(contentStart, contentEnd).trim();
}
