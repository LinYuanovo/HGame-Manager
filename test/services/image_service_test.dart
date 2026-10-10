import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/image_service.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:path/path.dart' as path;

void main() {
  group('ImageService', () {
    test('getImageStorageDir returns valid path', () async {
      final service = ImageService();
      final dir = await service.getImageStorageDir();
      expect(dir, isNotEmpty);
      expect(dir, contains('game_images'));
    });

    test('URL 图片下载到游戏 HGMDatas/images 目录', () async {
      final tempDir = await Directory.systemTemp.createTemp('hgm_image_test_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add([1, 2, 3, 4]);
        await request.response.close();
      });

      try {
        final service = ImageService();
        final imagePath = await service.downloadImageFromUrlToGameDir(
          'http://${server.address.host}:${server.port}/cover.png',
          tempDir.path,
        );

        expect(imagePath, isNotNull);
        expect(
          File(imagePath!).parent.path,
          GameDataPaths.imagesDir(tempDir.path).path,
        );
        // 手动添加图使用 manual_ 序号命名规则
        expect(path.basename(imagePath), 'manual_1.png');
        expect(await File(imagePath).readAsBytes(), [1, 2, 3, 4]);
      } finally {
        await server.close(force: true);
        await tempDir.delete(recursive: true);
      }
    });

    test('本地图片复制到游戏目录使用 manual_ 递增序号', () async {
      final tempDir = await Directory.systemTemp.createTemp('hgm_image_test_');
      final source = File('${tempDir.path}${Platform.pathSeparator}src.png');
      await source.writeAsBytes([9]);

      try {
        final service = ImageService();
        final first = await service.copyImageToGameDir(source.path, tempDir.path);
        final second = await service.copyImageToGameDir(source.path, tempDir.path);

        expect(path.basename(first), 'manual_1.png');
        expect(path.basename(second), 'manual_2.png');
        expect(await File(first).exists(), isTrue);
        expect(await File(second).exists(), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
