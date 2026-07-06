import 'dart:async';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../repositories/play_time_repository.dart';
import 'app_logger.dart';
import 'process_probe.dart';

class PlayTimeTracker {
  static final PlayTimeTracker _default = PlayTimeTracker();
  static const _logTag = 'PlayTimeTracker';

  final PlayTimeRepository _repository;
  final ProcessProbe _processProbe;
  final DateTime Function() _now;
  final Duration bindTimeout;
  final Duration bindPollInterval;
  final Duration checkInterval;
  final Duration saveInterval;

  Timer? _timer;
  Game? _currentGame;
  RunningProcess? _targetProcess;
  DateTime? _lastObservedAt;
  int _sessionSeconds = 0;
  int _lastSaveSeconds = 0;
  bool _isProcessing = false;

  PlayTimeTracker({
    PlayTimeRepository? repository,
    ProcessProbe? processProbe,
    DateTime Function()? now,
    this.bindTimeout = const Duration(seconds: 30),
    this.bindPollInterval = const Duration(seconds: 2),
    this.checkInterval = const Duration(seconds: 15),
    this.saveInterval = const Duration(seconds: 60),
  })  : _repository = repository ?? GameRepository(),
        _processProbe = processProbe ?? const WindowsProcessProbe(),
        _now = now ?? DateTime.now;

  static Future<bool> startTracking(
    Game game, {
    required List<RunningProcess> processSnapshotBefore,
    String? launchedPath,
    String? trackingHintPath,
    bool launcherWasLocked = false,
    int? startedProcessId,
  }) {
    return _default.start(
      game,
      processSnapshotBefore: processSnapshotBefore,
      launchedPath: launchedPath,
      trackingHintPath: trackingHintPath,
      launcherWasLocked: launcherWasLocked,
      startedProcessId: startedProcessId,
    );
  }

  static Future<void> stopTracking() => _default.stop();

  static Game? get currentGame => _default._currentGame;

  static int get sessionSeconds => _default._sessionSeconds;

