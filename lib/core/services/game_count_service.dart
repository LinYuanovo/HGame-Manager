import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class GameCountService {
  final Ref _ref;
  int _gameCount = 0;
  int _playedCount = 0;

  GameCountService(this._ref);

  int get gameCount => _gameCount;
  int get playedCount => _playedCount;

  Future<void> syncGameCount() async {
    try {
      final repository = _ref.read(gameRepositoryProvider);
      _gameCount = await repository.getGameCount();
      _playedCount = await repository.getPlayedCount();
    } catch (_) {
      // Database might not be initialized yet
    }
  }
}
