import 'dart:io';
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
    if (gameName == null || gameName.isEmpty) return null;

    final localLowPath = path.join(
      Platform.environment['USERPROFILE'] ?? '',
      'AppData',
      'LocalLow',
    );
    final localPath = path.join(
      Platform.environment['USERPROFILE'] ?? '',
      'AppData',
      'Local',
    );

    final candidates = <String>[];

    for (final basePath in [localLowPath, localPath]) {
      if (!Directory(basePath).existsSync()) continue;

      try {
        final directMatch = path.join(basePath, gameName);
        if (Directory(directMatch).existsSync()) {
          candidates.add(directMatch);
        }

        await for (final entity in Directory(basePath).list()) {
          if (entity is! Directory) continue;
          try {
            final subDir = path.join(entity.path, gameName);
            if (Directory(subDir).existsSync()) {
              candidates.add(subDir);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final aScore = _calculateConfidence(a, gameName);
      final bScore = _calculateConfidence(b, gameName);
      return bScore.compareTo(aScore);
    });

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
