class ClearedGamePathUtils {
  const ClearedGamePathUtils._();

  static bool hasBackupSegment(String gamePath) {
    return _segments(gamePath).any((segment) => segment == 'backup');
  }

  static bool isSameOrChildPath(String candidatePath, String rootPath) {
    final candidate = _normalizedPath(candidatePath);
    final root = _normalizedPath(rootPath);
    if (candidate.isEmpty || root.isEmpty) return false;
    return candidate == root || candidate.startsWith('$root/');
  }

  static String looseNameKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-\.]+'), '')
        .replaceAll(RegExp(r'[<>:"/\\|?*\[\]（）()]'), '');
  }

  static bool isLikelyBackupForLocalName(
    String backupFolderName,
    String localName,
  ) {
    final backupKey = looseNameKey(backupFolderName);
    final localKey = looseNameKey(localName);
    if (backupKey.length < 10 || localKey.length < 10) return false;
    return backupKey == localKey || backupKey.contains(localKey);
  }

  static bool isLikelySameGameName(String left, String right) {
    final leftKey = looseNameKey(left);
    final rightKey = looseNameKey(right);
    if (leftKey.length < 10 || rightKey.length < 10) return false;
    return leftKey == rightKey ||
        leftKey.contains(rightKey) ||
        rightKey.contains(leftKey);
  }

  static String _normalizedPath(String value) {
    return value
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+'), '/')
        .replaceAll(RegExp(r'/$'), '')
        .toLowerCase();
  }

  static List<String> _segments(String gamePath) {
    return gamePath
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map((segment) => segment.toLowerCase())
        .toList();
  }
}
