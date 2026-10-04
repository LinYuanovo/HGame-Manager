import 'dart:io';

/// 拖入分流结果：游戏目录列表 + 预设刮削关键词
class DropImportResult {
  /// 去重后的游戏目录列表（保持首次出现顺序，存放规范化后的路径）
  final List<String> folderPaths;

  /// 游戏目录 -> 预设刮削关键词（来自 exe 文件名）
  ///
  /// key 与 [folderPaths] 中存放的规范化路径完全一致，
  /// 调用方可直接 presetKeywords[folderPath] 查询
  final Map<String, String> presetKeywords;

  const DropImportResult({
    required this.folderPaths,
    required this.presetKeywords,
  });
}

/// 拖入路径分流工具（文件夹/EXE 拖入快速添加游戏）
class DropImportUtils {
  const DropImportUtils._();

  /// 规范化拖入路径：统一分隔符为 `\`、去除末尾分隔符、保留原始大小写
  ///
  /// 去重比较时由调用方再转小写（Windows 路径不区分大小写）
  static String normalizeDropPath(String p) {
    // 统一分隔符为反斜杠
    var normalized = p.trim().replaceAll('/', '\\');
    // 去除末尾分隔符，但保留驱动器根路径（如 C:\）
    while (normalized.length > 1 && normalized.endsWith('\\')) {
      if (normalized.length == 3 && normalized[1] == ':') break;
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 将拖入的路径列表分流为游戏目录列表与预设关键词
  ///
  /// 分流规则：
  /// - 目录 → 直接作为游戏目录
  /// - `.exe` 文件（大小写不敏感）→ 其父目录作为游戏目录，
  ///   并以 exe 文件名（去扩展名、`_` 转空格、trim）生成预设关键词
  /// - 其他情况（不存在的路径、非 exe 文件）→ 忽略
  ///
  /// 去重：同一目录（忽略大小写、分隔符与末尾分隔符差异）只出现一次；
  /// 预设关键词取第一个出现的 exe，后续 exe 不覆盖；
  /// 直接拖入的目录不产生预设关键词
  static DropImportResult resolveDroppedPaths(List<String> paths) {
    final folderPaths = <String>[];
    final presetKeywords = <String, String>{};
    // 已收录目录的比较键（小写），用于忽略大小写去重
    final seenKeys = <String>{};

    for (final rawPath in paths) {
      if (rawPath.trim().isEmpty) continue;

      // 目录：直接作为游戏目录，不产生预设关键词
      if (FileSystemEntity.isDirectorySync(rawPath)) {
        final normalized = normalizeDropPath(rawPath);
        if (seenKeys.add(normalized.toLowerCase())) {
          folderPaths.add(normalized);
        }
        continue;
      }

      // 文件：仅识别 .exe（大小写不敏感），其父目录作为游戏目录
      if (FileSystemEntity.isFileSync(rawPath) &&
          rawPath.toLowerCase().endsWith('.exe')) {
        final normalizedExe = normalizeDropPath(rawPath);
        final parent = _parentDirOf(normalizedExe);
        if (parent.isEmpty) continue;
        if (seenKeys.add(parent.toLowerCase())) {
          folderPaths.add(parent);
        }
        // 预设关键词取第一个出现的 exe，后续 exe 不覆盖
        presetKeywords.putIfAbsent(parent, () => _exeKeywordOf(normalizedExe));
        continue;
      }

      // 其他情况（不存在的路径、非 exe 文件）忽略
    }

    return DropImportResult(
      folderPaths: folderPaths,
      presetKeywords: presetKeywords,
    );
  }

  /// 提取已规范化 exe 路径的父目录（规范化路径，无末尾分隔符）
  static String _parentDirOf(String normalizedExePath) {
    final sepIndex = normalizedExePath.lastIndexOf('\\');
    if (sepIndex <= 0) return '';
    // 驱动器根目录（如 C:\）保留末尾分隔符
    if (sepIndex == 2 && normalizedExePath[1] == ':') {
      return normalizedExePath.substring(0, 3);
    }
    return normalizedExePath.substring(0, sepIndex);
  }

  /// 从已规范化 exe 路径生成预设刮削关键词：去扩展名、`_` 转空格、trim
  static String _exeKeywordOf(String normalizedExePath) {
    final fileName =
        normalizedExePath.substring(normalizedExePath.lastIndexOf('\\') + 1);
    final dotIndex = fileName.lastIndexOf('.');
    final stem = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    return stem.replaceAll('_', ' ').trim();
  }
}
