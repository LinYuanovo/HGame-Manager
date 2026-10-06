import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/intro_html_sync.dart';

void main() {
  test('修改单行时只更新对应文本，其余内容不变', () {
    const html = '<p>第一段</p><p>第二段</p><p><img src="a.jpg"></p><p>第三段</p>';
    const oldIntro = '第一段\n第二段\n第三段';
    const newIntro = '第一段\n改过的第二段\n第三段';

    final result = syncIntroToHtml(oldIntro, newIntro, html);

    expect(result, contains('改过的第二段'));
    expect(result, contains('第一段'));
    expect(result, contains('第三段'));
    expect(result, contains('<img src="a.jpg">'));
    expect(result, isNot(contains('<p>第二段</p>')));
  });

  test('交换两行不会产生重复文本（级联替换回归）', () {
    const html = '<p>苹果</p><p>香蕉</p>';
    const oldIntro = '苹果\n香蕉';
    const newIntro = '香蕉\n苹果';

    final result = syncIntroToHtml(oldIntro, newIntro, html);

    expect(result, contains('<p>香蕉</p><p>苹果</p>'));
  });

  test('重复句子只替换目标位置', () {
    const html = '<p>注意</p><p>内容</p><p>注意</p>';
    const oldIntro = '注意\n内容\n注意';
    const newIntro = '注意\n内容\n提醒';

    final result = syncIntroToHtml(oldIntro, newIntro, html);

    expect(result, contains('<p>注意</p><p>内容</p><p>提醒</p>'));
  });

  test('删除一行时从 HTML 中移除对应文本', () {
    const html = '<p>第一段</p><p>第二段</p><p>第三段</p>';
    const oldIntro = '第一段\n第二段\n第三段';
    const newIntro = '第一段\n第三段';

    final result = syncIntroToHtml(oldIntro, newIntro, html);

    expect(result, isNot(contains('第二段')));
    expect(result, contains('第一段'));
    expect(result, contains('第三段'));
  });

  test('新增一行时插入到对应位置', () {
    const html = '<p>第一段</p><p>第三段</p>';
    const oldIntro = '第一段\n第三段';
    const newIntro = '第一段\n第二段\n第三段';

    final result = syncIntroToHtml(oldIntro, newIntro, html);

    final first = result.indexOf('第一段');
    final second = result.indexOf('第二段');
    final third = result.indexOf('第三段');
    expect(second, greaterThan(first));
    expect(third, greaterThan(second));
  });

  test('行内包含 HTML 特殊字符时按转义后的文本节点匹配', () {
    const html = '<p>A &amp; B &lt;测试&gt;</p><p>第二段</p>';
    const oldIntro = 'A & B <测试>\n第二段';
    const newIntro = 'A & B <测试>\n改过的第二段';

    final result = syncIntroToHtml(oldIntro, newIntro, html);

    expect(result, contains('改过的第二段'));
    expect(result, contains('A &amp; B &lt;测试&gt;'));
  });

  test('跨内联标签的行可以整体替换', () {
    const html = '<p>这是<strong>加粗</strong>的一行</p>';
    const oldIntro = '这是加粗的一行';
    const newIntro = '全新的一行';

    final result = syncIntroToHtml(oldIntro, newIntro, html);

    expect(result, contains('全新的一行'));
    expect(result, isNot(contains('加粗')));
  });

  test('HTML 中找不到的行直接跳过，不做错位替换', () {
    const html = '<p>只有这一段</p>';
    const oldIntro = '不存在的旧行\n只有这一段';
    const newIntro = '不存在的旧行\n改过的一段';

    final result = syncIntroToHtml(oldIntro, newIntro, html);

    expect(result, contains('改过的一段'));
  });

  test('简介未变化时返回原 HTML', () {
    const html = '<p>第一段</p>';
    expect(syncIntroToHtml('第一段', '第一段', html), html);
  });

  group('整段简介包在单个 <p> 内（仅用 <br> 分行）', () {
    const html = '<p><img src="a.webp"></p>'
        '<p><img src="b.webp"></p>'
        '<p><br>社团名：测试社<br>'
        '进入东京。活着撤离。<br>'
        '每次行动都需要不同的策略。<br>'
        '仅靠火力无法生存。<br>'
        '百度下载：https://pan.baidu.com/s/1abc<br>'
        '结尾提示行</p>';
    const intro = '[图片:a.webp]\n[图片:b.webp]\n社团名：测试社\n'
        '进入东京。活着撤离。\n每次行动都需要不同的策略。\n'
        '仅靠火力无法生存。\n百度下载：https://pan.baidu.com/s/1abc\n结尾提示行';

    test('整段重写时新文本必须写入，不能被静默丢弃', () {
      final result =
          syncIntroToHtml(intro, '全新简介第一行\n全新简介第二行', html);

      expect(result, contains('全新简介第一行'));
      expect(result, contains('全新简介第二行'));
      expect(result, isNot(contains('社团名：测试社')));
      expect(result, isNot(contains('pan.baidu.com')));
      expect(RegExp(r'<img ').allMatches(result).length, 2);
    });

    test('改中间一行时其余正文与图片全部保留', () {
      final result = syncIntroToHtml(
          intro, intro.replaceFirst('仅靠火力无法生存。', '光靠火力活不下去。'), html);

      expect(result, contains('光靠火力活不下去。'));
      expect(result, isNot(contains('仅靠火力无法生存。')));
      expect(result, contains('进入东京。活着撤离。'));
      expect(result, contains('社团名：测试社'));
      expect(result, contains('结尾提示行'));
      expect(result, contains('pan.baidu.com'));
      expect(RegExp(r'<img ').allMatches(result).length, 2);
    });

    test('删行后折叠多余 <br>，不留空行', () {
      final result = syncIntroToHtml(
          intro, intro.replaceFirst('仅靠火力无法生存。\n', ''), html);

      expect(result, isNot(contains('仅靠火力无法生存。')));
      expect(result, contains('每次行动都需要不同的策略。<br>百度下载'));
      expect(result, isNot(contains('<br><br>百度下载')));
    });

    test('清空简介时保留全部图片', () {
      final result = syncIntroToHtml(intro, '', html);

      expect(RegExp(r'<img ').allMatches(result).length, 2);
      expect(result, isNot(contains('社团名：测试社')));
      expect(result, isNot(contains('结尾提示行')));
    });

    test('纯文本里的 [图片:xxx] 标记行不会误伤 HTML 中的 <img>', () {
      final result = syncIntroToHtml(
          intro,
          intro.split('\n').where((l) => !l.startsWith('[图片:')).join('\n'),
          html);

      expect(RegExp(r'<img ').allMatches(result).length, 2);
      expect(result, contains('社团名：测试社'));
      expect(result, contains('结尾提示行'));
    });
  });

  test('内容被删空的容器整体移除，不留空壳', () {
    const html = '<p>保留段</p><p>要删掉的段</p>';
    final result = syncIntroToHtml('保留段\n要删掉的段', '保留段', html);

    expect(result, contains('<p>保留段</p>'));
    expect(result, isNot(contains('<p></p>')));
  });

  test('原有的连续 <br> 空行不被误删', () {
    const html = '<p>第一段<br><br>第三段</p>';
    final result = syncIntroToHtml('第一段\n第三段', '第一段改\n第三段', html);

    expect(result, contains('第一段改'));
    expect(result, contains('<br><br>'));
  });
}
