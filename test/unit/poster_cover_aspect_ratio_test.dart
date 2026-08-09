import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';

void main() {
  group('封面比例设置', () {
    test('未设置时默认使用 16:9', () {
      expect(
        AppSettings.normalizePosterCoverAspectRatio(null),
        closeTo(16 / 9, 0.000001),
      );
    });

    test('四个预设比例保持原值', () {
      for (final ratio in [4 / 3, 16 / 9, 9 / 16, 3 / 4]) {
        expect(
          AppSettings.normalizePosterCoverAspectRatio(ratio),
          closeTo(ratio, 0.000001),
        );
      }
    });

    test('自定义比例限制在 0.5 到 2.0', () {
      expect(AppSettings.normalizePosterCoverAspectRatio(0.1), 0.5);
      expect(AppSettings.normalizePosterCoverAspectRatio(3), 2.0);
    });
  });
}
