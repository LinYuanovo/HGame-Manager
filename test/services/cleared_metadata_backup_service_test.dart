import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/services/cleared_metadata_backup_service.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory tempDir;
  late ClearedMetadataBackupService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hgm_cleared_metadata_');
    service = ClearedMetadataBackupService(backupDirectory: tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('保存并刷新完整通关元数据，随后可删除', () async {
    final game = Game(
      id: 42,
      path: r'D:\Games\Example',
      title: 'Example',
      sourceUrl: 'https://example.test/game',
      playCount: 3,
      isPlayed: true,
      isCleared: true,
      coverIndex: 1,
      rating: 4.5,
      review: '初始评论',
      playDuration: 7200,
      tags: [Tag(id: 5, name: '系列', type: Tag.typeSeries)],
      images: [
        GameImage(
          id: 9,
          gameId: 42,
          imagePath: r'D:\Images\cover.png',
          sortOrder: 0,
        ),
      ],
    );

    final file = await service.save(game);
    expect(file.path, path.join(tempDir.path, '42.json'));
    final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final savedGame = saved['game'] as Map<String, dynamic>;
    expect(saved['version'], 1);
    expect(savedGame['is_cleared'], 1);
    expect(savedGame['play_count'], 3);
    expect(savedGame['play_duration'], 7200);
    expect(savedGame['cover_index'], 1);
    expect(savedGame['rating'], 4.5);
    expect(savedGame['review'], '初始评论');
    expect((saved['tags'] as List).single['name'], '系列');
    expect(
        (saved['images'] as List).single['image_path'], r'D:\Images\cover.png');

    await service.refresh(game.copyWith(rating: 5.0, review: '删除前最新评论'));
    final refreshed =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final refreshedGame = refreshed['game'] as Map<String, dynamic>;
    expect(refreshedGame['rating'], 5.0);
    expect(refreshedGame['review'], '删除前最新评论');

    expect(await service.find(game), isNotNull);
    await service.delete(game);
    expect(await file.exists(), isFalse);
  });
}
