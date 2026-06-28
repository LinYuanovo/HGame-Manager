import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as path;
import '../models/models.dart';
import '../models/rename_rule.dart';
import '../repositories/game_repository.dart';
import '../utils/app_settings.dart';
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

  /// 加载重命名规则配置
  static Future<List<RenameRule>> _loadRules() async {
    final prefs = await AppSettings.load();
    final raw = prefs.getString(AppSettings.renameRulesKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw);
        return list.map((m) => RenameRule.fromJson(m as Map<String, dynamic>)).toList();
      } catch (_) {
        // JSON解析失败时使用默认配置
      }
    }

    return RenameRule.defaultRules();
  }

  /// 从游戏数据中提取指定规则的值
  static String? _extractRuleValue(String ruleId, Game game, {String? Function(String)? dlsiteIdExtractor}) {
    switch (ruleId) {
      case 'game_id':
        if (game.sourceUrl != null && game.sourceUrl!.isNotEmpty) {
          String? id;
          if (dlsiteIdExtractor != null) {
            id = dlsiteIdExtractor(game.sourceUrl!);
          } else {
            id = DlsiteService().normalizeId(game.sourceUrl!);
          }
          if (id == null || id.isEmpty) {
            final steamMatch = RegExp(r'store\.steampowered\.com/app/(\d+)').firstMatch(game.sourceUrl!);
            if (steamMatch != null) {
              id = steamMatch.group(1);
            }
          }
          return id;
        }
        return null;
      case 'maker':
        return game.maker;
      case 'series':
        for (final tag in game.tags) {
          if (tag.type == Tag.typeSeries) {
            return tag.name;
          }
        }
        return null;
      case 'title':
        return game.title;
      case 'version':
        return game.version;
      default:
        return null;
    }
  }

  /// 根据规则列表构建备份文件夹名称
  static String _buildNameFromRules(
    List<RenameRule> rules,
    Game game, {
    String? Function(String)? dlsiteIdExtractor,
  }) {
    final parts = <String>[];

    // 按排序顺序处理规则
    final sortedRules = List<RenameRule>.from(rules)
      ..sort((a, b) => a.order.compareTo(b.order));

    for (final rule in sortedRules) {
      if (!rule.enabled) continue;

      final value = _extractRuleValue(rule.id, game, dlsiteIdExtractor: dlsiteIdExtractor);
      if (value != null && value.isNotEmpty) {
        parts.add(rule.wrapContent(value));
      }
    }

    return parts.isEmpty ? '' : parts.join(' ');
  }

  /// 构建备份文件夹名称（异步版本，供外部直接调用）
  /// 使用配置的规则构建名称
  static Future<String?> buildBackupFolderName(
    Game game, {
    String? Function(String)? dlsiteIdExtractor,
  }) async {
    final title = game.title;
    if (title == null || title.isEmpty) return null;

    final rules = await _loadRules();
    final name = _buildNameFromRules(rules, game, dlsiteIdExtractor: dlsiteIdExtractor);
    return name.isEmpty ? null : name;
  }

  /// 同步版本的buildBackupFolderName（用于不能async的场景）
  /// 使用默认规则，不读取配置
  static String? buildBackupFolderNameSync(
    Game game, {
    String? Function(String)? dlsiteIdExtractor,
  }) {
    final title = game.title;
    if (title == null || title.isEmpty) return null;

    // 使用默认规则
    final rules = RenameRule.defaultRules();
    final name = _buildNameFromRules(rules, game, dlsiteIdExtractor: dlsiteIdExtractor);
    return name.isEmpty ? null : name;
  }

  /// 根据用户配置的规则构建新的游戏文件夹名称
  Future<String?> buildNewFolderName(Game game) {
    return buildBackupFolderName(
      game,
      dlsiteIdExtractor: (url) => _dlsiteService.normalizeId(url),
    );
  }

  /// 重命名单个游戏文件夹
  Future<String?> renameGameFolder(Game game) async {
    final newName = await buildNewFolderName(game);
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
        final newLauncher = path.join(newPath, relative);
        await _gameRepository.updateGameLauncher(game.id!, newLauncher, game.launcherLocked);
      }

      if (game.savePath != null && game.savePath!.startsWith(oldPath)) {
        final relative = game.savePath!.substring(oldPath.length);
        final newSavePath = path.join(newPath, relative);
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
        final metadataFile = File(path.join(newPath, 'metadata.json'));
        if (await metadataFile.exists()) {
          final content = await metadataFile.readAsString();
          if (content.contains(oldPath)) {
            final updatedContent = content.replaceAll(oldPath, newPath);
            await metadataFile.writeAsString(updatedContent, flush: true);
          }
        }
      } catch (e) {
        debugPrint('[FolderRename] 更新metadata.json路径失败: $e');
      }

      debugPrint('[FolderRename] Success: $newPath');
      return newPath;
    } catch (e) {
      debugPrint('[FolderRename] Failed: $e');
      return null;
    }
  }

  /// 计算可以重命名的游戏数量（预览）
  Future<int> countRenamableGames() async {
    final games = await _gameRepository.getAllGames();
    int count = 0;

    for (final game in games) {
      final newName = await buildNewFolderName(game);
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

  /// 批量重命名所有游戏文件夹
  Future<int> renameAllGameFolders() async {
    final games = await _gameRepository.getAllGames();
    int renamed = 0;

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
