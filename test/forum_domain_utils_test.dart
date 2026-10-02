import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/forum_domain_utils.dart';

void main() {
  group('ForumDomainUtils.rewriteWithCustomDomain', () {
    test('旧域名替换为自定义域名，路径与查询串保留', () {
      // 注意：Dart Uri 会把百分号编码归一化为大写（RFC 3986 下语义相同）
      const url =
          'https://acgyyg.ru/2026/07/03/%e3%80%90slg%e3%80%9145%e5%8f%b7/?page=2#comments';
      final rewritten = ForumDomainUtils.rewriteWithCustomDomain(
          url, {'acgying': 'acgyyg.cc'});
      expect(
        rewritten,
        'https://acgyyg.cc/2026/07/03/%E3%80%90slg%E3%80%9145%E5%8F%B7/?page=2#comments',
      );
    });

    test('品牌出现在主域名首标签即匹配（含前后缀的新域名）', () {
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://acgyyg.me/post/1', {'acgying': 'acgyyg.cc'}),
        'https://acgyyg.cc/post/1',
      );
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://acgying.com/post/1', {'acgying': 'acgyyg.cc'}),
        'https://acgyyg.cc/post/1',
      );
    });

    test('子域名挂靠在无关主域名下时不匹配', () {
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://acgyyg.evil.com/post/1', {'acgying': 'acgyyg.cc'}),
        isNull,
      );
    });

    test('无关域名不重写', () {
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://example.com/post/1', {'acgying': 'acgyyg.cc'}),
        isNull,
      );
    });

    test('已是自定义域名时不重写', () {
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://acgyyg.cc/post/1', {'acgying': 'acgyyg.cc'}),
        isNull,
      );
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://www.acgyyg.cc/post/1', {'acgying': 'acgyyg.cc'}),
        isNull,
      );
    });

    test('未配置自定义域名时不重写', () {
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://acgyyg.ru/post/1', {}),
        isNull,
      );
    });

    test('自定义域名写成完整 URL 时也能归一化', () {
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://acgyyg.ru/post/1', {'acgying': 'https://acgyyg.cc/'}),
        'https://acgyyg.cc/post/1',
      );
    });

    test('其他论坛品牌互不影响', () {
      final custom = {'acgying': 'acgyyg.cc', 'feixue': 'feixueacg.xyz'};
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://feixueacg.org/thread-1', custom),
        'https://feixueacg.xyz/thread-1',
      );
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'https://acgyyg.ru/post/1', custom),
        'https://acgyyg.cc/post/1',
      );
    });

    test('保留原 scheme', () {
      expect(
        ForumDomainUtils.rewriteWithCustomDomain(
            'http://acgyyg.ru/post/1', {'acgying': 'acgyyg.cc'}),
        'http://acgyyg.cc/post/1',
      );
    });

    test('非 URL 输入返回 null', () {
      expect(
        ForumDomainUtils.rewriteWithCustomDomain('not a url', {'acgying': 'acgyyg.cc'}),
        isNull,
      );
    });
  });

  group('ForumDomainUtils.hostMatchesBrand', () {
    test('主域名首标签等于或包含品牌关键词', () {
      expect(ForumDomainUtils.hostMatchesBrand('acgyyg.ru', ['acgyyg']), isTrue);
      expect(
          ForumDomainUtils.hostMatchesBrand('www.acgyyg.cc', ['acgyyg']), isTrue);
      expect(
          ForumDomainUtils.hostMatchesBrand('acgyyg123.me', ['acgyyg']), isTrue);
    });

    test('品牌只出现在子域名或非首标签时不匹配', () {
      expect(
          ForumDomainUtils.hostMatchesBrand('acgyyg.evil.com', ['acgyyg']),
          isFalse);
      expect(
          ForumDomainUtils.hostMatchesBrand('example.com', ['acgyyg']), isFalse);
    });
  });
}
