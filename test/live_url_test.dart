import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../lib/scraper/parse_utils.dart';

void main() async {
  final url = 'https://feixueacg.org/thread-83410-1-1.html';
  const cookie = 'X_CACHE_KEY=6f79c552ad8d31a3aa82d8cf65dbc65a; acFt_cookie=acFt_1; bPvg_2132_saltkey=Ahf4KI88; bPvg_2132_lastvisit=1779681602; bPvg_2132_atarget=1; bPvg_2132_auth=a85dzUrgzFuY48W00Sd%2B2cfbauK4mjFB1V2ghaai3sXX8CnPtV0RoT%2BZs0s%2Fp2OHxB55i%2BAc5CArcACMgQ5jOsndO9Q; bPvg_2132_lastcheckfeed=183720%7C1779685277; bPvg_2132_nofavfid=1; bPvg_2132_smile=1D1; bPvg_2132_visitedfid=43D64; server_name_session=f0a8796083e63e25a066bfaadd47d480; bPvg_2132_seccodecSAA9N0=23913.59e10036f2c92fc895; bPvg_2132_seccodecSAdUX0=24235.81a119aeb35f34d890; bPvg_2132_st_t=183720%7C1779795460%7C2dcd3e24bc61f389201ea63e3dcfe2f4; bPvg_2132_forum_lastvisit=D_64_1779692273D_43_1779795460; bPvg_2132_ulastactivity=1779798762%7C0; bPvg_2132_st_p=183720%7C1779798807%7Cd8e39f4136c9509f8f88b67e36d1a9a1; bPvg_2132_viewid=tid_88994; bPvg_2132_seccodecS0=35372.6d18bf92ab1d258093; bPvg_2132_lastact=1779798809%09plugin.php%09';

  print('=' * 80);
  print('测试URL解析: $url');
  print('=' * 80);

  try {
    // 发送HTTP请求
    print('\n📡 正在请求URL...');
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Cookie': cookie,
      },
    ).timeout(const Duration(seconds: 30));

    print('📊 HTTP状态码: ${response.statusCode}');

    if (response.statusCode != 200) {
      print('❌ 请求失败');
      return;
    }

    // 解析HTML
    final doc = html_parser.parse(response.body);

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

    // 提取内容
    final postContent = doc.querySelector('td.t_f');
    if (postContent != null) {
      // 移除提示div
      for (final tipDiv in postContent.querySelectorAll('div.tip, div.tip_4, div.aimg_tip')) {
        tipDiv.remove();
      }
      for (final script in postContent.querySelectorAll('script')) {
        script.remove();
      }

      // 提取下载链接
      final showhideDiv = postContent.querySelector('div.showhide');
      if (showhideDiv != null) {
        var showhideText = showhideDiv.text;
        showhideText = showhideText.replaceAll('本帖隱藏的內容', '').trim();

        // 过滤掉优惠码、VIP相关文本
        final lines = showhideText.split('\n').where((l) => l.trim().isNotEmpty).toList();
        final filteredLines = <String>[];
        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.contains('优惠码')) continue;
          if (trimmedLine.contains('VIP') || trimmedLine.contains('免飞猫')) continue;
          filteredLines.add(trimmedLine);
        }
        showhideText = filteredLines.join('\n');

        final downloads = extractDownloadLinks(showhideText);
        print('\n📥 下载链接 (${downloads.length} 个):');
        for (final dl in downloads) {
          print('  - [${dl.provider ?? "未知"}] ${dl.url}');
          if (dl.label != null) print('    标签: ${dl.label}');
          if (dl.password != null) print('    提取码: ${dl.password}');
        }
      } else {
        print('\n⚠️ 未找到 div.showhide（可能需要回复或VIP权限）');
      }

      // 检查是否有locked div
      final lockedDivs = postContent.querySelectorAll('div.locked');
      if (lockedDivs.isNotEmpty) {
        print('\n🔒 发现 locked 内容:');
        for (final div in lockedDivs) {
          final text = div.text.trim();
          if (text.contains('VIP')) {
            print('  - VIP付费内容');
          } else if (text.contains('回復')) {
            print('  - 回复后可见');
          } else {
            print('  - $text');
          }
        }
      }
    }

    // 提取解压码
    final signDiv = doc.querySelector('div.sign');
    if (signDiv != null) {
      final unzipCode = extractUnzipCode(signDiv.text);
      print('\n🔓 解压码: ${unzipCode ?? "未提取"}');
    }

    // 提取发布信息
    final authorPost = doc.querySelector('em[id^="authorposton"]');
    if (authorPost != null) {
      print('\n📅 发布信息: ${authorPost.text.trim()}');
    }

    // 提取查看数和回复数
    final viewCount = doc.querySelector('span.xi1');
    if (viewCount != null) {
      print('👁️ 查看数: ${viewCount.text.trim()}');
    }

    print('\n✅ 解析完成');

  } catch (e) {
    print('❌ 错误: $e');
  }
}
