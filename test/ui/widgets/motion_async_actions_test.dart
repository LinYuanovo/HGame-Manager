import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/guide_window_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/favorites/favorites_page.dart';
import 'package:hgame_manager/ui/pages/settings/guide_hotkey_dialog.dart';

class _EmptySettings extends Fake implements AppSettings {
  @override
  String? getString(String key) => null;
  @override
  bool? getBool(String key) => null;
  @override
  int? getInt(String key) => null;
  @override
  double? getDouble(String key) => null;
}

class _PendingTags extends Fake implements TagRepository {
  final finished = Completer<void>();
  int calls = 0;
  @override
  Future<void> toggleFavorite(int tagId, bool value) {
    calls++;
    return finished.future;
  }
}

class _PendingHotkeys extends Fake implements GuideWindowService {
  final finished = Completer<void>();
  int resets = 0;
  @override
  HotKey loadHotkey(String key) => GuideWindowService.defaultHotkeys()[key]!;
  @override
  Future<void> resetHotkeys() {
    resets++;
    return finished.future;
  }

  @override
  Future<String?> registerHotkeys() async => null;
}

void main() {
  testWidgets('取消分类收藏等待期间仅提交一次，失败后恢复操作', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1150, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _PendingTags();
    await tester.pumpWidget(ProviderScope(overrides: [
      sharedPreferencesProvider.overrideWithValue(_EmptySettings()),
      tagRepositoryProvider.overrideWithValue(repository),
      favoriteGamesProvider.overrideWith((ref) async => []),
      favoriteTagsProvider.overrideWith((ref) async => [
            Tag(id: 1, name: '冒险', type: Tag.typeCustom, isFavorite: true),
          ]),
    ], child: const MaterialApp(home: Scaffold(body: FavoritesPage()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类'));
    await tester.pumpAndSettle();
    final favorite = find.widgetWithIcon(IconButton, Icons.favorite);
    final action = tester.widget<IconButton>(favorite).onPressed!;
    action();
    action();
    await tester.pump();
    expect(repository.calls, 1);
    expect(tester.widget<IconButton>(favorite).onPressed, isNull);
    repository.finished.completeError(StateError('写入失败'));
    await tester.pumpAndSettle();
    expect(find.text('冒险'), findsOneWidget);
    expect(tester.widget<IconButton>(favorite).onPressed, isNotNull);
  });

  testWidgets('恢复默认快捷键期间锁定录制和重复重置，失败后可重试', (tester) async {
    final service = _PendingHotkeys();
    await tester.pumpWidget(ProviderScope(overrides: [
      guideWindowServiceProvider.overrideWithValue(service),
    ], child: const MaterialApp(home: Scaffold(body: GuideHotkeyDialog()))));
    await tester.pumpAndSettle();
    final reset = find.widgetWithText(TextButton, '恢复默认');
    final action = tester.widget<TextButton>(reset).onPressed!;
    action();
    action();
    await tester.pump();
    expect(service.resets, 1);
    expect(tester.widget<TextButton>(reset).onPressed, isNull);
    for (final button in tester
        .widgetList<TextButton>(find.widgetWithText(TextButton, '修改'))) {
      expect(button.onPressed, isNull);
    }
    service.finished.completeError(StateError('写入失败'));
    await tester.pumpAndSettle();
    expect(find.textContaining('恢复默认快捷键失败'), findsOneWidget);
    expect(tester.widget<TextButton>(reset).onPressed, isNotNull);
  });
}
