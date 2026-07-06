import 'dart:io';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../repositories/tool_repository.dart';
import 'app_logger.dart';
import 'process_probe.dart';
import 'save_path_service.dart';

class GameLaunchResult {
  final bool launched;
  final Game game;
  final List<RunningProcess> processSnapshotBefore;
  final String? launchedPath;
  final String? trackingHintPath;
  final bool launcherWasLocked;
  final int? startedProcessId;
  final bool localeEmulatorMissing;
  final Object? error;

  const GameLaunchResult({
    required this.launched,
    required this.game,
    required this.processSnapshotBefore,
    this.launchedPath,
    this.trackingHintPath,
    this.launcherWasLocked = false,
    this.startedProcessId,
    this.localeEmulatorMissing = false,
    this.error,
  });

  GameLaunchResult copyWith({
    bool? localeEmulatorMissing,
  }) {
    return GameLaunchResult(
      launched: launched,
      game: game,
      processSnapshotBefore: processSnapshotBefore,
      launchedPath: launchedPath,
      trackingHintPath: trackingHintPath,
      launcherWasLocked: launcherWasLocked,
      startedProcessId: startedProcessId,
      localeEmulatorMissing:
          localeEmulatorMissing ?? this.localeEmulatorMissing,
      error: error,
    );
  }
}

class GameLaunchService {
  static const _logTag = 'GameLaunchService';

  final GameRepository _gameRepository;
  final ToolRepository _toolRepository;
  final SavePathService _savePathService;
  final ProcessProbe processProbe;

  GameLaunchService({
    required GameRepository gameRepository,
    required ToolRepository toolRepository,
    required SavePathService savePathService,
    ProcessProbe? processProbe,
  })  : _gameRepository = gameRepository,
        _toolRepository = toolRepository,
        _savePathService = savePathService,
        processProbe = processProbe ?? const WindowsProcessProbe();

  Future<GameLaunchResult> launch(Game game,
      {String? manualLauncherPath}) async {
    final snapshotBefore = await processProbe.snapshot();
    AppLogger.instance.info(
      _logTag,
      '准备启动游戏：gameId=${game.id}, title=${game.title}, path=${game.path}, '
      'manualLauncherPath=$manualLauncherPath, useLocaleEmulator=${game.useLocaleEmulator}, '
      'launcherLocked=${game.launcherLocked}, storedLauncher=${game.gameLauncher}, '
      'beforeProcessCount=${snapshotBefore.length}',
    );

    if (manualLauncherPath != null) {
      return _launchManual(game, manualLauncherPath, snapshotBefore);
    }

    var gameForLaunch = game;
    var localeEmulatorMissing = false;

    if (gameForLaunch.useLocaleEmulator) {
      final localeResult =
          await _launchWithLocaleEmulator(gameForLaunch, snapshotBefore);
      if (localeResult != null) return localeResult;

      final leProcPath = await findLeProcPath();
      if (leProcPath == null) {
        localeEmulatorMissing = true;
        AppLogger.instance.warning(
          _logTag,
          'LE 启动失败：未找到 LEProc.exe，gameId=${gameForLaunch.id}',
        );
        if (gameForLaunch.id != null) {
          await _gameRepository.updateLocaleEmulator(gameForLaunch.id!, false);
        }
        gameForLaunch = gameForLaunch.copyWith(useLocaleEmulator: false);
      }
    }

    final result = await _launchNormal(gameForLaunch, snapshotBefore);
    return result.copyWith(localeEmulatorMissing: localeEmulatorMissing);
  }

  Future<String?> findLeProcPath() async {
    final tools = await _toolRepository.getAllTools();
    for (final tool in tools) {
      final fileName = p.basename(tool.path).toLowerCase();
      if (fileName == 'leproc.exe' && await File(tool.path).exists()) {
        return tool.path;
      }
    }
    return null;
  }

