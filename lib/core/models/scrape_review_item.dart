import '../../scraper/parse_utils.dart';
import 'models.dart';

enum ScrapeReviewDecision { pending, keep, discard }

/// 抓取只产生候选资料，用户确认后才应用到游戏。
class ScrapeReviewItem {
  final Game originalGame;
  final ScrapeMode mode;
  Game game;
  GameInfo? candidate;
  String? fetchError;
  ScrapeReviewDecision decision = ScrapeReviewDecision.pending;
  bool applied = false;
  String? applyError;
  String? moveError;
  bool recoveryRequired = false;
  final List<String> notices = [];

  ScrapeReviewItem({
    required this.game,
    this.candidate,
    this.fetchError,
    this.mode = ScrapeMode.scraperCenter,
  }) : originalGame = game;

  bool get canKeep => candidate?.title?.trim().isNotEmpty == true;

  String get status {
    if (recoveryRequired) return '需要恢复';
    if (applied) return '已保存';
    if (applyError != null) return '保存失败';
    if (decision == ScrapeReviewDecision.discard) return '已放弃';
    if (!canKeep) return '抓取失败';
    if (decision == ScrapeReviewDecision.keep) return '待保存';
    return '待确认';
  }
}
