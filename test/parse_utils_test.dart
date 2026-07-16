import '../lib/scraper/parse_utils.dart';

void main() {
  print('=' * 80);
  print('parse_utils.dart 公共工具方法测试');
  print('=' * 80);

  testExtractBrackets();
  testExtractVersion();
  testExtractUnzipCode();
  testIsDownloadLink();
  testExtractDownloadLinks();

  print('\n${'=' * 80}');
  print('所有测试完成!');
  print('=' * 80);
}

void testExtractBrackets() {
  print('\n--- 测试 extractBracketsFromTitle ---');

  final tests = [
    ('【ACT/中文/全动态】禁闭乐园：堕罪之寓 V1.5', ['ACT', '中文', '全动态']),
    ('[SLG/汉化/NTR] 游戏名 v2.0', ['SLG', '汉化', 'NTR']),
    ('没有标签的游戏名', null),
  ];

  for (final (input, expected) in tests) {
    final result = extractBracketsFromTitle(input);
    final pass = _listEquals(result, expected);
    print('${pass ? "✅" : "❌"} "$input"');
    print('   期望: $expected');
    print('   实际: $result');
  }
}

void testExtractVersion() {
  print('\n--- 测试 extractVersion ---');

  final tests = [
    ('禁闭乐园：堕罪之寓 V1.5', 'V1.5'),
    ('游戏名 ver2.1', 'V2.1'),
    ('游戏名 Build123', 'V123'),
    ('游戏名 version3.0.1', 'V3.0.1'),
    ('没有版本号的游戏', null),
  ];

  for (final (input, expected) in tests) {
    final result = extractVersion(input);
    final pass = result == expected;
    print('${pass ? "✅" : "❌"} "$input" => $result');
  }
}

void testExtractUnzipCode() {
  print('\n--- 测试 extractUnzipCode ---');

  final tests = [
    ('解压码：嘤嘤嘤', '嘤嘤嘤'),
    ('解压密码：abc123', 'abc123'),
    ('默认解压码：xyz', 'xyz'),
    ('没有解压码的文本', null),
  ];

  for (final (input, expected) in tests) {
    final result = extractUnzipCode(input);
    final pass = result == expected;
    print('${pass ? "✅" : "❌"} "$input" => $result');
  }
}

void testIsDownloadLink() {
  print('\n--- 测试 isDownloadLink ---');

  final tests = [
    ('https://pan.baidu.com/s/xxx', true),
    ('https://pan.xunlei.com/s/xxx', true),
    ('https://share.weiyun.com/xxx', true),
    ('https://drive.uc.cn/s/xxx', true),
    ('https://gofile.io/d/xxx', true),
    ('https://cm1.hk/s/xxx', true),
    ('https://cm2.hk/s/xxx', true),
    ('https://example.com', false),
    ('https://google.com', false),
  ];

  for (final (input, expected) in tests) {
    final result = isDownloadLink(input);
    final pass = result == expected;
    print('${pass ? "✅" : "❌"} "$input" => $result');
  }
}

void testExtractDownloadLinks() {
  print('\n--- 测试 extractDownloadLinks ---');

  final text1 = '''链接：
https://pan.baidu.com/s/1JNdzpnG9vakulh76qgA_Uw
提取码: 8qb9

https://pan.xunlei.com/s/VOpkQHGHY6o_kXl7VV0glP9sA1#
提取码：g2h8

https://share.weiyun.com/pqU328lh
密码：7pjswq

https://drive.uc.cn/s/e5b2a33c9b744
密码：xnVL

解压码：嘤嘤嘤''';

  print('\n测试1: ACG嘤嘤怪格式');
  final links1 = extractDownloadLinks(text1);
  print('提取到 ${links1.length} 个下载链接:');
  for (final link in links1) {
    print('  - [${link.provider}] ${link.url}');
    if (link.password != null) print('    提取码: ${link.password}');
    if (link.unzipCode != null) print('    解压码: ${link.unzipCode}');
  }

  final text2 = '''飞猫直链①：https://cm1.hk/s/mwuxwf
飞猫直链②：https://cm2.hk/s/356x5k
飞猫转链：https://cm1.hk/s/rmge51
飞猫优惠码：SLZMTM''';

  print('\n测试2: 飞雪ACG格式');
  final links2 = extractDownloadLinks(text2);
  print('提取到 ${links2.length} 个下载链接:');
  for (final link in links2) {
    print('  - [${link.provider}] ${link.url}');
    if (link.label != null) print('    标签: ${link.label}');
  }
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
