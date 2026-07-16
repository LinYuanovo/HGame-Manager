import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../lib/scraper/parse_utils.dart';

void main() async {
  final url = 'https://feixueacg.org/thread-83410-1-1.html';
  const cookie = 'X_CACHE_KEY=6f79c552ad8d31a3aa82d8cf65dbc65a; acFt_cookie=acFt_1; bPvg_2132_saltkey=Ahf4KI88; bPvg_2132_lastvisit=1779681602; bPvg_2132_atarget=1; bPvg_2132_auth=a85dzUrgzFuY48W00Sd%2B2cfbauK4mjFB1V2ghaai3sXX8CnPtV0RoT%2BZs0s%2Fp2OHxB55i%2BAc5CArcACMgQ5jOsndO9Q; bPvg_2132_lastcheckfeed=183720%7C1779685277; bPvg_2132_nofavfid=1; bPvg_2132_smile=1D1; bPvg_2132_visitedfid=43D64; server_name_session=f0a8796083e63e25a066bfaadd47d480; bPvg_2132_seccodecSAA9N0=23913.59e10036f2c92fc895; bPvg_2132_seccodecSAdUX0=24235.81a119aeb35f34d890; bPvg_2132_st_t=183720%7C1779795460%7C2dcd3e24bc61f389201ea63e3dcfe2f4; bPvg_2132_forum_lastvisit=D_64_1779692273D_43_1779795460; bPvg_2132_ulastactivity=1779798762%7C0; bPvg_2132_st_p=183720%7C1779798807%7Cd8e39f4136c9509f8f88b67e36d1a9a1; bPvg_2132_viewid=tid_88994; bPvg_2132_seccodecS0=35372.6d18bf92ab1d258093; bPvg_2132_lastact=1779798809%09plugin.php%09';

  final output = StringBuffer();
  output.writeln('过滤逻辑测试结果');
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
      File('test/filter_output.txt').writeAsStringSync(output.toString());
      return;
    }

    final doc = html_parser.parse(response.body);

    // 提取签名区域的解压码
    String? unzipCodeFromSign;
    final signDiv = doc.querySelector('div.sign');
    if (signDiv != null) {
      unzipCodeFromSign = extractUnzipCode(signDiv.text);
      output.writeln('\n【签名区域】');
      output.writeln('原始内容:');
      output.writeln(signDiv.text.trim());
      output.writeln('\n提取的解压码: ${unzipCodeFromSign ?? "无"}');
    }

    // 提取帖子内容
    final postContent = doc.querySelector('td.t_f');
    if (postContent != null) {
      // 移除提示div
      for (final tipDiv in postContent.querySelectorAll('div.tip, div.tip_4, div.aimg_tip')) {
        tipDiv.remove();
      }
      for (final script in postContent.querySelectorAll('script')) {
        script.remove();
      }

      // 1. showhide内容过滤
      final showhideDiv = postContent.querySelector('div.showhide');
      if (showhideDiv != null) {
        output.writeln('\n${'=' * 80}');
        output.writeln('【showhide过滤测试】');
        output.writeln('=' * 80);

        final originalText = showhideDiv.text;
        output.writeln('\n过滤前:');
        output.writeln(originalText.trim());

        final filteredText = filterCommonNoise(originalText);
        output.writeln('\n过滤后:');
        output.writeln(filteredText.isEmpty ? '(空)' : filteredText);

        final downloads = extractDownloadLinks(filteredText);
        output.writeln('\n提取的下载链接: ${downloads.length} 个');
        for (final dl in downloads) {
          output.writeln('  - ${dl.url}');
        }
      }

      // 2. 帖子全文过滤
      output.writeln('\n${'=' * 80}');
      output.writeln('【帖子全文过滤测试】');
      output.writeln('=' * 80);

      var fullText = postContent.text;
      output.writeln('\n过滤前 (前500字符):');
      output.writeln(fullText.length > 500 ? '${fullText.substring(0, 500)}...' : fullText);

      fullText = filterCommonNoise(fullText);
      output.writeln('\nfilterCommonNoise后 (前500字符):');
      output.writeln(fullText.length > 500 ? '${fullText.substring(0, 500)}...' : fullText);

      // 3. 游戏介绍过滤（使用filterDescription，排除签名区解压码）
      output.writeln('\n${'=' * 80}');
      output.writeln('【游戏介绍过滤测试】');
      output.writeln('=' * 80);

      // 假设游戏介绍是"游戏介绍："之后的内容
      final introMatch = RegExp(r'游戏介绍[：:](.+?)(?=更新日志[：:]|$)', dotAll: true).firstMatch(fullText);
      if (introMatch != null) {
        final rawIntro = introMatch.group(1)!.trim();
        output.writeln('\n过滤前:');
        output.writeln(rawIntro);

        final filteredIntro = filterDescription(rawIntro, unzipCodeFromSign: unzipCodeFromSign);
        output.writeln('\nfilterDescription后 (排除签名区解压码):');
        output.writeln(filteredIntro.isEmpty ? '(空)' : filteredIntro);
      } else {
        output.writeln('\n未找到"游戏介绍："标记');
      }

      // 4. 更新日志过滤
      output.writeln('\n${'=' * 80}');
      output.writeln('【更新日志过滤测试】');
      output.writeln('=' * 80);

      final changelogMatch = RegExp(r'更新日志[：:](.+?)(?=已补档|$)', dotAll: true).firstMatch(fullText);
      if (changelogMatch != null) {
        final rawChangelog = changelogMatch.group(1)!.trim();
        output.writeln('\n过滤前:');
        output.writeln(rawChangelog);

        final filteredChangelog = filterCommonNoise(rawChangelog);
        output.writeln('\nfilterCommonNoise后:');
        output.writeln(filteredChangelog.isEmpty ? '(空)' : filteredChangelog);
      } else {
        output.writeln('\n未找到"更新日志："标记');
      }
    }

    // 写入文件
    File('test/filter_output.txt').writeAsStringSync(output.toString());
    print('✅ 过滤测试结果已输出到 test/filter_output.txt');

  } catch (e) {
    output.writeln('错误: $e');
    File('test/filter_output.txt').writeAsStringSync(output.toString());
    print('❌ 错误: $e');
  }
}