  Future<GameLaunchResult> _launchManual(
    Game game,
    String launcherPath,
    List<RunningProcess> snapshotBefore,
  ) async {
    try {
      AppLogger.instance.info(
        _logTag,
        '手动启动器启动：gameId=${game.id}, launcherPath=$launcherPath',
      );
      final startedProcessId = await _startLauncher(launcherPath);
      var updatedGame =
          game.copyWith(gameLauncher: launcherPath, launcherLocked: true);
      if (game.id != null) {
        await _gameRepository.updateGameLauncher(game.id!, launcherPath, true);
      }
      return GameLaunchResult(
        launched: true,
        game: updatedGame,
        processSnapshotBefore: snapshotBefore,
        launchedPath: launcherPath,
        trackingHintPath: launcherPath,
        launcherWasLocked: true,
        startedProcessId: startedProcessId,
      );
    } catch (e) {
      AppLogger.instance.error(
        _logTag,
        '手动启动器启动失败：gameId=${game.id}, launcherPath=$launcherPath',
        e,
      );
      return GameLaunchResult(
        launched: false,
        game: game,
        processSnapshotBefore: snapshotBefore,
        error: e,
      );
    }
  }

  Future<GameLaunchResult?> _launchWithLocaleEmulator(
    Game game,
    List<RunningProcess> snapshotBefore,
  ) async {
    final leProcPath = await findLeProcPath();
    if (leProcPath == null) return null;

    final exePath = await _findLocaleTargetExe(game);
    if (exePath == null) {
      AppLogger.instance.warning(
        _logTag,
        'LE 启动跳过：未找到目标 exe，gameId=${game.id}, path=${game.path}',
      );
      return null;
    }

    try {
      AppLogger.instance.info(
        _logTag,
        'LE 启动：gameId=${game.id}, leProcPath=$leProcPath, targetExe=$exePath',
      );
      final startedProcessId = await _startLauncher(
        leProcPath,
        args: [exePath],
        workingDirectory: p.dirname(exePath),
      );
      return GameLaunchResult(
        launched: true,
        game: game,
        processSnapshotBefore: snapshotBefore,
        launchedPath: leProcPath,
        trackingHintPath: exePath,
        launcherWasLocked:
            _samePath(game.gameLauncher, exePath) && game.launcherLocked,
        startedProcessId: startedProcessId,
      );
    } catch (e) {
      AppLogger.instance.error(
        _logTag,
        'LE 启动失败：gameId=${game.id}, leProcPath=$leProcPath, targetExe=$exePath',
        e,
      );
      return null;
    }
  }

  Future<GameLaunchResult> _launchNormal(
    Game game,
    List<RunningProcess> snapshotBefore,
  ) async {
    final lockedLauncher = game.gameLauncher;
    if (game.launcherLocked &&
        lockedLauncher != null &&
        lockedLauncher.isNotEmpty) {
      final file = File(lockedLauncher);
      if (await file.exists()) {
        AppLogger.instance.info(
          _logTag,
          '使用锁定启动器：gameId=${game.id}, launcherPath=$lockedLauncher',
        );
        return _launchCandidate(
          game: game,
          launcherPath: lockedLauncher,
          snapshotBefore: snapshotBefore,
          locked: true,
          updateStoredLauncher: false,
        );
      }
    }

    final gameDir = Directory(game.path);
    if (!await gameDir.exists()) {
      AppLogger.instance.warning(
        _logTag,
        '普通启动失败：游戏目录不存在，gameId=${game.id}, path=${game.path}',
      );
      return GameLaunchResult(
          launched: false, game: game, processSnapshotBefore: snapshotBefore);
    }

    final toolBat = File(p.join(game.path, '与工具一同启动.bat'));
    if (await toolBat.exists()) {
      AppLogger.instance.info(
        _logTag,
        '使用工具 bat 启动：gameId=${game.id}, launcherPath=${toolBat.path}',
      );
      return _launchCandidate(
        game: game,
        launcherPath: toolBat.path,
        snapshotBefore: snapshotBefore,
        locked: false,
        updateStoredLauncher: true,
      );
    }

    await for (final entity in gameDir.list()) {
      if (entity is File) {
        final fileName = p.basename(entity.path).toLowerCase();
        if (fileName.endsWith('.bat') &&
            (fileName.contains('启动') || fileName.contains('开始'))) {
          AppLogger.instance.info(
            _logTag,
            '使用目录内 bat 启动：gameId=${game.id}, launcherPath=${entity.path}',
          );
          return _launchCandidate(
            game: game,
            launcherPath: entity.path,
            snapshotBefore: snapshotBefore,
            locked: false,
            updateStoredLauncher: true,
          );
        }
      }
    }

    for (final exeName in _fallbackExeNames) {
      final exeFile = File(p.join(game.path, exeName));
      if (await exeFile.exists()) {
        AppLogger.instance.info(
          _logTag,
          '使用兜底 exe 启动：gameId=${game.id}, launcherPath=${exeFile.path}',
        );
        return _launchCandidate(
          game: game,
          launcherPath: exeFile.path,
          snapshotBefore: snapshotBefore,
          locked: false,
          updateStoredLauncher: true,
        );
      }
    }

    final exePath = await _savePathService.findGameExe(game.path);
    if (exePath != null) {
      AppLogger.instance.info(
        _logTag,
        '使用自动扫描 exe 启动：gameId=${game.id}, launcherPath=$exePath',
      );
      return _launchCandidate(
        game: game,
        launcherPath: exePath,
        snapshotBefore: snapshotBefore,
        locked: false,
        updateStoredLauncher: true,
      );
    }

    AppLogger.instance.warning(
      _logTag,
      '普通启动失败：未找到启动器，gameId=${game.id}, path=${game.path}',
    );
    return GameLaunchResult(
        launched: false, game: game, processSnapshotBefore: snapshotBefore);
  }

