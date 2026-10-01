import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/services/scrape_apply_service.dart';

void main() {
  group('stripVersionFromTitle', () {
    test('去除精确版本号', () {
      expect(
        ScrapeApplyService.stripVersionFromTitle('禁闭乐园 V1.5 中文版', 'V1.5'),
        '禁闭乐园 中文版',
      );
    });

    test('去除通用版本号模式', () {
      expect(
        ScrapeApplyService.stripVersionFromTitle('游戏名 ver2.1 完整版'),
        '游戏名 完整版',
      );
    });

    test('无版本号时原样返回', () {
      expect(
        ScrapeApplyService.stripVersionFromTitle('普通标题'),
        '普通标题',
      );
    });
  });

  group('resolveCategoryName', () {
    test('按优先级匹配分类', () {
      final tags = [
        Tag(name: 'slg', type: Tag.typeCustom),
        Tag(name: 'RPG', type: Tag.typeCustom),
      ];
      expect(ScrapeApplyService.resolveCategoryName(tags), 'RPG');
    });

    test('无匹配时返回 Unclassified', () {
      expect(
        ScrapeApplyService.resolveCategoryName(
            [Tag(name: '汉化', type: Tag.typeCustom)]),
        'Unclassified',
      );
    });

    test('空标签返回 Unclassified', () {
      expect(ScrapeApplyService.resolveCategoryName([]), 'Unclassified');
    });
  });
}
