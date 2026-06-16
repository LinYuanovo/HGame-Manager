import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/image_service.dart';

void main() {
  group('ImageService', () {
    test('getImageStorageDir returns valid path', () async {
      final service = ImageService();
      final dir = await service.getImageStorageDir();
      expect(dir, isNotEmpty);
      expect(dir, contains('game_images'));
    });
  });
}
