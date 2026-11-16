import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/models/scrape_review_item.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/scrape_review_service.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';
import 'package:hgame_manager/ui/pages/scraper/scrape_review_dialog.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}确认操作继承应用字体并使用统一按钮规格', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const fontFamily = '测试应用字体';
      final items = [
        ScrapeReviewItem(
            game: Game(path: '候选游戏', title: '原游戏'),
            candidate: GameInfo(title: '候选标题', sourceUrl: '')),
        ScrapeReviewItem(
            game: Game(path: '失败游戏', title: '失败游戏'), fetchError: '抓取失败'),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: dark
            ? AppTheme.darkTheme(fontFamily: fontFamily)
            : AppTheme.lightTheme(fontFamily: fontFamily),
        home: Scaffold(
            body: ScrapeReviewDialog(
                items: items,
                configs: const ScrapeModeConfigs(configs: {}),
                service: ScrapeReviewService(
                    repository: GameRepository(),
                    tagRepository: TagRepository()))),
      ));
      await tester.pumpAndSettle();
      for (final label in ['全选', '清空选择', '选择放弃和失败项']) {
        final text = find.text(label);
        final style = DefaultTextStyle.of(tester.element(text)).style;
        expect(style.fontFamily, fontFamily, reason: label);
        expect(style.fontSize, GlassConstants.fontControl, reason: label);
        final button =
            find.ancestor(of: text, matching: find.byType(OutlinedButton));
        expect(button, findsOneWidget);
        expect(tester.getSize(button).height,
            greaterThanOrEqualTo(LayoutConstants.controlHeight));
      }
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);
      await tester.tap(find.text('清空选择'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 项'), findsOneWidget);
      await tester.tap(find.text('选择放弃和失败项'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${dark ? '深色' : '浅色'}受限候选明确提示来源限制且仍可确认', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final restricted = ScrapeReviewItem(
          game: Game(path: '受限游戏', title: '原游戏'),
          candidate: GameInfo(
              title: '受限候选标题',
              isDlsiteUserOnly: true,
              sourceUrl: 'https://example.test/restricted'));
      final normal = ScrapeReviewItem(
          game: Game(path: '普通游戏', title: '普通游戏'),
          candidate: GameInfo(
              title: '普通候选标题',
              description: '完整简介',
              sourceUrl: 'https://example.test/normal'));
      await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
        home: Scaffold(
            body: ScrapeReviewDialog(
                items: [restricted, normal],
                configs: const ScrapeModeConfigs(configs: {}),
                service: ScrapeReviewService(
                    repository: GameRepository(),
                    tagRepository: TagRepository()))),
      ));
      await tester.pumpAndSettle();

      final notice = find.text(GameInfo.dlsiteUserOnlyNotice);
      expect(notice, findsOneWidget);
      await tester.ensureVisible(notice);
      await tester.pumpAndSettle();
      final noticeText = tester.widget<Text>(notice);
      expect(noticeText.style?.color,
          AppTheme.getTextPrimary(tester.element(notice)));
      expect(noticeText.style?.fontSize, GlassConstants.fontBody);
      expect(find.text('本次未取得来源完整简介。'), findsOneWidget);
      expect(find.text('本次未取得简介，请核对来源。'), findsNothing);
      expect(restricted.canKeep, isTrue);

      await tester.tap(find.byKey(const ValueKey('keep-review-item')));
      await tester.pumpAndSettle();
      expect(restricted.decision, ScrapeReviewDecision.keep);
      expect(restricted.applied, isFalse);
      expect(notice, findsNothing);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);

      await tester.tap(find.byTooltip('下一项'));
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      expect(find.text('完整简介'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
