import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';

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
  });

  group('GameInfo.downloadUrl', () {
    test('带 label 的链接输出标签前缀', () {
      final info = GameInfo(
        sourceUrl: 'https://example.com/1',
        downloads: [
          DownloadLink(url: 'https://pan.baidu.com/s/abc', label: '备用'),
          DownloadLink(
              url: 'https://pan.quark.cn/s/def',
              label: '夸克',
              password: 'wC8u'),
          DownloadLink(url: 'https://drive.uc.cn/s/ghi'),
        ],
      );
      expect(
        info.downloadUrl,
        '备用 https://pan.baidu.com/s/abc\n'
        '夸克 https://pan.quark.cn/s/def 提取码: wC8u\n'
        'https://drive.uc.cn/s/ghi',
      );
    });
  });
}
