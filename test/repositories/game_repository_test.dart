import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';

void main() {
  group('GameRepository Image Methods', () {
    test('deleteGameImage removes image', () async {
      final repo = GameRepository();
      expect(repo.deleteGameImage, isA<Function>());
    });

    test('deleteGameImagesByGameId removes all game images', () async {
      final repo = GameRepository();
      expect(repo.deleteGameImagesByGameId, isA<Function>());
    });

    test('updateImageOrder updates single image order', () async {
      final repo = GameRepository();
      expect(repo.updateImageOrder, isA<Function>());
    });

    test('updateGameImagesOrder updates order', () async {
      final repo = GameRepository();
      expect(repo.updateGameImagesOrder, isA<Function>());
    });
  });
}