  Future<bool> start(
    Game game, {
    required List<RunningProcess> processSnapshotBefore,
    String? launchedPath,
    String? trackingHintPath,
    bool launcherWasLocked = false,
    int? startedProcessId,
  }) async {
    if (game.id == null) {
      AppLogger.instance.warning(_logTag, '开始计时失败：游戏缺少 id，path=${game.path}');
      return false;
    }

    if (_currentGame != null) {
      AppLogger.instance.info(
        _logTag,
        '切换追踪游戏：先停止当前游戏，currentGameId=${_currentGame?.id}, newGameId=${game.id}',
      );
      await stop();
    }

    AppLogger.instance.info(
      _logTag,
      '开始绑定游戏进程：gameId=${game.id}, title=${game.title}, path=${game.path}, '
      'launchedPath=$launchedPath, trackingHintPath=$trackingHintPath, '
      'launcherWasLocked=$launcherWasLocked, startedProcessId=$startedProcessId, '
      'beforeCount=${processSnapshotBefore.length}',
    );

    final target = await _bindTargetProcess(
      game: game,
      processSnapshotBefore: processSnapshotBefore,
      launchedPath: launchedPath,
      trackingHintPath: trackingHintPath,
      launcherWasLocked: launcherWasLocked,
      startedProcessId: startedProcessId,
    );

    if (target == null) {
      AppLogger.instance.warning(
        _logTag,
        '绑定游戏进程失败：30 秒内未识别到有效目标，gameId=${game.id}, '
        'path=${game.path}, launchedPath=$launchedPath, trackingHintPath=$trackingHintPath',
      );
      return false;
    }

    final startedAt = _now();
    await _repository.recordPlayStarted(game.id!, startedAt);

    _currentGame = game.copyWith(
      isPlayed: true,
      playCount: game.playCount + 1,
      lastPlayedTime: startedAt,
    );
    _targetProcess = target;
    _lastObservedAt = startedAt;
    _sessionSeconds = 0;
    _lastSaveSeconds = 0;

    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) => _handleTick());
    AppLogger.instance.info(
      _logTag,
      '绑定游戏进程成功并开始计时：gameId=${game.id}, ${_formatProcess(target)}',
    );
    return true;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;

    if (_currentGame != null && _targetProcess != null) {
      final runningTarget = await _findRunningTarget();
      if (runningTarget != null) {
        _targetProcess = runningTarget;
        _addElapsedUntil(_now());
      }
    }

    await _saveProgress();
    if (_currentGame != null) {
      AppLogger.instance.info(
        _logTag,
        '停止计时：gameId=${_currentGame?.id}, sessionSeconds=$_sessionSeconds, savedSeconds=$_lastSaveSeconds',
      );
    }
    _reset();
  }

  Future<void> handleTickForTesting() => _handleTick();

  RunningProcess? selectTargetProcessForTesting({
    required Game game,
    required List<RunningProcess> before,
    required List<RunningProcess> after,
    String? launchedPath,
    String? trackingHintPath,
    bool launcherWasLocked = false,
    int? startedProcessId,
  }) {
    return _selectTargetProcess(
      game: game,
      before: before,
      after: after,
      launchedPath: launchedPath,
      trackingHintPath: trackingHintPath,
      launcherWasLocked: launcherWasLocked,
      startedProcessId: startedProcessId,
    );
  }

  Future<RunningProcess?> _bindTargetProcess({
    required Game game,
    required List<RunningProcess> processSnapshotBefore,
    String? launchedPath,
    String? trackingHintPath,
    bool launcherWasLocked = false,
    int? startedProcessId,
  }) async {
    final deadline = _now().add(bindTimeout);

    while (true) {
      final snapshotAfter = await _processProbe.snapshot();
      final target = _selectTargetProcess(
        game: game,
        before: processSnapshotBefore,
        after: snapshotAfter,
        launchedPath: launchedPath,
        trackingHintPath: trackingHintPath,
        launcherWasLocked: launcherWasLocked,
        startedProcessId: startedProcessId,
      );
      if (target != null) return target;
      if (!_now().isBefore(deadline)) {
        AppLogger.instance.warning(
          _logTag,
          '绑定轮询结束仍未找到目标进程：gameId=${game.id}, afterCount=${snapshotAfter.length}',
        );
        return null;
      }
      await Future.delayed(bindPollInterval);
    }
  }

  RunningProcess? _selectTargetProcess({
    required Game game,
    required List<RunningProcess> before,
    required List<RunningProcess> after,
    String? launchedPath,
    String? trackingHintPath,
    bool launcherWasLocked = false,
    int? startedProcessId,
  }) {
    final beforePids = before.map((process) => process.pid).toSet();
    final newProcesses =
        after.where((process) => !beforePids.contains(process.pid)).toList();
    AppLogger.instance.info(
      _logTag,
      '进程绑定扫描：gameId=${game.id}, before=${before.length}, after=${after.length}, new=${newProcesses.length}',
    );

    if (launcherWasLocked && _isExePath(trackingHintPath)) {
      final launcherProcess = _bestCandidate(
        after.where((process) {
          return _isValidGameProcess(process) &&
              _matchesPathOrName(process, trackingHintPath);
        }),
        game: game,
        trackingHintPath: trackingHintPath,
      );
      if (launcherProcess != null) {
        AppLogger.instance.info(
          _logTag,
          '绑定命中：锁定启动器仍在运行，${_formatProcess(launcherProcess)}',
        );
        return launcherProcess;
      }
    }

    final newGameDirProcess = _bestCandidate(
      newProcesses.where((process) {
        return _isValidGameProcess(process) &&
            _isUnderPath(process.executablePath, game.path);
      }),
      game: game,
      trackingHintPath: trackingHintPath,
    );
    if (newGameDirProcess != null) {
      AppLogger.instance.info(
        _logTag,
        '绑定命中：游戏目录内新进程，${_formatProcess(newGameDirProcess)}',
      );
      return newGameDirProcess;
    }

    final relatedProcess = _bestCandidate(
      _relatedNewProcesses(
        allProcesses: after,
        newProcesses: newProcesses,
        launchedPath: launchedPath,
        trackingHintPath: trackingHintPath,
        startedProcessId: startedProcessId,
      ).where(_isValidGameProcess),
      game: game,
      trackingHintPath: trackingHintPath,
    );
    if (relatedProcess != null) {
      AppLogger.instance.info(
        _logTag,
        '绑定命中：启动器父子关系新进程，${_formatProcess(relatedProcess)}',
      );
      return relatedProcess;
    }

    final commonNames = _commonGameProcessNames(trackingHintPath);
    final commonNameProcess = _bestCandidate(
      after.where((process) {
        return _isValidGameProcess(process) &&
            commonNames.contains(process.normalizedName) &&
            (_isUnderPath(process.executablePath, game.path) ||
                process.executablePath == null);
      }),
      game: game,
      trackingHintPath: trackingHintPath,
    );
    if (commonNameProcess != null) {
      AppLogger.instance.info(
        _logTag,
        '绑定命中：常见游戏进程名，${_formatProcess(commonNameProcess)}',
      );
      return commonNameProcess;
    }

    _logRejectedNewProcesses(newProcesses, game.path);
    return null;
  }

  Iterable<RunningProcess> _relatedNewProcesses({
    required List<RunningProcess> allProcesses,
    required List<RunningProcess> newProcesses,
    String? launchedPath,
    String? trackingHintPath,
    int? startedProcessId,
  }) sync* {
    final processByPid = {
      for (final process in allProcesses) process.pid: process
    };
    final seedPids = <int>{};
    if (startedProcessId != null) seedPids.add(startedProcessId);

    for (final process in newProcesses) {
      if (_matchesPathOrName(process, launchedPath) ||
          _matchesPathOrName(process, trackingHintPath)) {
        seedPids.add(process.pid);
      }
    }

    for (final process in newProcesses) {
      if (seedPids.contains(process.pid) && _isValidGameProcess(process)) {
        yield process;
        continue;
      }

      var parentPid = process.parentPid;
      final visited = <int>{};
      while (parentPid != null && visited.add(parentPid)) {
        if (seedPids.contains(parentPid)) {
          yield process;
          break;
        }
        parentPid = processByPid[parentPid]?.parentPid;
      }
    }
  }

  Future<void> _handleTick() async {
    if (_currentGame == null || _targetProcess == null) return;
    if (_isProcessing) return;

    _isProcessing = true;
    try {
      final runningTarget = await _findRunningTarget();
      if (runningTarget == null) {
        AppLogger.instance.info(
          _logTag,
          '目标进程已退出：gameId=${_currentGame?.id}, target=${_formatProcess(_targetProcess!)}',
        );
        await _saveProgress();
        _reset();
        return;
      }

      _targetProcess = runningTarget;
      _addElapsedUntil(_now());

      if (_sessionSeconds - _lastSaveSeconds >= saveInterval.inSeconds) {
        await _saveProgress();
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<RunningProcess?> _findRunningTarget() async {
    final target = _targetProcess;
    if (target == null) return null;

    final snapshot = await _processProbe.snapshot();
    for (final process in snapshot) {
      if (process.pid == target.pid &&
          process.normalizedName == target.normalizedName &&
          _samePathOrBothUnknown(
              process.executablePath, target.executablePath)) {
        return process;
      }
    }

    if (target.executablePath != null && target.executablePath!.isNotEmpty) {
      for (final process in snapshot) {
        if (_samePath(process.executablePath, target.executablePath) &&
            _isValidGameProcess(process)) {
          return process;
        }
      }
    }

    if (target.executablePath == null || target.executablePath!.isEmpty) {
      for (final process in snapshot) {
        if (process.normalizedName == target.normalizedName &&
            _isValidGameProcess(process)) {
          return process;
        }
      }
    }

    return null;
  }

  void _addElapsedUntil(DateTime now) {
    final lastObservedAt = _lastObservedAt;
    if (lastObservedAt == null) {
      _lastObservedAt = now;
      return;
    }

    final elapsedSeconds = now.difference(lastObservedAt).inSeconds;
    if (elapsedSeconds <= 0) return;

    _sessionSeconds += elapsedSeconds;
    _lastObservedAt = now;
  }

  Future<void> _saveProgress() async {
    final gameId = _currentGame?.id;
    if (gameId == null) return;

    final delta = _sessionSeconds - _lastSaveSeconds;
    if (delta <= 0) return;

    try {
      await _repository.addPlayDurationDelta(gameId, delta);
      _lastSaveSeconds = _sessionSeconds;
      AppLogger.instance.info(
        _logTag,
        '保存游玩时长增量：gameId=$gameId, delta=$delta, sessionSeconds=$_sessionSeconds',
      );
    } catch (e, stackTrace) {
      AppLogger.instance.error(
        _logTag,
        '保存游玩时长增量失败：gameId=$gameId, delta=$delta',
        e,
        stackTrace,
      );
      // 保存失败不影响游戏继续运行；下次 tick 会再次尝试写入同一段增量。
    }
  }

  RunningProcess? _bestCandidate(
    Iterable<RunningProcess> candidates, {
    required Game game,
    String? trackingHintPath,
  }) {
    final list = candidates.toList();
    if (list.isEmpty) return null;

    list.sort((a, b) {
      final scoreB =
          _scoreProcess(b, game: game, trackingHintPath: trackingHintPath);
      final scoreA =
          _scoreProcess(a, game: game, trackingHintPath: trackingHintPath);
      final scoreCompare = scoreB.compareTo(scoreA);
      if (scoreCompare != 0) return scoreCompare;
      return a.pid.compareTo(b.pid);
    });

    return list.first;
  }

  void _logRejectedNewProcesses(
    List<RunningProcess> newProcesses,
    String gamePath,
  ) {
    if (newProcesses.isEmpty) {
      AppLogger.instance.info(_logTag, '绑定未命中：未发现新进程');
      return;
    }

    final preview = newProcesses.take(12).map((process) {
      final valid = _isValidGameProcess(process);
      final underGamePath = _isUnderPath(process.executablePath, gamePath);
      return '${_formatProcess(process)} valid=$valid underGamePath=$underGamePath';
    }).join(' | ');

    AppLogger.instance.info(
      _logTag,
      '绑定未命中：新进程均未满足规则，preview=$preview',
    );
  }

  String _formatProcess(RunningProcess process) {
    return 'pid=${process.pid}, parentPid=${process.parentPid}, '
        'name=${process.name}, path=${process.executablePath}';
  }

  int _scoreProcess(RunningProcess process,
      {required Game game, String? trackingHintPath}) {
    var score = 0;
    if (_samePath(process.executablePath, trackingHintPath)) {
      score += 100;
    }
    if (_isUnderPath(process.executablePath, game.path)) {
      score += 50;
    }
    if (_commonGameProcessNames(trackingHintPath)
        .contains(process.normalizedName)) {
      score += 20;
    }
    if (process.executablePath != null) {
      score += 5;
    }
    return score;
  }

  bool _isValidGameProcess(RunningProcess process) {
    if (process.name.isEmpty || process.pid <= 0) {
      return false;
    }
    return !_helperProcessNames.contains(process.normalizedName);
  }

  bool _matchesPathOrName(RunningProcess process, String? path) {
    if (path == null || path.isEmpty) {
      return false;
    }
    return _samePath(process.executablePath, path) ||
        process.normalizedName == p.basename(path).toLowerCase();
  }

  bool _isUnderPath(String? childPath, String parentPath) {
    if (childPath == null || childPath.isEmpty || parentPath.isEmpty) {
      return false;
    }
    final normalizedChild = _normalizePath(childPath);
    final normalizedParent = _normalizePath(parentPath);
    return normalizedChild == normalizedParent ||
        normalizedChild.startsWith('$normalizedParent${p.separator}');
  }

  bool _samePath(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) {
      return false;
    }
    return _normalizePath(a) == _normalizePath(b);
  }

  bool _samePathOrBothUnknown(String? a, String? b) {
    if ((a == null || a.isEmpty) && (b == null || b.isEmpty)) {
      return true;
    }
    return _samePath(a, b);
  }

  bool _isExePath(String? path) {
    if (path == null || path.isEmpty) {
      return false;
    }
    return p.extension(path).toLowerCase() == '.exe';
  }

  String _normalizePath(String value) {
    var normalized =
        value.replaceAll('\\', p.separator).replaceAll('/', p.separator);
    normalized = p.normalize(normalized).toLowerCase();
    if (normalized.length > 1 && normalized.endsWith(p.separator)) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Set<String> _commonGameProcessNames(String? trackingHintPath) {
    final names = <String>{
      'game.exe',
      'launcher.exe',
      'launch.exe',
      'player.exe',
      'play.exe',
      'nw.exe',
      'mtool_game.exe',
    };

    if (_isExePath(trackingHintPath)) {
      names.add(p.basename(trackingHintPath!).toLowerCase());
    }

    return names;
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _currentGame = null;
    _targetProcess = null;
    _lastObservedAt = null;
    _sessionSeconds = 0;
    _lastSaveSeconds = 0;
    _isProcessing = false;
  }

  static const _helperProcessNames = {
    'cmd.exe',
    'conhost.exe',
    'explorer.exe',
    'leproc.exe',
    'powershell.exe',
    'pwsh.exe',
    'start.exe',
  };
}
