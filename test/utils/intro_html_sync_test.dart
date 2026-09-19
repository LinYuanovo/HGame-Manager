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
}
