import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/ui/widgets/markdown_editor.dart';
import 'package:hgame_manager/ui/widgets/picture_motion.dart';
import 'package:hgame_manager/ui/widgets/rating_input.dart';
import 'package:hgame_manager/ui/widgets/result_location.dart';
import 'package:hgame_manager/ui/widgets/layout_reflow.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/pages/games/detail_search_bar.dart';

void main() {
  testWidgets('中文组合提交即使文字不变也触发正文搜索', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final searches = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DetailSearchBar(
      controller: controller,
      matches: const [],
      currentMatchIndex: -1,
      hasSearched: false,
      onNext: () {},
      onPrevious: () {},
      onSearch: searches.add,
      onClose: () {},
    ))));
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '中文',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    ));
    await tester.pump();
    expect(searches, isEmpty);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: '中文',
      selection: TextSelection.collapsed(offset: 2),
    ));
    await tester.pump();
    expect(searches, ['中文']);
    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    expect(searches, ['中文']);
  });

  testWidgets('评分拖动时星级画面跟随已提交的分值', (tester) async {
    final rating = ValueNotifier(2.0);
    addTearDown(rating.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: ValueListenableBuilder(
          valueListenable: rating,
          builder: (_, value, __) => RatingInput(
              value: value, onChanged: (next) => rating.value = next)),
    ))));
    final rect = tester.getRect(find.byType(RatingInput));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: rect.centerLeft + const Offset(20, 0));
    await mouse.moveTo(rect.centerLeft + const Offset(22, 0));
    await tester.pump();
    await mouse.down(rect.centerLeft + const Offset(22, 0));
    await mouse.moveTo(rect.center);
    await mouse.moveTo(rect.centerRight - const Offset(1, 0));
    await tester.pump();
    expect(rating.value, 5);
    expect(find.byIcon(Icons.star), findsNWidgets(5));
    await mouse.up();
    await mouse.removePointer();
  });

  testWidgets('补位动画中的点击跟随当前绘制位置', (tester) async {
    final shifted = ValueNotifier(false);
    addTearDown(shifted.dispose);
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder(
      valueListenable: shifted,
      builder: (_, moved, __) => Padding(
        padding: EdgeInsets.only(left: moved ? 100 : 0),
        child: LayoutReflow(
            revision: moved,
            child: SizedBox(
                width: 300,
                height: 80,
                child: Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => tapped++,
                      child: const SizedBox(
                          width: 60,
                          height: 60,
                          child: ColoredBox(
                              color: Colors.blue,
                              key: ValueKey('moving-button'))),
                    )))),
      ),
    ))));
    await tester.pumpAndSettle();
    shifted.value = true;
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester
        .tapAt(tester.getCenter(find.byKey(const ValueKey('moving-button'))));
    expect(tapped, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('返回分类卡后的焦点可直接用回车再次打开', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GlassCard(
                focusNode: focus,
                onTap: () => opened++,
                child: const Text('分类')))));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
  testWidgets('布局切换中再次切换和卸载会清除飞行层并恢复来源', (tester) async {
    final origins = PictureOrigins();
    final right = ValueNotifier(false);
    addTearDown(right.dispose);
    addTearDown(() => origins.cancelFlight(restore: false));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => Column(children: [
                      TextButton(
                          onPressed: () {
                            origins.moveAcrossLayout(
                                context,
                                '封面',
                                const ColoredBox(
                                    key: ValueKey('flight'),
                                    color: Colors.blue));
                            right.value = !right.value;
                          },
                          child: const Text('切换布局')),
                      ValueListenableBuilder(
                          valueListenable: right,
                          builder: (_, moved, __) => Align(
                              alignment: moved
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: PictureOrigin(
                                  origins: origins,
                                  identity: '封面',
                                  child: const SizedBox(
                                      width: 100,
                                      height: 90,
                                      child: Text('封面'))))),
                    ])))));
    await tester.tap(find.text('切换布局'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('切换布局'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flight')), findsNothing);
    expect(origins.visible('封面'), isNotNull);
    await tester.tap(find.text('切换布局'));
    await tester.pump();
    origins.cancelFlight(restore: false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('列表补位保持被移动项的文本编辑状态', (tester) async {
    final shifted = ValueNotifier(false);
    addTearDown(shifted.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ValueListenableBuilder(
                valueListenable: shifted,
                builder: (_, move, __) => Column(children: [
                      if (!move) const SizedBox(height: 80),
                      LayoutReflow(
                          key: const ValueKey('editor'),
                          revision: move,
                          child: const TextField()),
                    ])))));
    await tester.enterText(find.byType(TextField), '保持这段输入');
    shifted.value = true;
    await tester.pumpAndSettle();
    expect(find.text('保持这段输入'), findsOneWidget);
  });
  testWidgets('图片翻页后返回当前来源，来源离屏与开合中断安全退出', (tester) async {
    final origins = PictureOrigins();
    final selected = ValueNotifier('甲');
    final hidden = ValueNotifier(false);
    addTearDown(selected.dispose);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => Column(children: [
                      for (final name in ['甲', '乙'])
                        ValueListenableBuilder(
                            valueListenable: hidden,
                            builder: (_, offstage, __) => Offstage(
                                  offstage: offstage && name == '乙',
                                  child: PictureOrigin(
                                      origins: origins,
                                      identity: name,
                                      onOpen: (origin) {
                                        selected.value = name;
                                        showPictureDialog<void>(
                                            context,
                                            (context) => ValueListenableBuilder(
                                                  valueListenable: selected,
                                                  builder: (context, page, _) =>
                                                      Dialog(
                                                          child: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                        pictureHero(
                                                            context,
                                                            origins.visible(
                                                                page,
                                                                preferred:
                                                                    origin),
                                                            SizedBox(
                                                                width: 280,
                                                                height: 180,
                                                                child: Text(
                                                                    '大图$page'))),
                                                        TextButton(
                                                            onPressed: () =>
                                                                selected.value =
                                                                    '乙',
                                                            child: const Text(
                                                                '下一张')),
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context),
                                                            child: const Text(
                                                                '关闭图片')),
                                                      ])),
                                                ));
                                      },
                                      child: SizedBox(
                                          width: 100,
                                          height: 60,
                                          child: Text(name))),
                                )),
                    ])))));
    await tester.tap(find.text('甲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一张'));
    await tester.pump();
    final target = tester.widget<Hero>(
        find.ancestor(of: find.text('大图乙'), matching: find.byType(Hero)));
    expect(target.tag, origins.visible('乙'));
    hidden.value = true;
    await tester.pump();
    await tester.tap(find.text('关闭图片'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.text('甲'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('甲'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片展开途中启用减少动效立即收束，关闭仍返回当前页', (tester) async {
    final reduced = ValueNotifier(false);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(ValueListenableBuilder(
        valueListenable: reduced,
        builder: (_, disabled, __) => MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: disabled),
                  child: child!),
              home: Scaffold(
                  body: Builder(
                      builder: (context) => TextButton(
                          onPressed: () => showPictureDialog(
                              context,
                              (context) => Dialog(
                                    child: TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('关闭')),
                                  )),
                          child: const Text('打开')))),
            )));
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 35));
    reduced.value = true;
    await tester.pump();
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.byType(Dialog)))!;
    expect(route.animation!.isCompleted, isTrue);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
  });

  testWidgets('离屏定位能找到长列表后半段的实际条目', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            height: 300,
            child: ListView.builder(
              controller: scroll,
              itemCount: 200,
              itemBuilder: (_, index) => SizedBox(
                  height: index % 3 == 0 ? 110 : 38, child: Text('记录$index')),
            ))));
    final done = seekListIndex(scroll, 173);
    await tester.pumpAndSettle();
    await done;
    expect(find.text('记录173').hitTestable(), findsOneWidget);
  });

  testWidgets('Markdown 预览往返保留中文选区和编辑焦点', (tester) async {
    final text = TextEditingController(text: '第一行\n第二行中文\n第三行');
    addTearDown(text.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MarkdownEditor(controller: text, imagePaths: const []))));
    await tester.tap(find.byType(TextField));
    text.selection = const TextSelection(baseOffset: 2, extentOffset: 10);
    await tester.pump();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(
        text.selection, const TextSelection(baseOffset: 2, extentOffset: 10));
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue);
  });

  testWidgets('评分悬停只预览，点击和键盘才提交', (tester) async {
    final rating = ValueNotifier(2.0);
    addTearDown(rating.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: ValueListenableBuilder(
                    valueListenable: rating,
                    builder: (_, value, __) => RatingInput(
                        value: value,
                        onChanged: (next) => rating.value = next))))));
    final region = tester.getRect(find.byType(RatingInput));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: region.centerRight - const Offset(2, 0));
    await tester.pump();
    expect(rating.value, 2);
    await tester.tapAt(region.center);
    await tester.pump();
    final clicked = rating.value;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(rating.value, clicked + .5);
    await mouse.removePointer();
  });
}
