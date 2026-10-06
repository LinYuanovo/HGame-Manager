import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/html_line_remover.dart';

void main() {
  bool isDownloadLine(String line) {
    final t = line.trim();
    if (t.isEmpty) return false;
    if (t.contains('https://pan.baidu.com/s/1lAU')) return true;
    if (t.contains('https://pan.quark.cn/s/c256')) return true;
    if (t == '解压码007721') return true;
    return false;
  }

  group('HtmlLineRemover', () {
    test('整段简介包在单个 <p> 内时只删下载行，保留正文与图片', () {
      const html = '<p><img src="a.webp"></p>'
          '<p><img src="b.webp"></p>'
          '<p><br>✅社团名：#BLEACHMAMA<br>'
          '▫️名称：死亡撤离<br>'
          '进入东京。活着撤离。<br>'
          'Dead Extraction是一款撤离生存游戏。<br>'
          '解压码007721<br>'
          '百度下载：https://pan.baidu.com/s/1lAUWyu12ifm2gaCKoIEmqA?pwd=brqd<br>'
          '夸克下载：https://pan.quark.cn/s/c256dc8a008e<br>'
          '显示安卓模拟器/PC”的游戏安卓需要用到模拟器游玩</p>';

      final result = HtmlLineRemover.removeMatchedLines(html,
          isRemovableLine: isDownloadLine);

      expect(result, isNotNull);
      expect(result, contains('进入东京。活着撤离。'));
      expect(result, contains('Dead Extraction是一款撤离生存游戏。'));
      expect(result, contains('✅社团名：#BLEACHMAMA'));
      expect(result, contains('显示安卓模拟器/PC'));
      expect(result, contains('src="a.webp"'));
      expect(result, contains('src="b.webp"'));
      expect(result, isNot(contains('pan.baidu.com')));
      expect(result, isNot(contains('pan.quark.cn')));
      expect(result, isNot(contains('解压码007721')));
    });

    test('每行独立顶层节点时按节点删除并清空空壳', () {
      const html = '<p>游戏简介正文</p>'
          '<p>百度下载：https://pan.baidu.com/s/1lAUWyu</p>'
          '<p>尾部说明</p>';

      final result = HtmlLineRemover.removeMatchedLines(html,
          isRemovableLine: isDownloadLine);

      expect(result, isNotNull);
      expect(result, contains('游戏简介正文'));
      expect(result, contains('尾部说明'));
      expect(result, isNot(contains('pan.baidu.com')));
      expect(result, isNot(contains('<p></p>')));
    });

    test('独占一行的网盘标签随链接行一并删除', () {
      const html = '<div>正文<br>百度网盘<br>'
          'https://pan.baidu.com/s/1lAUWyu<br>结尾</div>';

      final result = HtmlLineRemover.removeMatchedLines(
        html,
        isRemovableLine: isDownloadLine,
        removableLabels: {'百度网盘'},
        normalizeLabel: (v) => v.replaceAll(RegExp(r'[：:\s]+$'), '').trim(),
        triggersLabelCleanup: (v) => v.contains('pan.baidu.com'),
      );

      expect(result, isNotNull);
      expect(result, contains('正文'));
      expect(result, contains('结尾'));
      expect(result, isNot(contains('百度网盘')));
      expect(result, isNot(contains('pan.baidu.com')));
    });

    test('文本节点内以 \\n 分行时也能逐行删除', () {
      const html = '<p>第一行\n百度下载：https://pan.baidu.com/s/1lAUWyu\n第二行</p>';

      final result = HtmlLineRemover.removeMatchedLines(html,
          isRemovableLine: isDownloadLine);

      expect(result, isNotNull);
      expect(result, contains('第一行'));
      expect(result, contains('第二行'));
      expect(result, isNot(contains('pan.baidu.com')));
    });

    test('无命中时返回 null', () {
      const html = '<p>纯简介内容<br>没有任何下载信息</p>';
      expect(
        HtmlLineRemover.removeMatchedLines(html,
            isRemovableLine: isDownloadLine),
        isNull,
      );
    });

    test('嵌套结构中命中行被删除', () {
      const html = '<div class="content"><p>介绍段落</p>'
          '<p>解压码007721</p>'
          '<ul><li>https://pan.quark.cn/s/c256</li></ul></div>';

      final result = HtmlLineRemover.removeMatchedLines(html,
          isRemovableLine: isDownloadLine);

      expect(result, isNotNull);
      expect(result, contains('介绍段落'));
      expect(result, isNot(contains('解压码007721')));
      expect(result, isNot(contains('pan.quark.cn')));
    });

    test('与图片同处一行的下载信息不会被删除，避免误伤配图', () {
      const html = '<p><img src="a.webp">https://pan.baidu.com/s/1lAUWyu</p>';

      expect(
        HtmlLineRemover.removeMatchedLines(html,
            isRemovableLine: isDownloadLine),
        isNull,
      );
    });
  });
}
