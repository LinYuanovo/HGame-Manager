import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';

void main() {
  group('formatDuration', () {
    test('should format 0 seconds as 0分钟', () {
      expect(formatDuration(0), '0分钟');
    });

    test('should format seconds less than 60', () {
      expect(formatDuration(30), '0分钟');
      expect(formatDuration(59), '0分钟');
    });

    test('should format minutes correctly', () {
      expect(formatDuration(60), '1分钟');
      expect(formatDuration(90), '1分钟');
      expect(formatDuration(3540), '59分钟');
    });

    test('should format hours and minutes correctly', () {
      expect(formatDuration(3600), '1小时0分钟');
      expect(formatDuration(3660), '1小时1分钟');
      expect(formatDuration(7200), '2小时0分钟');
      expect(formatDuration(9000), '2小时30分钟');
    });
  });

  group('Game model', () {
    test('should create game with default playDuration', () {
      final game = Game(path: '/test');
      expect(game.playDuration, 0);
    });

    test('should create game with custom playDuration', () {
      final game = Game(path: '/test', playDuration: 3600);
      expect(game.playDuration, 3600);
    });

    test('should copy game with new playDuration', () {
      final game = Game(path: '/test', playDuration: 0);
      final updatedGame = game.copyWith(playDuration: 3600);
      expect(updatedGame.playDuration, 3600);
    });

    test('should serialize and deserialize playDuration', () {
      final game = Game(path: '/test', playDuration: 3600);
      final map = game.toMap();
      final deserializedGame = Game.fromMap(map);
      expect(deserializedGame.playDuration, 3600);
    });
  });
}