  Future<GameLaunchResult> _launchCandidate({
    required Game game,
    required String launcherPath,
    required List<RunningProcess> snapshotBefore,
    required bool locked,
    required bool updateStoredLauncher,
  }) async {
    try {
      AppLogger.instance.info(
        _logTag,
        '执行启动器：gameId=${game.id}, launcherPath=$launcherPath, locked=$locked, '
        'updateStoredLauncher=$updateStoredLauncher',
      );
      final startedProcessId = await _startLauncher(launcherPath);
      AppLogger.instance.info(
        _logTag,
        '启动器进程已创建：gameId=${game.id}, launcherPath=$launcherPath, startedProcessId=$startedProcessId',
      );
      var updatedGame = game;
      if (updateStoredLauncher && game.id != null) {
        await _gameRepository.updateGameLauncher(game.id!, launcherPath, false);
        updatedGame =
            game.copyWith(gameLauncher: launcherPath, launcherLocked: false);
      }
      return GameLaunchResult(
        launched: true,
        game: updatedGame,
        processSnapshotBefore: snapshotBefore,
        launchedPath: launcherPath,
        trackingHintPath: launcherPath,
        launcherWasLocked: locked,
        startedProcessId: startedProcessId,
      );
    } catch (e) {
      AppLogger.instance.error(
        _logTag,
        '执行启动器失败：gameId=${game.id}, launcherPath=$launcherPath',
        e,
      );
      return GameLaunchResult(
        launched: false,
        game: game,
        processSnapshotBefore: snapshotBefore,
        launchedPath: launcherPath,
        trackingHintPath: launcherPath,
        launcherWasLocked: locked,
        error: e,
      );
    }
  }

  Future<int> _startLauncher(
    String executablePath, {
    List<String> args = const [],
    String? workingDirectory,
  }) async {
    final extension = p.extension(executablePath).toLowerCase();
    final runInShell = extension == '.bat' || extension == '.cmd';
    final process = await Process.start(
      executablePath,
      args,
      workingDirectory: workingDirectory ?? p.dirname(executablePath),
      runInShell: runInShell,
      mode: ProcessStartMode.detached,
    );
    return process.pid;
  }

  Future<String?> _findLocaleTargetExe(Game game) async {
    final launcher = game.gameLauncher;
    if (game.launcherLocked && launcher != null && launcher.isNotEmpty) {
      final file = File(launcher);
      if (await file.exists() &&
          p.extension(launcher).toLowerCase() == '.exe') {
        return launcher;
      }
    }

    final gameDir = Directory(game.path);
    if (!await gameDir.exists()) return null;

    for (final exeName in _fallbackExeNames) {
      final exeFile = File(p.join(game.path, exeName));
      if (await exeFile.exists()) return exeFile.path;
    }

    await for (final entity in gameDir.list()) {
      if (entity is File && p.extension(entity.path).toLowerCase() == '.exe') {
        return entity.path;
      }
    }

    return null;
  }

  static const _fallbackExeNames = [
    'game.exe',
    'Game.exe',
    'launcher.exe',
    'launch.exe',
    'player.exe',
    'play.exe',
  ];

  bool _samePath(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
    return _normalizePath(a) == _normalizePath(b);
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
}
