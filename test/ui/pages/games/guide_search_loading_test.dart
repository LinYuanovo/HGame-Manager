import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/services/fan2d_service.dart';
import 'package:hgame_manager/ui/pages/games/guide_search_dialog.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/widgets/app_dropdown.dart';

void main() {
  Future<void> openSearch(WidgetTester tester, _DelayedGuides service,
      {ValueChanged<String?>? onResult}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [fan2dServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              final result = await showAppDialog<String>(
                context: context,
                builder: (_) => GuideSearchDialog(
                  game: Game(path: 'sample'),
                  initialKeyword: '攻略',
                ),
              );
              onResult?.call(result);
            },
            child: const Text('打开攻略'),
          );
        })),
      ),
    ));
    await tester.tap(find.text('打开攻略'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pilipili'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2DFan').last);
    await tester.pumpAndSettle();
  }

  testWidgets('攻略搜索等待时回车不重复请求，来源保持当前请求一致', (tester) async {
    final service = _DelayedGuides();
    await openSearch(tester, service);
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.showKeyboard(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(service.searchCalls, 1);
    expect(
        tester
            .widget<AppDropdown<GuideSource>>(
                find.byType(AppDropdown<GuideSource>))
            .onChanged,
        isNull);
    service.searchResults.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(AppSkeleton), findsNothing);
    expect(find.text('无搜索结果'), findsOneWidget);
  });

  testWidgets('攻略正文获取保持结果并显示忙碌，失败后可重试并只返回一次', (tester) async {
    final service = _DelayedGuides();
    final returned = <String?>[];
    await openSearch(tester, service, onResult: returned.add);
    await tester.tap(find.text('搜索'));
    service.searchResults.complete([
      Fan2dGuideResult(
          title: '示例攻略', guideUrl: 'https://example.invalid/guide'),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例攻略'));
    await tester.pump();
    expect(find.text('正在获取攻略及图片…'), findsOneWidget);
    expect(find.text('示例攻略'), findsOneWidget);
    await tester.tap(find.text('示例攻略'));
    await tester.pump();
    expect(service.contentCalls, 1);
    service.content.completeError(StateError('内容请求失败'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('正在获取攻略及图片…'), findsNothing);
    expect(find.text('示例攻略'), findsOneWidget);
    service.content = Completer<Fan2dGuideScrapeResult>();
    await tester.tap(find.text('示例攻略'));
    service.content.complete(Fan2dGuideScrapeResult(content: '攻略正文'));
    await tester.pumpAndSettle();
    expect(service.contentCalls, 2);
    expect(returned, ['攻略正文']);
    expect(find.text('打开攻略'), findsOneWidget);
  });

  testWidgets('关闭攻略窗口时到达的结果不再弹出选择窗口', (tester) async {
    final service = _DelayedGuides();
    final returned = <String?>[];
    await openSearch(tester, service, onResult: returned.add);
    await tester.tap(find.text('搜索'));
    service.searchResults.complete([
      Fan2dGuideResult(
          title: '示例攻略', guideUrl: 'https://example.invalid/guide'),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例攻略'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    service.content.complete(Fan2dGuideScrapeResult(walkthroughs: [
      Fan2dWalkthrough(title: '攻略一', url: 'https://example.invalid/one'),
      Fan2dWalkthrough(title: '攻略二', url: 'https://example.invalid/two'),
    ]));
    await tester.pumpAndSettle();
    expect(returned, [null]);
    expect(find.text('选择攻略'), findsNothing);
    expect(find.text('打开攻略'), findsOneWidget);
  });

  testWidgets('改选另一条攻略时迟到的正文不覆盖当前选择', (tester) async {
    final service = _DelayedGuides();
    final returned = <String?>[];
    await openSearch(tester, service, onResult: returned.add);
    await tester.tap(find.text('搜索'));
    service.searchResults.complete([
      Fan2dGuideResult(title: '攻略甲', guideUrl: 'https://example.invalid/one'),
      Fan2dGuideResult(title: '攻略乙', guideUrl: 'https://example.invalid/two'),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('攻略甲'));
    await tester.pump();
    final earlier = service.content;
    service.content = Completer<Fan2dGuideScrapeResult>();
    await tester.tap(find.text('攻略乙'));
    await tester.pump();
    expect(service.contentCalls, 2);
    earlier.complete(Fan2dGuideScrapeResult(content: '甲正文'));
    await tester.pump();
    expect(returned, isEmpty);
    service.content.complete(Fan2dGuideScrapeResult(content: '乙正文'));
    await tester.pumpAndSettle();
    expect(returned, ['乙正文']);
  });
}

class _DelayedGuides extends Fake implements Fan2dService {
  final searchResults = Completer<List<Fan2dGuideResult>>();
  var content = Completer<Fan2dGuideScrapeResult>();
  var searchCalls = 0;
  var contentCalls = 0;

  @override
  Future<List<Fan2dGuideResult>> searchGuides(String keyword) {
    searchCalls++;
    return searchResults.future;
  }

  @override
  Future<Fan2dGuideScrapeResult> scrapeGuideContent(String url) {
    contentCalls++;
    return content.future;
  }
}
