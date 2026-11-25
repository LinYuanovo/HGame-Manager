import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/widgets/scraped_image_cleanup_dialog.dart';

Future<BuildContext> _boot(
  WidgetTester tester, {
  bool dark = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: const Scaffold(body: SizedBox()),
  ));
  return tester.element(find.byType(Scaffold));
}

void main() {
  testWidgets('显示游戏名和旧配图数量，点击删除返回确认', (tester) async {
    final context = await _boot(tester);
    final result = confirmScrapedImageCleanup(
      context: context,
      gameTitle: '示例游戏',
      imageCount: 3,
    );
    await tester.pumpAndSettle();

    expect(find.text('「示例游戏」有 3 张旧配图，是否保留？'), findsOneWidget);
    expect(find.text('保留后仍可在图库查看。删除会移除这些旧图。'), findsOneWidget);

    await tester.tap(find.text('删除旧图'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });

  for (final action in ['保留旧图', '关闭', 'Escape', '遮罩']) {
    testWidgets('$action 返回保留结果', (tester) async {
      final context = await _boot(tester);
      final result = confirmScrapedImageCleanup(
        context: context,
        gameTitle: '示例游戏',
        imageCount: 3,
      );
      await tester.pumpAndSettle();

      switch (action) {
        case '保留旧图':
          await tester.tap(find.text('保留旧图'));
        case '关闭':
          await tester.tap(find.byTooltip('关闭'));
        case 'Escape':
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        case '遮罩':
          await tester.tapAt(const Offset(8, 8));
      }
      await tester.pumpAndSettle();

      expect(await result, isFalse);
      expect(find.byType(Dialog), findsNothing);
    });
  }

  testWidgets('页面已关闭时返回保留结果', (tester) async {
    final context = await _boot(tester);
    await tester.pumpWidget(const SizedBox());

    expect(
      await confirmScrapedImageCleanup(
        context: context,
        gameTitle: '示例游戏',
        imageCount: 3,
      ),
      isFalse,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}窄窗口和较大字号下可滚动完成选择', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 480);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final context = await _boot(tester, dark: dark, textScale: 2);
      final result = confirmScrapedImageCleanup(
        context: context,
        gameTitle: '用于验证较大字号时自动换行的示例游戏名称',
        imageCount: 12,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in ['保留旧图', '删除旧图']) {
        final button = find.text(label);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text('删除旧图'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });
  }
}
