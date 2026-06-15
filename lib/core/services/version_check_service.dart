// TODO: Add these imports when search methods are implemented (Task 5):
// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:html/parser.dart' as html_parser;
// import '../utils/proxy_client.dart';
// import '../utils/app_settings.dart';
// import '../../scraper/parse_utils.dart';

class VersionCheckResult {
  final String siteName;
  final String? maxVersion;
  final String? downloadUrl;
  final String? postTitle;

  VersionCheckResult({
    required this.siteName,
    this.maxVersion,
    this.downloadUrl,
    this.postTitle,
  });
}

class VersionCheckService {
  List<String> extractKeywords(String title) {
    final tokens = title.split(RegExp(r'\s+'));

    const filterWords = ['官中', '+', '存档', '汉化', 'steam', '官方'];
    final filtered = tokens.where((t) {
      return !filterWords.any((w) => t.toLowerCase().contains(w.toLowerCase()));
    }).toList();

    final subTokens = <String>[];
    for (final token in filtered) {
      subTokens.addAll(token.split(RegExp(r'[/\-]')));
    }

    final merged = <String>[];
    final buffer = StringBuffer();

    for (final token in subTokens) {
      if (token.isEmpty) continue;
      final isEnglish = RegExp(r'^[a-zA-Z0-9\s]+$').hasMatch(token);
      if (isEnglish) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(token);
      } else {
        if (buffer.isNotEmpty) {
          merged.add(buffer.toString().trim());
          buffer.clear();
        }
        merged.add(token);
      }
    }
    if (buffer.isNotEmpty) {
      merged.add(buffer.toString().trim());
    }

    return merged.where((k) => k.isNotEmpty).toList();
  }

  int compareVersions(String v1, String v2) {
    final parts1 = _parseVersionParts(v1);
    final parts2 = _parseVersionParts(v2);

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) return p1.compareTo(p2);
    }
    return 0;
  }

  List<int> _parseVersionParts(String version) {
    final cleaned = version.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return [];
    return cleaned.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }
}
