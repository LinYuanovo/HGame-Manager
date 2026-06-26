import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/models.dart';
import '../database/database_helper.dart';

class PlayTimeTracker {
  static Timer? _timer;
  static Game? _currentGame;
  static int _sessionSeconds = 0;
  static int _lastSaveSeconds = 0;
  static const int _saveInterval = 600; // 10分钟 = 600秒
  static const int _checkInterval = 30; // 30秒检测一次

  /// 开始追踪游戏游玩时长
  static void startTracking(Game game) {
    // 如果正在追踪其他游戏，先停止
    if (_currentGame != null && _currentGame?.id != game.id) {
      stopTracking();
    }

    _currentGame = game;
    _sessionSeconds = 0;
    _lastSaveSeconds = 0;

    // 启动定时器
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: _checkInterval), _onTick);
  }

  /// 停止追踪并保存
  static Future<void> stopTracking() async {
    _timer?.cancel();
    _timer = null;

    if (_currentGame != null && _sessionSeconds > 0) {
      await _saveProgress();
    }

    _currentGame = null;
    _sessionSeconds = 0;
    _lastSaveSeconds = 0;
  }

  /// 定时器回调
  static void _onTick(Timer timer) async {
    if (_currentGame == null) return;

    // 检测游戏进程是否运行
    final isRunning = await _isGameRunning(_currentGame!);

    if (isRunning) {
      _sessionSeconds += _checkInterval;

      // 检查是否需要保存到数据库
      if (_sessionSeconds - _lastSaveSeconds >= _saveInterval) {
        await _saveProgress();
      }
    } else {
      // 游戏已关闭，停止追踪
      await stopTracking();
    }
  }

  /// 保存进度到数据库
  static Future<void> _saveProgress() async {
    if (_currentGame == null || _sessionSeconds <= 0) return;

    try {
      final db = await DatabaseHelper.database;
      final newDuration = _currentGame!.playDuration + _sessionSeconds;

      await db.update(
        'games',
        {'play_duration': newDuration},
        where: 'id = ?',
        whereArgs: [_currentGame!.id],
      );

      _lastSaveSeconds = _sessionSeconds;
    } catch (e) {
      // 记录错误但不中断
      print('保存游玩时长失败: $e');
    }
  }

  /// 检测游戏进程是否运行
  static Future<bool> _isGameRunning(Game game) async {
    try {
      String processName;

      // 优先检测 game_launcher
      if (game.gameLauncher != null && game.gameLauncher!.isNotEmpty) {
        final launcherPath = game.gameLauncher!;

        // 如果是 bat 文件，检测同级目录下的 EXE
        if (launcherPath.toLowerCase().endsWith('.bat')) {
          final dir = p.dirname(launcherPath);
          final exeNames = [
            'MTool_Game.exe',
            'Game.exe',
            'game.exe',
            'nw.exe',
            'launcher.exe',
            'launch.exe',
          ];

          for (final exeName in exeNames) {
            final exePath = p.join(dir, exeName);
            if (await File(exePath).exists()) {
              processName = p.basenameWithoutExtension(exePath);
              if (await _isProcessRunning(processName)) {
                return true;
              }
            }
          }
          return false;
        }

        // 如果是 EXE 文件，直接检测
        processName = p.basenameWithoutExtension(launcherPath);
      } else {
        // 检测游戏目录下的主 EXE
        final dir = Directory(game.path);
        if (await dir.exists()) {
          final exeFiles = await dir
              .list()
              .where((entity) => entity.path.toLowerCase().endsWith('.exe'))
              .toList();

          if (exeFiles.isNotEmpty) {
            processName = p.basenameWithoutExtension(exeFiles.first.path);
          } else {
            return false;
          }
        } else {
          return false;
        }
      }

      return await _isProcessRunning(processName);
    } catch (e) {
      // 检测失败视为游戏未运行
      return false;
    }
  }

  /// 检测指定进程是否运行
  static Future<bool> _isProcessRunning(String processName) async {
    try {
      final result = await Process.run('tasklist', ['/FI', 'IMAGENAME eq $processName.exe']);
      return result.stdout.toString().contains(processName);
    } catch (e) {
      return false;
    }
  }

  /// 获取当前追踪的游戏
  static Game? get currentGame => _currentGame;

  /// 获取当前会话已记录的秒数
  static int get sessionSeconds => _sessionSeconds;
}
