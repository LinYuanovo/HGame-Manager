import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/ui/pages/games/content_search_engine.dart';

void main() {
  group('ContentSearchEngine.findAll', () {
    test('空查询返回空列表', () {
      final results = ContentSearchEngine.findAll(
        query: '',
        sections: {'intro': 'Hello World'},
      );
      expect(results, isEmpty);
    });

    test('纯空格查询返回空列表', () {
      final results = ContentSearchEngine.findAll(
        query: '   ',
        sections: {'intro': 'Hello World'},
      );
      expect(results, isEmpty);
    });

    test('纯制表符查询返回空列表', () {
      final results = ContentSearchEngine.findAll(
        query: '\t\t',
        sections: {'intro': 'Hello World'},
      );
      expect(results, isEmpty);
    });

    test('null区域被跳过', () {
      final results = ContentSearchEngine.findAll(
        query: 'Hello',
        sections: {
          'intro': null,
          'guide': 'Hello World',
        },
      );
      expect(results.length, 1);
      expect(results.first.sectionKey, 'guide');
    });

    test('空字符串区域被跳过', () {
      final results = ContentSearchEngine.findAll(
        query: 'Hello',
        sections: {
          'intro': '',
          'guide': 'Hello World',
        },
      );
      expect(results.length, 1);
      expect(results.first.sectionKey, 'guide');
    });

    test('图片标签行被跳过', () {
      final results = ContentSearchEngine.findAll(
        query: '测试',
        sections: {
          'intro': '[图片:test.png]\n这是测试内容',
        },
      );
      expect(results.length, 1);
      expect(results.first.lineIndex, 1);
    });

    test('视频标签行被跳过', () {
      final results = ContentSearchEngine.findAll(
        query: '测试',
        sections: {
          'intro': '[视频:test.mp4]\n这是测试内容',
        },
      );
      expect(results.length, 1);
      expect(results.first.lineIndex, 1);
    });

    test('不区分大小写搜索（默认）', () {
      final results = ContentSearchEngine.findAll(
        query: 'hello',
        sections: {'intro': 'Hello World'},
      );
      expect(results.length, 1);
      expect(results.first.charOffset, 0);
      expect(results.first.matchLength, 5);
    });

    test('区分大小写搜索', () {
      final results = ContentSearchEngine.findAll(
        query: 'Hello',
        sections: {'intro': 'hello world'},
        caseSensitive: true,
      );
      expect(results, isEmpty);
    });

    test('区分大小写搜索 - 匹配存在', () {
      final results = ContentSearchEngine.findAll(
        query: 'Hello',
        sections: {'intro': 'Hello World'},
        caseSensitive: true,
      );
      expect(results.length, 1);
      expect(results.first.charOffset, 0);
    });

    test('特殊正则字符被转义', () {
      final results = ContentSearchEngine.findAll(
        query: 'hello.world',
        sections: {'intro': 'hello.world'},
      );
      expect(results.length, 1);

      final noMatchResults = ContentSearchEngine.findAll(
        query: 'hello.world',
        sections: {'intro': 'helloXworld'},
      );
      expect(noMatchResults, isEmpty);
    });

    test('正则特殊字符 [ ] 被转义', () {
      final results = ContentSearchEngine.findAll(
        query: '[test]',
        sections: {'intro': '[test] content'},
      );
      expect(results.length, 1);

      final noMatchResults = ContentSearchEngine.findAll(
        query: '[test]',
        sections: {'intro': 'test content'},
      );
      expect(noMatchResults, isEmpty);
    });

    test('正则特殊字符 + * 被转义', () {
      final results = ContentSearchEngine.findAll(
        query: 'a+b*c',
        sections: {'intro': 'a+b*c'},
      );
      expect(results.length, 1);

      final noMatchResults = ContentSearchEngine.findAll(
        query: 'a+b*c',
        sections: {'intro': 'abc'},
      );
      expect(noMatchResults, isEmpty);
    });

    test('多行内容搜索', () {
      final results = ContentSearchEngine.findAll(
        query: 'World',
        sections: {
          'intro': 'Hello\nWorld\nFoo',
        },
      );
      expect(results.length, 1);
      expect(results.first.lineIndex, 1);
      expect(results.first.charOffset, 0);
    });

    test('同一行多个匹配', () {
      final results = ContentSearchEngine.findAll(
        query: 'ab',
        sections: {'intro': 'ab cd ab ef ab'},
      );
      expect(results.length, 3);
      expect(results[0].charOffset, 0);
      expect(results[1].charOffset, 6);
      expect(results[2].charOffset, 12);
    });

    test('多个区域搜索', () {
      final results = ContentSearchEngine.findAll(
        query: 'test',
        sections: {
          'intro': 'test intro',
          'guide': 'test guide',
          'changelog': 'no match here',
        },
      );
      expect(results.length, 2);
      final sectionKeys = results.map((r) => r.sectionKey).toList();
      expect(sectionKeys, containsAll(['intro', 'guide']));
    });

    test('匹配长度正确', () {
      final results = ContentSearchEngine.findAll(
        query: 'abc',
        sections: {'intro': 'xxxabcxxx'},
      );
      expect(results.length, 1);
      expect(results.first.matchLength, 3);
      expect(results.first.charOffset, 3);
    });

    test('空sections返回空列表', () {
      final results = ContentSearchEngine.findAll(
        query: 'test',
        sections: {},
      );
      expect(results, isEmpty);
    });

    test('所有区域为null返回空列表', () {
      final results = ContentSearchEngine.findAll(
        query: 'test',
        sections: {
          'intro': null,
          'guide': null,
        },
      );
      expect(results, isEmpty);
    });
  });

  group('ContentSearchMatch', () {
    test('所有字段是final的（不可变性）', () {
      const match = ContentSearchMatch(
        sectionKey: 'intro',
        lineIndex: 0,
        charOffset: 5,
        matchLength: 3,
      );
      expect(match.sectionKey, 'intro');
      expect(match.lineIndex, 0);
      expect(match.charOffset, 5);
      expect(match.matchLength, 3);
    });

    test('相等性比较', () {
      const match1 = ContentSearchMatch(
        sectionKey: 'intro',
        lineIndex: 0,
        charOffset: 5,
        matchLength: 3,
      );
      const match2 = ContentSearchMatch(
        sectionKey: 'intro',
        lineIndex: 0,
        charOffset: 5,
        matchLength: 3,
      );
      expect(match1, equals(match2));
    });
  });
}
