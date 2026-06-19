import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as path;

class SavePathService {
  static const List<String> _commonEngineExes = [
    'UnityCrashHandler64.exe',
    'UnityCrashHandler32.exe',
    'crashpad_handler.exe',
    'crash_handler.exe',
    'game.exe',
    'launch.exe',
    'launcher.exe',
    'setup.exe',
    'uninstall.exe',
    'unins000.exe',
    'unins001.exe',
    'nw.exe',
    'cef_simple.exe',
    'renderdoc.exe',
    'vcredist_x64.exe',
    'vcredist_x86.exe',
    'dxwebsetup.exe',
    'oalinst.exe',
    'xnafx40_redist.msi',
  ];

  static const List<String> _versionSuffixPatterns = [
    r'-\d+$',
    r'-\d+bit$',
    r'_\d+bit$',
    r'_x\d+$',
    r'[-_]?(32|64)(bit)?$',
    r'\s+\(.*\)$',
  ];

  String? extractGameNameFromExe(String gamePath) {
    final dir = Directory(gamePath);
    if (!dir.existsSync()) return null;

    final exeFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.exe'))
        .toList();

    for (final exe in exeFiles) {
      final exeName = path.basename(exe.path);
      if (_commonEngineExes.contains(exeName.toLowerCase())) continue;
      if (exeName.toLowerCase().contains('unity') ||
          exeName.toLowerCase().contains('unreal') ||
          exeName.toLowerCase().contains('godot') ||
          exeName.toLowerCase().contains('renpy')) {
        continue;
      }

      var gameName = path.basenameWithoutExtension(exe.path);
      gameName = _cleanGameName(gameName);
      if (gameName.isNotEmpty) return gameName;
    }

    return null;
  }

  String? findGameExe(String gamePath) {
    final dir = Directory(gamePath);
    if (!dir.existsSync()) return null;

    final exeFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.exe'))
        .toList();

    for (final exe in exeFiles) {
      final exeName = path.basename(exe.path);
      if (_commonEngineExes.contains(exeName.toLowerCase())) continue;
      if (exeName.toLowerCase().contains('unity') ||
          exeName.toLowerCase().contains('unreal') ||
          exeName.toLowerCase().contains('godot') ||
          exeName.toLowerCase().contains('renpy')) continue;
      return exe.path;
    }

    return null;
  }

  String _cleanGameName(String name) {
    var cleaned = name;
    for (final pattern in _versionSuffixPatterns) {
      cleaned = cleaned.replaceAll(RegExp(pattern, caseSensitive: false), '');
    }
    cleaned = cleaned.replaceAll(RegExp(r'[-_]\s*$'), '');
    return cleaned.trim();
  }

  Future<String?> findSavePath(String gamePath, String? gameTitle) async {
    final gameName = extractGameNameFromExe(gamePath) ?? gameTitle;
    if (gameName == null || gameName.isEmpty) {
      debugPrint('[SavePath] 游戏名为空，跳过扫描');
      return null;
    }

    debugPrint('[SavePath] 开始扫描存档，游戏名: $gameName，游戏路径: $gamePath');

    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    final localLowPath = path.join(userProfile, 'AppData', 'LocalLow');
    final localPath = path.join(userProfile, 'AppData', 'Local');
    final roamingPath = path.join(userProfile, 'AppData', 'Roaming');

    final candidates = <String>[];
    final gameNameLower = gameName.toLowerCase();

    final searchPaths = [localLowPath, localPath, roamingPath];
    debugPrint('[SavePath] 搜索目录: $searchPaths');

    for (final basePath in searchPaths) {
      if (!Directory(basePath).existsSync()) {
        debugPrint('[SavePath] 目录不存在，跳过: $basePath');
        continue;
      }

      debugPrint('[SavePath] 搜索目录: $basePath');
      try {
        // 遍历子目录，查找大小写不敏感匹配
        await for (final entity in Directory(basePath).list()) {
          if (entity is! Directory) continue;
          try {
            final dirName = path.basename(entity.path).toLowerCase();
            // 检查目录名是否与游戏名匹配（大小写不敏感）
            if (dirName == gameNameLower) {
              debugPrint('[SavePath] 大小写不敏感匹配成功: ${entity.path}');
              candidates.add(entity.path);
            } else {
              // 检查子目录（如 Diamond Visual/SPITE）
              // 遍历子目录，使用实际目录名进行匹配
              await for (final subEntity in entity.list()) {
                if (subEntity is! Directory) continue;
                final subDirName = path.basename(subEntity.path).toLowerCase();
                if (subDirName == gameNameLower) {
                  debugPrint('[SavePath] 子目录大小写不敏感匹配成功: ${subEntity.path}');
                  candidates.add(subEntity.path);
                }
              }
            }
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[SavePath] 搜索目录出错: $basePath, 错误: $e');
      }
    }

    debugPrint('[SavePath] 找到 ${candidates.length} 个候选路径: $candidates');

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final aScore = _calculateConfidence(a, gameName);
      final bScore = _calculateConfidence(b, gameName);
      return bScore.compareTo(aScore);
    });

    debugPrint('[SavePath] 最佳匹配: ${candidates.first}');
    return candidates.first;
  }

  double _calculateConfidence(String savePath, String gameName) {
    double score = 0.0;
    final dirName = path.basename(savePath).toLowerCase();

    if (dirName == gameName.toLowerCase()) {
      score += 50.0;
    } else if (dirName.contains(gameName.toLowerCase())) {
      score += 30.0;
    }

    try {
      final dir = Directory(savePath);
      final children = dir.listSync().map((e) => path.basename(e.path).toLowerCase()).toList();

      final saveIndicators = ['save', 'saves', 'savegame', 'savegames', 'userdata', 'config', 'settings', 'profiles'];
      for (final child in children) {
        for (final indicator in saveIndicators) {
          if (child.contains(indicator)) {
            score += 10.0;
            break;
          }
        }
      }

      if (children.any((c) => c.endsWith('.sav') || c.endsWith('.save') || c.endsWith('.dat'))) {
        score += 15.0;
      }

      score += children.length.clamp(0, 5).toDouble();
    } catch (_) {}

    return score;
  }

  Future<String?> scanWithConfidence(String gamePath, String? gameTitle) async {
    final result = await findSavePath(gamePath, gameTitle);
    if (result == null) return null;

    final gameName = extractGameNameFromExe(gamePath) ?? gameTitle ?? '';
    final confidence = _calculateConfidence(result, gameName);

    if (confidence < 30.0) return null;
    return result;
  }
}
