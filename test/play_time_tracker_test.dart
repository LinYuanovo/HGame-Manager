import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/repositories/play_time_repository.dart';
import 'package:hgame_manager/core/services/play_time_tracker.dart';
import 'package:hgame_manager/core/services/process_probe.dart';

void main() {
  group('formatDuration', () {
    test('should format 0 seconds as 0分钟', () {
      expect(formatDuration(0), '0分钟');
    });

    test('should format seconds less than 60', () {
      expect(formatDuration(30), '0分钟');
      expect(formatDuration(59), '0分钟');
    });

    test('should format minutes correctly', () {
      expect(formatDuration(60), '1分钟');
      expect(formatDuration(90), '1分钟');
      expect(formatDuration(3540), '59分钟');
    });

    test('should format hours and minutes correctly', () {
      expect(formatDuration(3600), '1小时0分钟');
      expect(formatDuration(3660), '1小时1分钟');
      expect(formatDuration(7200), '2小时0分钟');
      expect(formatDuration(9000), '2小时30分钟');
    });
  });

  group('Game model', () {
    test('should create game with default playDuration', () {
      final game = Game(path: '/test');
      expect(game.playDuration, 0);
    });

    test('should create game with custom playDuration', () {
      final game = Game(path: '/test', playDuration: 3600);
      expect(game.playDuration, 3600);
    });

    test('should copy game with new playDuration', () {
      final game = Game(path: '/test', playDuration: 0);
      final updatedGame = game.copyWith(playDuration: 3600);
      expect(updatedGame.playDuration, 3600);
    });

    test('should serialize and deserialize playDuration', () {
      final game = Game(path: '/test', playDuration: 3600);
      final map = game.toMap();
      final deserializedGame = Game.fromMap(map);
      expect(deserializedGame.playDuration, 3600);
    });
  });

  group('PlayTimeTracker', () {
    test('does not record play when no process can be bound', () async {
      final repo = _FakePlayTimeRepository();
      final probe = _FakeProcessProbe([
        [],
      ]);
      final now = DateTime(2026, 1, 1, 12);
      final tracker = PlayTimeTracker(
        repository: repo,
        processProbe: probe,
        now: () => now,
        bindTimeout: Duration.zero,
      );

      final started = await tracker.start(
        Game(id: 1, path: r'C:\Games\NoProcess'),
        processSnapshotBefore: const [],
        trackingHintPath: r'C:\Games\NoProcess\game.exe',
      );

      expect(started, isFalse);
      expect(repo.startedGameIds, isEmpty);
      expect(repo.durationDeltas, isEmpty);
    });

    test('prefers a running locked launcher exe', () {
      final tracker = PlayTimeTracker(
        repository: _FakePlayTimeRepository(),
        processProbe: _FakeProcessProbe(),
      );
      const launcher = RunningProcess(
        pid: 10,
        name: 'Launcher.exe',
        executablePath: r'C:\Games\Locked\Launcher.exe',
      );
      const game = RunningProcess(
        pid: 11,
        parentPid: 10,
        name: 'Game.exe',
        executablePath: r'C:\Games\Locked\Game.exe',
      );

      final selected = tracker.selectTargetProcessForTesting(
        game: Game(
          id: 1,
          path: r'C:\Games\Locked',
          gameLauncher: r'C:\Games\Locked\Launcher.exe',
          launcherLocked: true,
        ),
        before: const [],
        after: const [launcher, game],
        trackingHintPath: r'C:\Games\Locked\Launcher.exe',
        launcherWasLocked: true,
      );

      expect(selected?.pid, launcher.pid);
    });

    test('ignores bat and LE helper processes and binds the real game process',
        () {
      final tracker = PlayTimeTracker(
        repository: _FakePlayTimeRepository(),
        processProbe: _FakeProcessProbe(),
      );
      const leProc = RunningProcess(
        pid: 20,
        name: 'LEProc.exe',
        executablePath: r'C:\Tools\LEProc.exe',
      );
      const cmd = RunningProcess(
        pid: 21,
        parentPid: 20,
        name: 'cmd.exe',
        executablePath: r'C:\Windows\System32\cmd.exe',
      );
      const game = RunningProcess(
        pid: 22,
        parentPid: 21,
        name: 'Game.exe',
        executablePath: r'C:\Games\Locale\Game.exe',
      );

      final selected = tracker.selectTargetProcessForTesting(
        game: Game(id: 1, path: r'C:\Games\Locale'),
        before: const [],
        after: const [leProc, cmd, game],
        launchedPath: r'C:\Tools\LEProc.exe',
        trackingHintPath: r'C:\Games\Locale\Game.exe',
        startedProcessId: 20,
      );

      expect(selected?.pid, game.pid);
    });

    test('binds a new process under the game directory before recording play',
        () async {
      final repo = _FakePlayTimeRepository();
      final probe = _FakeProcessProbe([
        const [
          RunningProcess(
            pid: 30,
            name: 'Game.exe',
            executablePath: r'C:\Games\NewProcess\Game.exe',
          ),
        ],
      ]);
      final now = DateTime(2026, 1, 1, 12);
      final tracker = PlayTimeTracker(
        repository: repo,
        processProbe: probe,
        now: () => now,
        bindTimeout: Duration.zero,
      );

      final started = await tracker.start(
        Game(id: 7, path: r'C:\Games\NewProcess'),
        processSnapshotBefore: const [],
        trackingHintPath: r'C:\Games\NewProcess\Game.exe',
      );

      expect(started, isTrue);
      expect(repo.startedGameIds, [7]);
      expect(repo.startedAt.single, now);
    });

    test('adds real elapsed seconds on tick instead of a fixed interval',
        () async {
      final repo = _FakePlayTimeRepository();
      const target = RunningProcess(
        pid: 40,
        name: 'Game.exe',
        executablePath: r'C:\Games\Elapsed\Game.exe',
      );
      final probe = _FakeProcessProbe([
        [target],
        [target],
      ]);
      var now = DateTime(2026, 1, 1, 12);
      final tracker = PlayTimeTracker(
        repository: repo,
        processProbe: probe,
        now: () => now,
        bindTimeout: Duration.zero,
        saveInterval: const Duration(seconds: 1),
      );

      final started = await tracker.start(
        Game(id: 8, path: r'C:\Games\Elapsed'),
        processSnapshotBefore: const [],
        trackingHintPath: r'C:\Games\Elapsed\Game.exe',
      );
      expect(started, isTrue);

      now = now.add(const Duration(seconds: 15));
      await tracker.handleTickForTesting();

      expect(repo.durationDeltas, [15]);
    });

    test('saves the final partial duration when stopped', () async {
      final repo = _FakePlayTimeRepository();
      const target = RunningProcess(
        pid: 50,
        name: 'Game.exe',
        executablePath: r'C:\Games\Stop\Game.exe',
      );
      final probe = _FakeProcessProbe([
        [target],
        [target],
      ]);
      var now = DateTime(2026, 1, 1, 12);
      final tracker = PlayTimeTracker(
        repository: repo,
        processProbe: probe,
        now: () => now,
        bindTimeout: Duration.zero,
      );

      final started = await tracker.start(
        Game(id: 9, path: r'C:\Games\Stop'),
        processSnapshotBefore: const [],
        trackingHintPath: r'C:\Games\Stop\Game.exe',
      );
      expect(started, isTrue);

      now = now.add(const Duration(seconds: 20));
      await tracker.stop();

      expect(repo.durationDeltas, [20]);
    });

    test('saves the previous game duration before switching games', () async {
      final repo = _FakePlayTimeRepository();
      const first = RunningProcess(
        pid: 60,
        name: 'Game.exe',
        executablePath: r'C:\Games\First\Game.exe',
      );
      const second = RunningProcess(
        pid: 61,
        name: 'Game.exe',
        executablePath: r'C:\Games\Second\Game.exe',
      );
      final probe = _FakeProcessProbe([
        [first],
        [first],
        [second],
      ]);
      var now = DateTime(2026, 1, 1, 12);
      final tracker = PlayTimeTracker(
        repository: repo,
        processProbe: probe,
        now: () => now,
        bindTimeout: Duration.zero,
      );

      expect(
        await tracker.start(
          Game(id: 10, path: r'C:\Games\First'),
          processSnapshotBefore: const [],
          trackingHintPath: r'C:\Games\First\Game.exe',
        ),
        isTrue,
      );

      now = now.add(const Duration(seconds: 15));
      expect(
        await tracker.start(
          Game(id: 11, path: r'C:\Games\Second'),
          processSnapshotBefore: const [],
          trackingHintPath: r'C:\Games\Second\Game.exe',
        ),
        isTrue,
      );

      expect(repo.startedGameIds, [10, 11]);
      expect(repo.durationDeltas, [15]);
    });
  });
}

class _FakePlayTimeRepository implements PlayTimeRepository {
  final startedGameIds = <int>[];
  final startedAt = <DateTime>[];
  final durationDeltas = <int>[];

  @override
  Future<void> recordPlayStarted(int gameId, DateTime startedAt) async {
    startedGameIds.add(gameId);
    this.startedAt.add(startedAt);
  }

  @override
  Future<void> addPlayDurationDelta(int gameId, int seconds) async {
    durationDeltas.add(seconds);
  }
}

class _FakeProcessProbe implements ProcessProbe {
  final Queue<List<RunningProcess>> _snapshots;
  List<RunningProcess> _lastSnapshot = const [];

  _FakeProcessProbe([List<List<RunningProcess>> snapshots = const []])
      : _snapshots = Queue<List<RunningProcess>>.from(snapshots);

  @override
  Future<List<RunningProcess>> snapshot() async {
    if (_snapshots.isNotEmpty) {
      _lastSnapshot = _snapshots.removeFirst();
    }
    return _lastSnapshot;
  }
}
