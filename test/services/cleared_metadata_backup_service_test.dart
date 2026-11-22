import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/services/cleared_metadata_backup_service.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
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
      final resolved = path.normalize(path.absolute(tempDir.path));
      if (!path.isWithin(
              path.normalize(path.absolute(Directory.systemTemp.path)),
              resolved) ||
          !path.basename(resolved).startsWith('hgm_cleared_metadata_')) {
        throw StateError('临时目录超出测试范围');
      }
      await tempDir.delete(recursive: true);
    }
  });

  test('删除游戏元数据后刷新备份仍保留译文、原文和富文本', () async {
    final game = Game(
        id: 7,
        path: path.join(tempDir.path, 'game'),
        title: '村庄',
        isCleared: true);
    final metadata = {
      'title': '村庄',
      'intro_html': '<p>探索</p>',
      'translation': {
        'original': {'title': 'Village', 'intro_html': '<p>Explore</p>'},
        'provider': 'llm',
      },
    };
    await GameDataPaths.ensureDataDir(game.path);
    final source = GameDataPaths.metadataFile(game.path);
    await source.writeAsString(jsonEncode(metadata));
    final backup = await service.save(game);
    expect(jsonDecode(await backup.readAsString())['metadata'], metadata);
    await source.delete();
    await service.refresh(game.copyWith(review: '删除后更新评论'));
    final refreshed = jsonDecode(await backup.readAsString());
    expect(refreshed['metadata'], metadata);
    expect(refreshed['game']['review'], '删除后更新评论');
    expect(await service.loadMetadata(game), metadata);
    await source.writeAsString(jsonEncode({'title': '重新刮削', 'intro': '新的原文'}));
    await service.refresh(game);
    expect(
        await service.loadMetadata(game), {'title': '重新刮削', 'intro': '新的原文'});
    await source.delete();
    expect(
        await service.loadMetadata(game), {'title': '重新刮削', 'intro': '新的原文'});
  });

  test('旧版通关备份没有原文时正常读取并可刷新', () async {
    final game =
        Game(id: 8, path: path.join(tempDir.path, 'missing'), isCleared: true);
    await File(path.join(tempDir.path, '8.json')).writeAsString(jsonEncode({
      'version': 1,
      'game': game.toMap(),
      'tags': [],
      'images': [],
    }));
    expect(await service.loadMetadata(game), isNull);
    await service.refresh(game);
    expect(await service.find(game), isNotNull);
    expect(await service.loadMetadata(game), isNull);
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

    saved['metadata'] = {
      'intro_html': '<p>需要保留的简介布局</p>',
      'translation': {
        'original': {'intro': '原文'}
      },
    };
    await file.writeAsString(jsonEncode(saved));

    await service.refresh(game.copyWith(rating: 5.0, review: '删除前最新评论'));
    final refreshed =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final refreshedGame = refreshed['game'] as Map<String, dynamic>;
    expect(refreshedGame['rating'], 5.0);
    expect(refreshedGame['review'], '删除前最新评论');
    expect(refreshed['metadata'], saved['metadata']);
    expect(await File('${file.path}.tmp').exists(), isFalse);

    expect(await service.find(game), isNotNull);
    await service.delete(game);
    expect(await file.exists(), isFalse);
  });
}
