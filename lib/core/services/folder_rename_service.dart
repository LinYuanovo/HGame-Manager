import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as path;
import '../models/models.dart';
import '../repositories/game_repository.dart';
import 'dlsite_service.dart';
import 'steam_service.dart';

class FolderRenameService {
  final GameRepository _gameRepository;
  final DlsiteService _dlsiteService;
  final SteamService _steamService;

  FolderRenameService({
    GameRepository? gameRepository,
    DlsiteService? dlsiteService,
    SteamService? steamService,
  })  : _gameRepository = gameRepository ?? GameRepository(),
        _dlsiteService = dlsiteService ?? DlsiteService(),
        _steamService = steamService ?? SteamService();

  String? buildNewFolderName(Game game) {
    final title = game.title;
    if (title == null || title.isEmpty) return null;

    String? id;
    String? series;

    if (game.sourceUrl != null && game.sourceUrl!.isNotEmpty) {
      final dlsiteId = _dlsiteService.normalizeId(game.sourceUrl!);
      if (dlsiteId != null) {
        id = dlsiteId;
      } else {
        final steamMatch = RegExp(r'store\.steampowered\.com/app/(\d+)').firstMatch(game.sourceUrl!);
        if (steamMatch != null) {
          id = steamMatch.group(1);
        }
      }
    }

    for (final tag in game.tags) {
      if (tag.type == Tag.typeSeries) {
        series = tag.name;
        break;
      }
    }

    final parts = <String>[];
    if (id != null && id.isNotEmpty) parts.add('[$id]');
    if (series != null && series.isNotEmpty) parts.add('[$series]');
    parts.add(title);
    if (game.version != null && game.version!.isNotEmpty) parts.add(game.version!);

    return parts.join(' ');
  }

  Future<String?> renameGameFolder(Game game) async {
    final newName = buildNewFolderName(game);
    if (newName == null) {
      debugPrint('[FolderRename] Cannot build name for game: ${game.title}');
      return null;
    }

    final oldPath = game.path;
    final parentDir = path.dirname(oldPath);
    final newPath = path.join(parentDir, newName);

    if (oldPath == newPath) {
      debugPrint('[FolderRename] Already correctly named: $oldPath');
      return null;
    }

    if (await Directory(newPath).exists()) {
      debugPrint('[FolderRename] Target already exists: $newPath');
      return null;
    }

    debugPrint('[FolderRename] Renaming: $oldPath -> $newPath');

    try {
      await Directory(oldPath).rename(newPath);
      await _gameRepository.updateGamePath(game.id!, newPath);
      await _gameRepository.updateImagePaths(game.id!, oldPath, newPath);

      if (game.gameLauncher != null && game.gameLauncher!.startsWith(oldPath)) {
        final relative = game.gameLauncher!.substring(oldPath.length);
        final newLauncher = '$newPath$relative';
        await _gameRepository.updateGameLauncher(game.id!, newLauncher, game.launcherLocked);
      }

      if (game.savePath != null && game.savePath!.startsWith(oldPath)) {
        final relative = game.savePath!.substring(oldPath.length);
        final newSavePath = '$newPath$relative';
        await _gameRepository.updateGame(game.copyWith(savePath: newSavePath));
      }

      final currentGame = await _gameRepository.getGameById(game.id!);
      if (currentGame != null && currentGame.intro != null) {
        var updatedIntro = currentGame.intro!;
        if (updatedIntro.contains(oldPath)) {
          updatedIntro = updatedIntro.replaceAll(oldPath, newPath);
          await _gameRepository.updateGame(currentGame.copyWith(intro: updatedIntro));
        }
      }

      try {
        final metadataFile = File('$newPath${path.separator}metadata.json');
        if (await metadataFile.exists()) {
          final content = await metadataFile.readAsString();
          if (content.contains(oldPath)) {
            final updatedContent = content.replaceAll(oldPath, newPath);
            await metadataFile.writeAsString(updatedContent, flush: true);
          }
        }
      } catch (_) {}

      debugPrint('[FolderRename] Success: $newPath');
      return newPath;
    } catch (e) {
      debugPrint('[FolderRename] Failed: $e');
      return null;
    }
  }

  /// Count how many games would be renamed (dry run).
  Future<int> countRenamableGames() async {
    final games = await _gameRepository.getAllGames();
    int count = 0;

    for (final game in games) {
      final newName = buildNewFolderName(game);
      if (newName == null) continue;

      final oldPath = game.path;
      final parentDir = path.dirname(oldPath);
      final newPath = path.join(parentDir, newName);

      if (oldPath == newPath) continue;
      if (await Directory(newPath).exists()) continue;

      count++;
    }

    return count;
  }

  Future<int> renameAllGameFolders() async {
    final games = await _gameRepository.getAllGames();
    int renamed = 0;

    // Process in parallel batches of 10
    const batchSize = 10;
    for (var i = 0; i < games.length; i += batchSize) {
      final batch = games.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((game) async {
          if (game.id == null) return false;
          final result = await renameGameFolder(game);
          return result != null;
        }),
      );
      renamed += results.where((r) => r).length;
    }

    debugPrint('[FolderRename] Renamed $renamed/${games.length} games');
    return renamed;
  }
}
