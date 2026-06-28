import 'package:flutter/foundation.dart';

/// 内容搜索匹配位置
@immutable
class ContentSearchMatch {
  final String sectionKey;    // 区域键（'intro', 'guide', 'features', 'changelog'）
  final int lineIndex;        // 行索引
  final int charOffset;       // 行内字符偏移
  final int matchLength;      // 匹配长度

  const ContentSearchMatch({
    required this.sectionKey,
    required this.lineIndex,
    required this.charOffset,
    required this.matchLength,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContentSearchMatch &&
        other.sectionKey == sectionKey &&
        other.lineIndex == lineIndex &&
        other.charOffset == charOffset &&
        other.matchLength == matchLength;
  }

  @override
  int get hashCode => Object.hash(sectionKey, lineIndex, charOffset, matchLength);
}

/// 内容搜索引擎（纯逻辑，无UI依赖）
class ContentSearchEngine {
  /// 媒体标签前缀列表
  static const _mediaPrefixes = ['[图片:', '[视频:'];

  /// 查找所有匹配项
  static List<ContentSearchMatch> findAll({
    required String query,
    required Map<String, String?> sections,
    bool caseSensitive = false,
  }) {
    if (query.trim().isEmpty) return [];

    final regex = RegExp(RegExp.escape(query), caseSensitive: caseSensitive);
    final matches = <ContentSearchMatch>[];

    for (final entry in sections.entries) {
      final content = entry.value;
      if (content == null || content.isEmpty) continue;

      final lines = content.split('\n');
      for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
        final line = lines[lineIdx];
        // 跳过媒体标签行
        if (_mediaPrefixes.any((prefix) => line.startsWith(prefix))) continue;

        for (final match in regex.allMatches(line)) {
          matches.add(ContentSearchMatch(
            sectionKey: entry.key,
            lineIndex: lineIdx,
            charOffset: match.start,
            matchLength: match.end - match.start,
          ));
        }
      }
    }

    return matches;
  }
}
