import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/scrape_review_item.dart';
import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import '../utils/game_path_utils.dart';
import 'folder_move_progress.dart';
import 'game_move_service.dart';
import 'scrape_apply_service.dart';
import 'scrape_file_snapshot.dart';

class ScrapeReviewService {
  final GameRepository repository;
  final TagRepository tagRepository;

  ScrapeReviewService({required this.repository, required this.tagRepository});

  Future<Game> _currentGame(ScrapeReviewItem item) async {
    final id = item.game.id;
    if (id == null) {
      if (await repository.getStoredGameByPath(item.game.path) != null) {
        throw GameAlreadyExistsException(item.game.path);
      }
      return item.game;
    }
    final currentPath = await repository.getStoredGamePath(id);
    if (currentPath == null) throw StateError('游戏记录已移除，请重新抓取后确认');
    if (GamePathUtils.comparisonKey(currentPath) !=
        GamePathUtils.comparisonKey(item.game.path)) {
      throw StateError('游戏路径已变化，请重新抓取后确认');
    }
    final current = await repository.getStoredGameByPath(currentPath);
    if (current?.id != id) throw StateError('游戏记录已变化，请重新抓取后确认');
    return current!;
  }

  Future<void> apply(
    ScrapeReviewItem item,
    ScrapeModeConfigs configs, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (item.applied || item.decision != ScrapeReviewDecision.keep) return;
    if (item.recoveryRequired) throw StateError('请先按提示恢复此前资料');
    if (!item.canKeep) throw StateError('没有可以保存的刮削结果');
    item.applyError = null;
    item.notices.clear();
    try {
      final current = await _currentGame(item);
      if (!await Directory(current.path).exists()) {
        throw const FileSystemException('游戏文件夹不存在，请检查路径后重试');
      }
      // 确认时重新读取记录，保留抓取期间变更的收藏、评分和游玩数据。
      item.game = await ScrapeApplyService.applyScrapeResult(
        game: current,
        gameInfo: item.candidate!,
        mode: item.mode,
        repo: repository,
        tagRepo: tagRepository,
        configs: configs,
        sourceUrl: item.candidate!.sourceUrl,
        requirePersistence: true,
        onProgress: onProgress,
        onTranslationNotice: item.notices.add,
        onLog: (message) {
          if (message.contains('失败') || message.contains('跳过')) {
            item.notices.add(message);
          }
        },
      );
      item.applied = true;
    } catch (error) {
      item.applyError = error.toString();
      item.recoveryRequired = error is ScrapeRecoveryException;
      rethrow;
    }
  }

  /// 保持每个游戏的子目录，不合并同名目录或覆盖已有文件。
  Future<void> move(
    ScrapeReviewItem item,
    String destination, {
    void Function(FolderMoveProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    item.moveError = null;
    try {
      if (item.recoveryRequired) throw StateError('请先按提示恢复此前资料');
      if (!item.applied && item.decision == ScrapeReviewDecision.keep) {
        throw const FolderMoveException('请先保存已保留的结果，再移动该游戏');
      }
      if (!path.isAbsolute(destination) ||
          !await Directory(destination).exists()) {
        throw const FolderMoveException('请选择已存在的目标文件夹');
      }
      final current = await _currentGame(item);
      final oldPath = current.path;
      final newPath = path.join(destination, path.basename(oldPath));
      if (path.equals(path.normalize(oldPath), path.normalize(newPath))) {
        throw const FolderMoveException('游戏已在所选文件夹中');
      }
      final occupied = await repository.getStoredGameByPath(newPath);
      if (occupied != null) {
        throw const FolderMoveException('目标路径已被其他游戏记录占用');
      }
      final result = await GameMoveService(gameRepository: repository)
          .moveGameFolderCrossDrive(
        gameId: current.id,
        oldPath: oldPath,
        newPath: newPath,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
      item.game = await repository.getStoredGameByPath(newPath) ??
          current.copyWith(path: newPath);
      if (result.warning != null) item.notices.add(result.warning!);
    } catch (error) {
      item.moveError = error.toString();
      rethrow;
    }
  }
}
