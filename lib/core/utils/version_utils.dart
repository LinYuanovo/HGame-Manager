int compareVersions(String v1, String v2) {
  final parts1 = _parseVersionParts(v1);
  final parts2 = _parseVersionParts(v2);
  final maxLength =
      parts1.length > parts2.length ? parts1.length : parts2.length;

  for (var i = 0; i < maxLength; i++) {
    final p1 = i < parts1.length ? parts1[i] : 0;
    final p2 = i < parts2.length ? parts2[i] : 0;
    if (p1 != p2) return p1.compareTo(p2);
  }
  return 0;
}

List<int> _parseVersionParts(String version) {
  final cleaned = version.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return [];
  return cleaned.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}
