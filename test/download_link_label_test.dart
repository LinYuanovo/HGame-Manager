import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:hgame_manager/scraper/parse_utils.dart';
import 'package:hgame_manager/scraper/site_parsers.dart';

void main() {
  group('extractDownloadLinks 前置标签', () {
    test('空格分隔的前置标签被提取为 label', () {
      const text = '''
解压教程 https://pan.baidu.com/s/1GXCJmmJIMlqblZFtLH35qQ?pwd=kdy2
百度 https://pan.baidu.com/s/1BGTpGKw9STmESYKw3U2q2Q?pwd=2tdi
夸克 https://pan.quark.cn/s/478b6b749d5c 提取码: wC8u
UC https://drive.uc.cn/s/85695af27a564
备用 https://1024terabox.com/s/1dyheuRH80zS1Dwv1FlSTXQ
''';
      final links = extractDownloadLinks(text);
      expect(links.length, 5);
      expect(links[0].label, '解压教程');
      expect(links[1].label, '百度');
      expect(links[2].label, '夸克');
      expect(links[2].password, 'wC8u');
      expect(links[3].label, 'UC');
      expect(links[4].label, '备用');
    });

    test('冒号格式标签保持原有行为', () {
      const text = '飞猫直链①：https://cm1.hk/s/mwuxwf';
      final links = extractDownloadLinks(text);
      expect(links.length, 1);
      expect(links[0].label, '飞猫直链①');
    });

    test('纯 URL 行不带 label', () {
      const text = 'https://pan.baidu.com/s/1JNdzpnG9vakulh76qgA_Uw';
      final links = extractDownloadLinks(text);
      expect(links.length, 1);
      expect(links[0].label, isNull);
    });

    test('过长前缀不视为标签', () {
      const text = '这是一段非常长的说明性文字已经超过十五个字符 https://pan.baidu.com/s/abc';
      final links = extractDownloadLinks(text);
      expect(links.length, 1);
      expect(links[0].label, isNull);
    });

    test('提取码独占下一行的跨行配对保持原有行为', () {
      const text = '''
https://pan.baidu.com/s/1JNdzpnG9vakulh76qgA_Uw
提取码: 8qb9
''';
      final links = extractDownloadLinks(text);
      expect(links.length, 1);
      expect(links[0].label, isNull);
      expect(links[0].password, '8qb9');
    });
  });

  group('extractDownloadLinks 维咔格式（标签独占一行）', () {
    test('标签行配对到下一行的 URL，括号内提取码一并提取', () {
      const text = '''
保存到网盘后再下载：
百度 （提取码436o）
https://pan.baidu.com/s/1hAeUN_9MQDK1HrC2N0zSKw?pwd=436o
夸克
https://pan.quark.cn/s/648537865538
UC
https://drive.uc.cn/s/8f277819b7f34
迅雷 （提取码nfc4）
https://pan.xunlei.com/s/VP2Do601ZrdK1caahlopwNBjA1?pwd=nfc4
备用
https://gofile.io/d/Qc4rqf
超3000款大合集！：https://share.weiyun.com/fr7Ki9ZL
''';
      final links = extractDownloadLinks(text);
      expect(links.length, 6);
      DownloadLink byHost(String host) =>
          links.firstWhere((l) => l.url.contains(host));
      expect(byHost('pan.baidu.com').label, '百度');
      expect(byHost('pan.baidu.com').password, '436o');
      expect(byHost('pan.quark.cn').label, '夸克');
      expect(byHost('drive.uc.cn').label, 'UC');
      expect(byHost('pan.xunlei.com').label, '迅雷');
      expect(byHost('pan.xunlei.com').password, 'nfc4');
      expect(byHost('gofile.io').label, '备用');
      expect(byHost('share.weiyun.com').label, '超3000款大合集！');
    });
  });

  group('VikAcgParser 下载链接', () {
    test('external 外链不作为下载地址，标签独占行正常配对', () {
      final doc = html_parser.parse('''
<html><head><meta property="og:title" content="测试游戏 - 维咔VikACG"></head>
<body><div class="prose">
<p>每日更新介绍</p>
<p>备用</p>
<p>https://gofile.io/d/Qc4rqf</p>
<p>百度 （教程）：<a href="https://www.vikacg.com/external?e=8A39CC60B6E649DE">网页链接</a>(pan.baidu.com)</p>
</div></body></html>
''');
      final info =
          VikAcgParser().parseGameInfo(doc, 'https://www.vikacg.cc/p/12345');
      expect(info, isNotNull);
      final urls = info!.downloads.map((d) => d.url).toList();
      expect(urls.any((u) => u.contains('/external')), isFalse);
      expect(urls, contains('https://gofile.io/d/Qc4rqf'));
      final gofile =
          info.downloads.firstWhere((d) => d.url.contains('gofile'));
      expect(gofile.label, '备用');
    });
  });
}
