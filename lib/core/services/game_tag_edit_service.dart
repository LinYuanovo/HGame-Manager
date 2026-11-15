import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../utils/game_data_paths.dart';
import 'app_logger.dart';
import 'cleared_metadata_backup_service.dart';

/// 保存游戏标签，同时保持目录元数据与数据库一致。
class GameTagEditService {
  final GameRepository repository;
  final ClearedMetadataBackupService clearedMetadataBackupService;

  GameTagEditService({
    required this.repository,
    ClearedMetadataBackupService? clearedMetadataBackupService,
  }) : clearedMetadataBackupService =
            clearedMetadataBackupService ?? ClearedMetadataBackupService();

  Future<Game> saveTags(Game game, List<Tag> tags,
      {Map<String, dynamic> metadataChanges = const {}}) async {
    if (game.id == null) throw StateError('编辑标签需要已入库的游戏');
    final seen = <String>{};
    final normalized = <Tag>[];
    for (final tag in tags) {
      final name = tag.name.trim();
      if (name.isNotEmpty && seen.add('${tag.type}:${name.toLowerCase()}')) {
        normalized.add(tag.copyWith(name: name));
      }
    }
    final updated = game.copyWith(tags: normalized);
    if (!await Directory(game.path).exists()) {
      return _saveMissingDirectoryGame(updated);
    }
    final metadataFile = await GameDataPaths.existingMetadataFile(game.path);
    final existed = await metadataFile.exists();
    final original = existed ? await metadataFile.readAsString() : null;
    final metadata = original != null
        ? jsonDecode(original) as Map<String, dynamic>
        : <String, dynamic>{
            if (game.title != null) 'title': game.title,
            if (game.version != null) 'version': game.version,
            if (game.intro != null) 'intro': game.intro,
            if (game.features != null) 'features': game.features,
            if (game.changelog != null) 'changelog': game.changelog,
            if (game.downloadUrl != null) 'download_url': game.downloadUrl,
            if (game.sourceUrl != null) 'source_url': game.sourceUrl,
            if (game.guide != null) 'guide': game.guide,
            if (game.maker != null) 'maker': game.maker,
            if (game.makerUrl != null) 'maker_url': game.makerUrl,
          };
    metadata.addAll(metadataChanges);
    metadata['tags'] = normalized
        .where((tag) => tag.type == Tag.typeCustom)
        .map((tag) => tag.name)
        .toList();
    final series = normalized.where((tag) => tag.type == Tag.typeSeries);
    if (series.length == 1) {
      metadata['series'] = series.single.name;
    } else if (series.isEmpty) {
      metadata.remove('series');
    }

    await metadataFile.parent.create(recursive: true);
    final temporary = File('${metadataFile.path}.tags.tmp');
    var replaced = false;
    var keepRecovery = false;
    try {
      await temporary.writeAsString(jsonEncode(metadata), flush: true);
      await repository.updateGameWithTags(updated, beforeCommit: () async {
        await temporary.rename(metadataFile.path);
        replaced = true;
      });
    } catch (error, stackTrace) {
      if (replaced) {
        keepRecovery = true;
        if (original != null) {
          await temporary.writeAsString(original, flush: true);
          await temporary.rename(metadataFile.path);
        } else {
          await metadataFile.delete();
        }
        keepRecovery = false;
      }
      AppLogger.instance.error('GameTags', '保存游戏标签失败', error, stackTrace);
      rethrow;
    } finally {
      if (!keepRecovery && await temporary.exists()) {
        await temporary.delete();
      }
    }
    return await repository.getGameById(game.id!) ?? updated;
  }

  /// 本体已删除时仍可编辑通关资料，标签变更需恢复游戏目录后同步。
  Future<Game> _saveMissingDirectoryGame(Game game) async {
    final current = await repository.getGameById(game.id!);
    if (current == null) throw StateError('游戏记录已不存在');
    Set<String> names(List<Tag> tags) => tags
        .map((tag) => '${tag.type}:${tag.name.trim().toLowerCase()}')
        .toSet();
    final previousTags = names(current.tags);
    final editedTags = names(game.tags);
    if (previousTags.length != editedTags.length ||
        !previousTags.containsAll(editedTags)) {
      throw StateError('游戏文件夹不存在，请恢复文件夹后修改标签；其他资料可继续编辑');
    }

    File? savedBackup;
    final oldBackup = game.isCleared
        ? await clearedMetadataBackupService.find(current)
        : null;
    final oldContent =
        oldBackup == null ? null : await oldBackup.readAsString();
    try {
      await repository.updateGameWithTags(game, beforeCommit: () async {
        if (game.isCleared) {
          savedBackup = await clearedMetadataBackupService.refresh(game);
        }
      });
    } catch (_) {
      if (savedBackup != null) {
        if (oldContent == null) {
          await savedBackup!.delete();
        } else {
          final recovery = File('${savedBackup!.path}.tmp');
          await recovery.writeAsString(oldContent, flush: true);
          await recovery.rename(savedBackup!.path);
        }
      }
      rethrow;
    }
    return await repository.getGameById(game.id!) ?? game;
  }
}
