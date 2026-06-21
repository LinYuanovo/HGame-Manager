import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as path;

class SavePathService {
  String? _lastMatchedKeyword;
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
    'config.exe',
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
          exeName.toLowerCase().contains('renpy') ||
          exeName.toLowerCase().startsWith('mtool_')) {
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
          exeName.toLowerCase().contains('renpy') ||
          exeName.toLowerCase().startsWith('mtool_')) {
        continue;
      }
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
    final exeGameName = extractGameNameFromExe(gamePath);
    final gameName = exeGameName ?? gameTitle;
    
    if (gameName == null || gameName.isEmpty) {
      debugPrint('[SavePath] 游戏名为空，尝试本地存档检测');
      return _findLocalSavePath(gamePath);
    }

    debugPrint('[SavePath] 开始扫描存档，游戏名: $gameName，游戏路径: $gamePath');

    // 1. 先用游戏名搜索 AppData
    var result = await _searchInAppData(gameName);
    if (result != null) return result;

    // 2. 搜索本地存档
    result = _findLocalSavePath(gamePath);
    if (result != null) return result;

    // 3. 如果游戏名来自exe且有metadata title，用title分词回退搜索AppData
    if (exeGameName != null && gameTitle != null && gameTitle.isNotEmpty && gameTitle != gameName) {
      debugPrint('[SavePath] 使用metadata title分词回退搜索: $gameTitle');
      result = await _searchWithTokenizedTitle(gameTitle);
      if (result != null) return result;
    }

    debugPrint('[SavePath] 未找到存档路径');
    return null;
  }

  Future<String?> _searchWithTokenizedTitle(String title) async {
    // 先用完整title搜索
    debugPrint('[SavePath] 尝试完整title: $title');
    var result = await _searchInAppData(title);
    if (result != null) return result;

    // 按空格、_、-分词，每次去掉最后一个词
    final separators = [' ', '_', '-'];
    for (final sep in separators) {
      final tokens = title.split(RegExp(RegExp.escape(sep)));
      if (tokens.length <= 1) continue;

      // 逐步去掉最后一个词
      for (int i = tokens.length - 1; i >= 1; i--) {
        final partialTitle = tokens.sublist(0, i).join(sep);
        debugPrint('[SavePath] 尝试分词($sep): $partialTitle');
        result = await _searchInAppData(partialTitle);
        if (result != null) return result;
      }
    }

    return null;
  }

  Future<String?> _searchInAppData(String keyword) async {
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    final localLowPath = path.join(userProfile, 'AppData', 'LocalLow');
    final localPath = path.join(userProfile, 'AppData', 'Local');
    final roamingPath = path.join(userProfile, 'AppData', 'Roaming');

    final candidates = <String>[];
    final keywordLower = keyword.toLowerCase();

    final searchPaths = [localLowPath, localPath, roamingPath];
    debugPrint('[SavePath] 搜索AppData，关键词: $keyword');

    for (final basePath in searchPaths) {
      if (!Directory(basePath).existsSync()) continue;

      try {
        await for (final entity in Directory(basePath).list()) {
          if (entity is! Directory) continue;
          try {
            final dirName = path.basename(entity.path).toLowerCase();
            if (dirName == keywordLower) {
              debugPrint('[SavePath] 大小写不敏感匹配成功: ${entity.path}');
              candidates.add(entity.path);
            } else if (dirName.contains(keywordLower)) {
              debugPrint('[SavePath] 模糊匹配成功（包含关键词）: ${entity.path}');
              candidates.add(entity.path);
            } else {
              await for (final subEntity in entity.list()) {
                if (subEntity is! Directory) continue;
                final subDirName = path.basename(subEntity.path).toLowerCase();
                if (subDirName == keywordLower || subDirName.contains(keywordLower)) {
                  debugPrint('[SavePath] 子目录匹配成功: ${subEntity.path}');
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

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final aScore = _calculateConfidence(a, keyword);
      final bScore = _calculateConfidence(b, keyword);
      return bScore.compareTo(aScore);
    });

    debugPrint('[SavePath] 最佳匹配: ${candidates.first}');
    _lastMatchedKeyword = keyword;
    return candidates.first;
  }

  double _calculateConfidence(String savePath, String gameName) {
    double score = 0.0;
    final dirName = path.basename(savePath).toLowerCase();

    final gameNameLower = gameName.toLowerCase();
    if (dirName == gameNameLower) {
      score += 50.0;
    } else if (dirName.contains(gameNameLower)) {
      final idx = dirName.indexOf(gameNameLower);
      if (idx == 0) {
        score += 40.0;
      } else {
        score += 30.0;
      }
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

  String? _findLocalSavePath(String gamePath) {
    final saveExtensions = ['.rxdata', '.rvdata2', '.rpgsave', '.rmmzsave'];
    
    // 检查游戏根目录下的 save 文件夹（大小写不敏感）
    final localSavePath = _findFolderIgnoreCase(gamePath, 'save');
    if (localSavePath != null && _isValidSaveFolder(localSavePath, saveExtensions)) {
      debugPrint('[SavePath] 本地存档匹配成功: $localSavePath');
      return localSavePath;
    }
    
    // 检查 www/save 文件夹（大小写不敏感）
    final wwwDir = _findFolderIgnoreCase(gamePath, 'www');
    if (wwwDir != null) {
      final wwwSavePath = _findFolderIgnoreCase(wwwDir, 'save');
      if (wwwSavePath != null && _isValidSaveFolder(wwwSavePath, saveExtensions)) {
        debugPrint('[SavePath] 本地存档匹配成功: $wwwSavePath');
        return wwwSavePath;
      }
    }
    
    debugPrint('[SavePath] 本地存档检测未找到有效存档');
    return null;
  }
  
  String? _findFolderIgnoreCase(String parentPath, String targetName) {
    final targetLower = targetName.toLowerCase();
    try {
      final dir = Directory(parentPath);
      if (!dir.existsSync()) return null;
      
      for (final entity in dir.listSync()) {
        if (entity is Directory) {
          final dirName = path.basename(entity.path).toLowerCase();
          if (dirName == targetLower) {
            return entity.path;
          }
        }
      }
    } catch (_) {}
    return null;
  }
  
  bool _isValidSaveFolder(String folderPath, List<String> extensions) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return false;
    
    try {
      final files = dir.listSync().whereType<File>();
      for (final file in files) {
        final fileName = file.path.toLowerCase();
        for (final ext in extensions) {
          if (fileName.endsWith(ext)) {
            return true;
          }
        }
      }
    } catch (_) {}
    
    return false;
  }

  Future<String?> scanWithConfidence(String gamePath, String? gameTitle) async {
    _lastMatchedKeyword = null;
    final result = await findSavePath(gamePath, gameTitle);
    if (result == null) return null;

    final gameName = _lastMatchedKeyword ?? extractGameNameFromExe(gamePath) ?? gameTitle ?? '';
    final confidence = _calculateConfidence(result, gameName);

    if (confidence < 30.0) return null;
    return result;
  }
}
