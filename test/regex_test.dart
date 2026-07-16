import '../lib/scraper/parse_utils.dart';

void main() {
  final testContent = '''本帖最后由 玉枝 于 2026-2-11 16:01 编辑

游戏介绍:
《女祭司之眼1.3》官方中文版，一款充满动态CG的SLG同人游戏。

化身女祭司，体验第一章"泉迷乱影"的剧情。
虽然制作略显粗糙，但满满都是作者的心血！
御姐、中出等元素应有尽有，助你获得独特的游戏体验。
遇到卡顿？别担心，文件夹内有解决方法！快来体验吧！

更新日志：

V1.3
本次更新内容：
1.更换制作引擎，从RPG developer bakin更换到了unity
2.更新了新的开始画面，运用了spine的技术，实现了动态立绘
3.更新了六章故事集
3.1重置了神隐之夜
3.2重置了靡音暗巷，并且额外加了5张新CG，以及配套的新前置故事
3.3重置了觅春韵，增加了新的3D场景尝试
3.4新故事集，河光映残阳
3.5新故事集，神隐之夜续
3.6新故事集，温蒂的净域温潮
4.片段回忆改动，现在能看所以故事内容的CG
5.从线性流程改成关卡制，并新增选择关卡页面
6.对话系统大改，现在支持跳过，隐藏界面，自动剧情和调整文字大小等功能
安卓：（等热更新）

已补档

飞猫云优惠码：VRX9JM

解压密码：飞雪ACG论坛@玉枝''';

  print('=== 测试 filterCommonNoise ===');
  print('过滤前:');
  print(testContent);
  print('\n${'=' * 80}\n');

  final filtered = filterCommonNoise(testContent);
  print('过滤后:');
  print(filtered);
  print('\n${'=' * 80}\n');

  // 测试单个正则
  print('=== 测试单个正则 ===');

  final regex1 = RegExp(r'本帖最后由\s*\S+\s*于\s*\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}\s*编辑');
  print('正则1 (本帖最后由...编辑): ${regex1.hasMatch(testContent)}');
  if (regex1.hasMatch(testContent)) {
    print('  匹配: ${regex1.firstMatch(testContent)!.group(0)}');
  }

  final regex2 = RegExp(r'[^\n]*已补档[^\n]*');
  print('正则2 (已补档): ${regex2.hasMatch(testContent)}');
  if (regex2.hasMatch(testContent)) {
    print('  匹配: ${regex2.firstMatch(testContent)!.group(0)}');
  }

  final regex3 = RegExp(r'[^\n]*飞猫云[^\n]*');
  print('正则3 (飞猫云): ${regex3.hasMatch(testContent)}');
  if (regex3.hasMatch(testContent)) {
    print('  匹配: ${regex3.firstMatch(testContent)!.group(0)}');
  }

  final regex4 = RegExp(r'[^\n]*(解压码|解压密码|解压口令)[^\n]*');
  print('正则4 (解压密码): ${regex4.hasMatch(testContent)}');
  if (regex4.hasMatch(testContent)) {
    print('  匹配: ${regex4.firstMatch(testContent)!.group(0)}');
  }
}
