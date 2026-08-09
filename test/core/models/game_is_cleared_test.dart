import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';

void main() {
  group('Game.isCleared', () {
    test('数据库序列化和反序列化保留通关状态', () {
      final game = Game(
        id: 7,
        path: r'D:\Games\Example',
        title: 'Example',
        isCleared: true,
        clearedBackupPath: r'D:\Sorted\Cleared\Backup\Example',
      );

      final map = game.toMap();
      expect(map['is_cleared'], 1);
      expect(map['cleared_backup_path'], r'D:\Sorted\Cleared\Backup\Example');
      final restored = Game.fromMap(map);
      expect(restored.isCleared, isTrue);
      expect(restored.clearedBackupPath, r'D:\Sorted\Cleared\Backup\Example');
    });

    test('旧数据缺少字段时默认未通关，copyWith 可更新状态', () {
      final legacy = Game.fromMap({
        'id': 8,
        'path': r'D:\Games\Legacy',
      });

      expect(legacy.isCleared, isFalse);
      expect(legacy.clearedBackupPath, isNull);
      expect(legacy.copyWith(isCleared: true).isCleared, isTrue);
    });
  });
}
