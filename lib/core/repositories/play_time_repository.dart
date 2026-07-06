abstract class PlayTimeRepository {
  Future<void> recordPlayStarted(int gameId, DateTime startedAt);

  Future<void> addPlayDurationDelta(int gameId, int seconds);
}
