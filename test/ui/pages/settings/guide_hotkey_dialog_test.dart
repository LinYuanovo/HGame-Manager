import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/services/guide_window_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/settings/guide_hotkey_dialog.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

void main() {
  late Directory tempDir;
  late AppSettings prefs;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('guide_hotkey_test_');
    prefs = await AppSettings.loadFromFileForTest(
        '${tempDir.path}${Platform.pathSeparator}settings.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    AppSettings.invalidateCache();
  });

  Widget buildDialog() {
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: Scaffold(body: GuideHotkeyDialog())),
    );
  }

  testWidgets('录制时按下修饰键不完成，再按普通键才组合完成', (tester) async {
    await tester.pumpWidget(buildDialog());
    await tester.pumpAndSettle();

    // 点击第一行（开启/关闭浮窗）的「修改」
    await tester.tap(find.text('修改').first);
    await tester.pump();
    expect(find.text('请按下按键组合…'), findsOneWidget);

    // 只按下 Ctrl：不应完成录制
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('…'), findsOneWidget);

    // 再按 A：完成 Ctrl+A 组合并保存
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final saved = prefs.getString(GuideWindowService.hotkeyToggleKey);
    expect(saved, isNotNull);
    final hotKey =
        HotKey.fromJson(jsonDecode(saved!) as Map<String, dynamic>);
    expect(hotKey.physicalKey, PhysicalKeyboardKey.keyA);
    expect(hotKey.modifiers, contains(HotKeyModifier.control));

    // 冲刷 AppSettings 防抖写入的计时器，避免测试结束时仍有 pending Timer
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('无修饰键的普通键被拒绝并继续录制，Esc 取消录制', (tester) async {
    await tester.pumpWidget(buildDialog());
    await tester.pumpAndSettle();

    await tester.tap(find.text('修改').first);
    await tester.pump();

    // 直接按 A（无修饰键）：拒绝且继续录制
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(prefs.getString(GuideWindowService.hotkeyToggleKey), isNull);

    // Esc 取消录制，回到展示状态
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('修改'), findsNWidgets(4));

    // 冲刷提示 toast 的计时器，避免测试结束时仍有 pending Timer
    await tester.pump(const Duration(seconds: 4));
  });
}

