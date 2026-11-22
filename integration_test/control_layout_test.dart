import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/backup_entry.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/services/backup_service.dart';
import 'package:hgame_manager/ui/pages/games/save_management_dialog.dart';
import 'package:hgame_manager/ui/pages/scraper/scraper_page.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

class _Backups extends Fake implements BackupService {
  @override
  Future<List<BackupEntry>> listBackups(String gamePath) async => [];

  @override
  Future<BackupEntry?> autoImportSaveFolder(String gamePath) async => null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('刮削控件等高，存档按钮在不同窗口和字号下完整可见', (tester) async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1200, 760));
    final boundary = GlobalKey();
    final issues = <String>[];
    Future<void> show(Widget page, double width, double scale) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [backupServiceProvider.overrideWithValue(_Backups())],
        child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
            width: width,
            height: 650,
            child: RepaintBoundary(
                key: boundary,
                child: Builder(
                    builder: (context) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              textScaler: TextScaler.linear(scale),
                              disableAnimations: true),
                          child: page,
                        ))),
          ))),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name, Rect area) async {
      const output = String.fromEnvironment('CONTROL_LAYOUT_EVIDENCE');
      if (output.isEmpty) return;
      final box =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final offset = box.localToGlobal(Offset.zero);
      final layer = box.debugLayer! as OffsetLayer;
      final image = await layer.toImage(area.shift(-offset));
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    for (final scale in [1.0, 1.5, 2.0]) {
      await show(const ScraperPage(), 1100, scale);
      Rect surface(String label, Type type) => tester.getRect(find
          .ancestor(
            of: find.text(label),
            matching: find.byType(type),
          )
          .first);
      final rects = [
        surface('空闲', GlassContainer),
        surface('扫描游戏库', Material),
        surface('刮削元数据', Material),
        surface('线程数', GlassContainer)
      ];
      debugPrint('刮削控件 $scale 倍：${rects.map((rect) => rect.height).toList()}');
      if (rects.any((rect) => (rect.height - rects.first.height).abs() > .5))
        issues.add('刮削控件高度不一致 $scale');
      if (scale == 1)
        await capture(
            'scraper', rects.first.expandToInclude(rects.last).inflate(8));
    }

    for (final (width, scale) in [
      (1100.0, 1.0),
      (640.0, 1.0),
      (640.0, 1.5),
      (640.0, 2.0)
    ]) {
      await show(
          SaveManagementDialog(game: Game(path: 'sample', title: '布局检查')),
          width,
          scale);
      final dialog = tester.getRect(find
          .ancestor(of: find.text('暂无备份'), matching: find.byType(DecoratedBox))
          .first);
      final bounds = <Rect>[];
      void checkLabel(String label) {
        final finder = find.text(label);
        final text = tester.renderObject<RenderParagraph>(finder);
        final rect = tester.getRect(finder);
        if (text.didExceedMaxLines ||
            finder.hitTestable().evaluate().isEmpty ||
            !dialog.contains(rect.topLeft) ||
            !dialog.contains(rect.bottomRight))
          issues.add('$width/$scale 标签不可见：$label');
        for (final box in text.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length))) {
          if (!(Offset.zero & text.size)
              .inflate(1)
              .contains(box.toRect().bottomRight))
            issues.add('$width/$scale 文字超出边界：$label');
        }
      }

      for (final label in [
        '打开存档',
        '打开备份',
        '导入存档',
        '下载存档',
        '备份存档',
        '云端备份',
        '批量删除'
      ]) {
        checkLabel(label);
        bounds.add(tester.getRect(find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first));
      }
      final rows = bounds.map((rect) => rect.top.round()).toSet().length;
      debugPrint('存档管理 ${dialog.width} 宽、$scale 倍：$rows 行');
      if (width == 640 && scale == 1.5)
        await capture(
            'saves',
            bounds
                .reduce((first, next) => first.expandToInclude(next))
                .inflate(6)
                .intersect(dialog));
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      for (final label in ['选择', '保存', '取消']) {
        checkLabel(label);
      }
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }
    expect(issues, isEmpty, reason: issues.join('\n'));
  });
}
