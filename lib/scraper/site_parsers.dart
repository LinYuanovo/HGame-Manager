import 'package:html/dom.dart';
import 'html_parser.dart';
import 'parse_utils.dart';
import 'dlsite_parser.dart';
import '../core/services/app_logger.dart';
import '../core/utils/app_settings.dart';

const kValidSeriesTypes = ['RPG', 'ADV', 'ACT', 'SLG', 'AVG', 'FPS', 'TPS'];

String _elementText(Element element) {
  final buffer = StringBuffer();
  for (final node in element.nodes) {
    if (node is Text) {
      buffer.write(node.text);
    } else if (node is Element && node.localName == 'br') {
      buffer.write('\n');
    } else if (node is Element) {
      buffer.write(_elementText(node));
    }
  }
  return buffer.toString();
}

final _copyrightPattern = RegExp(r'Copyright\s*©|All\s+rights\s+reserved|版权所有|ICP备|粤ICP|京ICP', caseSensitive: false);
final _unzipPattern = RegExp(r'(?:默认)?解压(?:码|密码)|(?<!提取)密码[：:]?\s*\S+');

bool _isCopyrightText(String text) => _copyrightPattern.hasMatch(text);
bool _containsUnzipCode(String text) => _unzipPattern.hasMatch(text);

String? normalizeSeries(String? series) {
  if (series == null || series.isEmpty) return null;
  final upper = series.toUpperCase().trim();
  // Direct match
  if (kValidSeriesTypes.contains(upper)) return upper;
  // Try to find a valid type that's contained in the series name
  for (final valid in kValidSeriesTypes) {
    if (upper.contains(valid)) return valid;
  }
  // No match found - don't create a series tag
  return null;
}

/// Helper class for tracking section marker positions in text.
class _MarkerPos {
  final String marker;
  final int pos;
  _MarkerPos(this.marker, this.pos);
}

/// Parser for ACG嘤嘤怪 (acgyyg.ru / acgying.com)
/// WordPress + LoLiMeow theme with structured post content using badge spans.
class AcgYingParser extends SiteParser {
  @override
  String get domain => 'acgyyg';

  @override
  GameInfo? parseGameInfo(Document document, String url) {
    final titleEl = document.querySelector('h3.post-title');
    var rawTitle = titleEl?.text.trim();
    if (rawTitle == null) return null;

    final tags = extractBracketsFromTitle(rawTitle) ?? [];
    final category = normalizeSeries(tags.isNotEmpty ? tags.first : null);

    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();

    final version = extractVersion(cleanTitle);
    final titleWithoutVersion = version != null ? removeVersionFromTitle(cleanTitle) : cleanTitle;

    final postContent = document.querySelector('div.post-content');
    String? description;
    List<String> features = [];
    String? changelog;
    final screenshots = <String>[];
    final downloads = <DownloadLink>[];
    String? unzipCode;

    if (postContent != null) {
      final fullText = postContent.text;
      final sections = _splitSections(fullText);

      description = sections['游戏介绍'];
      final featuresText = sections['游戏特点'];
      if (featuresText != null) {
        features = featuresText
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
      }
      changelog = sections['更新内容'];

      final linksSection = sections['链接'];
      if (linksSection != null) {
        downloads.addAll(extractDownloadLinks(linksSection));
      }

      unzipCode = extractUnzipCode(fullText);

      final images = postContent.querySelectorAll('img');
      for (final img in images) {
        final src = img.attributes['src'] ?? '';
        if (src.isNotEmpty &&
            src.contains('wp-content/uploads') &&
            !src.endsWith('.svg') &&
            !src.endsWith('.ico')) {
          screenshots.add(src);
        }
      }
    }

    final postMeta = document.querySelector('div.post-meta');
    String? publishDate;
    if (postMeta != null) {
      final dateMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(postMeta.text);
      if (dateMatch != null) {
        publishDate = dateMatch.group(1);
      }
    }

    if (unzipCode != null && downloads.isNotEmpty) {
      final last = downloads.last;
      downloads[downloads.length - 1] = DownloadLink(
        url: last.url,
        label: last.label,
        provider: last.provider,
        password: last.password,
        unzipCode: unzipCode,
      );
    }

    return GameInfo(
      title: titleWithoutVersion,
      version: version,
      tags: tags,
      category: category,
      description: description,
      features: features,
      changelog: changelog,
      screenshots: screenshots,
      downloads: downloads,
      publishDate: publishDate,
      sourceUrl: url,
    );
  }

  @override
  GameMetadata parse(Document document, String url) {
    final metadata = GameMetadata();

    // Title from h3.post-title
    final titleEl = document.querySelector('h3.post-title');
    metadata.title = titleEl?.text.trim();

    // Extract tags and series from title brackets like 【ACT/中文/全动态】
    if (metadata.title != null) {
      final bracketMatch =
          RegExp(r'【([^】]+)】').firstMatch(metadata.title!);
      if (bracketMatch != null) {
        final parts = bracketMatch.group(1)!.split('/');
        final tagList = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
        if (tagList.isNotEmpty) {
          metadata.series = normalizeSeries(tagList.first); // e.g. "ACT"
        }
        metadata.tags = tagList;
      }

      // Remove all bracket parts from title
      metadata.title = metadata.title!
          .replaceAll(RegExp(r'【[^】]*】'), '')
          .replaceAll(RegExp(r'\[[^\]]*\]'), '')
          .trim();
    }

    // Extract version from title pattern like "V1.5", "ver2.1", "Build123", "version3.0"
    if (metadata.title != null) {
      final versionMatch =
          RegExp(r'(?:[Vv](?:er(?:sion)?)?|build)\s*(\d[\w.]*)', caseSensitive: false).firstMatch(metadata.title!);
      if (versionMatch != null) {
        metadata.version = 'V${versionMatch.group(1)}';
        metadata.title = removeVersionFromTitle(metadata.title!);
      }
    }

    // Parse post content using text-based section splitting
    final postContent = document.querySelector('div.post-content');
    if (postContent != null) {
      final fullText = postContent.text;
      final sections = _splitSections(fullText);

      metadata.intro = sections['游戏介绍'];
      metadata.features = sections['游戏特点'];
      metadata.changelog = sections['更新内容'];

      // Extract download links from the "链接" section
      final linksSection = sections['链接'];
      if (linksSection != null) {
        final downloadUrls = <String>[];
        // Match URL followed by optional extract code on same or next line
        final linkPattern = RegExp(r'(https?://[^\s<>"\u3000]+)[\s]*(?:提取码|密码)[：:]\s*(\w+)?', multiLine: true);
        for (final match in linkPattern.allMatches(linksSection)) {
          final link = match.group(1)!;
          if (_isDownloadLink(link)) {
            final code = match.group(2);
            if (code != null && code.isNotEmpty) {
              downloadUrls.add('$link 提取码: $code');
            } else {
              downloadUrls.add(link);
            }
          }
        }
        // Also find standalone URLs that weren't matched above
        final standaloneMatches = RegExp(r'https?://[^\s<>"\u3000]+').allMatches(linksSection);
        for (final match in standaloneMatches) {
          final link = match.group(0)!;
          if (_isDownloadLink(link) && !downloadUrls.any((u) => u.contains(link))) {
            downloadUrls.add(link);
          }
        }
        // Find remaining extract codes not yet paired
        final codeMatches = RegExp(r'(?:提取码|密码)[：:]\s*(\w+)').allMatches(linksSection);
        final unpairedCodes = <String>[];
        for (final m in codeMatches) {
          final code = m.group(1)!;
          if (!downloadUrls.any((u) => u.contains(code))) {
            unpairedCodes.add(code);
          }
        }

        if (downloadUrls.isNotEmpty) {
          var result = downloadUrls.join('\n');
          if (unpairedCodes.isNotEmpty) {
            result += '\n提取码: ${unpairedCodes.join(", ")}';
          }
          metadata.downloadUrl = result;
        }
      }

      // Check for unzip code anywhere in post content
      final unzipMatch = RegExp(r'解压(?:码|密码)[：:]\s*(.{1,50})', multiLine: true).firstMatch(fullText);
      if (unzipMatch != null) {
        final unzipCode = unzipMatch.group(1)?.trim() ?? '';
        if (unzipCode.isNotEmpty) {
          if (metadata.downloadUrl != null && metadata.downloadUrl!.isNotEmpty) {
            metadata.downloadUrl = '${metadata.downloadUrl}\n解压码: $unzipCode';
          } else {
            metadata.downloadUrl = '解压码: $unzipCode';
          }
        }
      }

      // Extract images from post content
      final images = postContent.querySelectorAll('img');
      metadata.imageUrls = images
          .map((img) => img.attributes['src'] ?? '')
          .where((src) =>
              src.isNotEmpty &&
              src.contains('wp-content/uploads') &&
              !src.endsWith('.svg') &&
              !src.endsWith('.ico'))
          .toList();
    }

    return metadata;
  }

  /// Check if a URL is a known download/pan link
  bool _isDownloadLink(String url) {
    return url.contains('pan.baidu.com') ||
        url.contains('pan.xunlei.com') ||
        url.contains('share.weiyun.com') ||
        url.contains('drive.uc.cn');
  }

  /// Split full text into sections based on section markers.
  /// Returns a map from section name to its content text.
  /// If no "游戏介绍" marker is found, content before the first recognized
  /// marker (or the entire text when nothing matches) is used as intro.
  Map<String, String> _splitSections(String fullText) {
    final markers = ['游戏介绍：', '游戏特点：', '更新内容：', '链接：'];
    final result = <String, String>{};

    // Find all marker positions
    final positions = <_MarkerPos>[];
    for (final marker in markers) {
      var searchFrom = 0;
      while (true) {
        final index = fullText.indexOf(marker, searchFrom);
        if (index == -1) break;
        positions.add(_MarkerPos(marker, index));
        searchFrom = index + marker.length;
      }
    }
    positions.sort((a, b) => a.pos.compareTo(b.pos));

    // Extract content between markers
    for (var i = 0; i < positions.length; i++) {
      final contentStart = positions[i].pos + positions[i].marker.length;
      final contentEnd = i + 1 < positions.length
          ? positions[i + 1].pos
          : fullText.length;
      final content = fullText.substring(contentStart, contentEnd).trim();
      if (content.isNotEmpty) {
        // Store with marker name (without colon)
        final name = positions[i].marker.replaceAll('：', '');
        result[name] = content;
      }
    }

    // Intelligent fallback: if no "游戏介绍" section was found
    if (!result.containsKey('游戏介绍')) {
      if (positions.isEmpty) {
        // No markers at all — treat entire text as intro
        final trimmed = fullText.trim();
        if (trimmed.isNotEmpty) {
          result['游戏介绍'] = trimmed;
        }
      } else {
        // Use content before the first recognized marker as intro
        final introText = fullText.substring(0, positions.first.pos).trim();
        if (introText.isNotEmpty) {
          result['游戏介绍'] = introText;
        }
      }
    } else if (positions.isNotEmpty) {
      // "游戏介绍" found — merge any text before the first marker into it
      final preText = fullText.substring(0, positions.first.pos).trim();
      if (preText.isNotEmpty) {
        result['游戏介绍'] = '$preText\n\n${result['游戏介绍']}';
      }
    }

    return result;
  }
}

/// Parser for 飞雪ACG (feixueacg.org)
/// Discuz! X3.4 forum with structured thread content.
class FeiXueAcgParser extends SiteParser {
  @override
  String get domain => 'feixueacg';

  @override
  GameInfo? parseGameInfo(Document document, String url) {
    final titleEl = document.querySelector('span#thread_subject');
    var rawTitle = titleEl?.text.trim();
    if (rawTitle == null) return null;

    final tags = extractBracketsFromTitle(rawTitle) ?? [];
    final category = normalizeSeries(tags.isNotEmpty ? tags.first : null);

    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();

    final version = extractVersion(cleanTitle);
    final titleWithoutVersion = version != null ? removeVersionFromTitle(cleanTitle) : cleanTitle;

    final typeOption = document.querySelector('div.typeoption table');
    final platforms = <String>[];
    if (typeOption != null) {
      for (final row in typeOption.querySelectorAll('tr')) {
        final th = row.querySelector('th');
        final td = row.querySelector('td');
        if (th != null && td != null) {
          final label = th.text.trim();
          final value = td.text.trim().replaceAll('\u00A0', '').trim();
          if (value.isEmpty) continue;
          switch (label) {
            case '游玩平台':
              platforms.add(value);
            case '游戏类型':
              final normalized = normalizeSeries(value);
              if (normalized != null && category == null) {
                tags.insert(0, normalized);
              }
            case '游戏语言':
            case '偏好类型':
            case 'XP口味':
              if (!tags.contains(value)) tags.add(value);
          }
        }
      }
    }

    final postContent = document.querySelector('td.t_f');
    String? description;
    String? changelog;
    final screenshots = <String>[];
    final downloads = <DownloadLink>[];
    String? unzipCode;

    // 先从签名区域提取解压码
    final signDiv = document.querySelector('div.sign');
    if (signDiv != null) {
      unzipCode = extractUnzipCode(signDiv.text);
    }

    if (postContent != null) {
      for (final tipDiv in postContent.querySelectorAll('div.tip, div.tip_4, div.aimg_tip')) {
        tipDiv.remove();
      }
      for (final script in postContent.querySelectorAll('script')) {
        script.remove();
      }

      final showhideDiv = postContent.querySelector('div.showhide');
      if (showhideDiv != null) {
        var showhideText = showhideDiv.text;
        showhideText = showhideText.replaceAll('本帖隱藏的內容', '').trim();

        // 过滤掉优惠码、VIP相关文本
        final lines = showhideText.split('\n').where((l) => l.trim().isNotEmpty).toList();
        final filteredLines = <String>[];
        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.contains('优惠码')) continue;
          if (trimmedLine.contains('VIP') || trimmedLine.contains('免飞猫')) continue;
          filteredLines.add(trimmedLine);
        }
        showhideText = filteredLines.join('\n');

        downloads.addAll(extractDownloadLinks(showhideText));
      }

      for (final lockedDiv in postContent.querySelectorAll('div.locked')) {
        lockedDiv.remove();
      }
      for (final showhide in postContent.querySelectorAll('div.showhide')) {
        showhide.remove();
      }

      var fullText = postContent.text;
      fullText = fullText.replaceAll(RegExp(r'[\w.]+\.\w+\s*\([^)]*KB[^)]*\)[^\n]*下載附件[^\n]*(?:\d+\s*天前|\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})\s*上傳'), '');
      fullText = fullText.replaceAll(RegExp(r'[\w.]+\.\w+\s*\([^)]*KB[^)]*\)[^\n]*下載附件'), '');

      final uploadMarker = RegExp(r'(?:\d+\s*天前|\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})\s*上傳');
      final allMarkers = uploadMarker.allMatches(fullText).toList();
      if (allMarkers.isNotEmpty) {
        fullText = fullText.substring(allMarkers.last.end).trim();
      }

      fullText = fullText.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

      // 应用基本噪音过滤
      fullText = filterCommonNoise(fullText);

      final images = postContent.querySelectorAll('img.zoom, ignore_js_op img');
      final imageList = images.isEmpty ? postContent.querySelectorAll('img') : images;
      for (final img in imageList) {
        final src = img.attributes['zoomfile'] ??
            img.attributes['file'] ??
            img.attributes['src'] ??
            '';
        if (src.isNotEmpty &&
            !src.contains('static/image/common') &&
            !src.endsWith('.svg') &&
            !src.endsWith('.ico')) {
          screenshots.add(src);
        }
      }

      if (downloads.isEmpty) {
        downloads.addAll(extractDownloadLinks(fullText));
      }

      // 先提取解压码，然后在过滤描述时排除它
      // 尝试多个可能的section名称
      description = _extractSection(fullText, '概要') ??
                    _extractSection(fullText, '游戏介绍') ??
                    _extractSection(fullText, '简介');
      if (description != null) {
        description = filterDescription(description, unzipCodeFromSign: unzipCode);
        if (description.isEmpty) description = null;
      }

      // 兜底：如果没有匹配到任何section，使用过滤后的全文作为游戏介绍
      if (description == null && fullText.trim().isNotEmpty) {
        final filtered = filterDescription(fullText.trim(), unzipCodeFromSign: unzipCode);
        if (filtered.trim().length > 20) {
          description = filtered;
        }
      }

      // 提取更新日志
      changelog = _extractSection(fullText, '更新日志') ??
                  _extractSection(fullText, '更新内容');
      if (changelog != null) {
        changelog = filterCommonNoise(changelog);
        if (changelog.isEmpty) changelog = null;
      }
    }

    final ptgLinks = document.querySelectorAll('div.ptg a');
    for (final a in ptgLinks) {
      final tag = a.text.trim();
      if (tag.isNotEmpty && !tags.contains(tag)) {
        tags.add(tag);
      }
    }

    if (unzipCode != null && downloads.isNotEmpty) {
      final last = downloads.last;
      downloads[downloads.length - 1] = DownloadLink(
        url: last.url,
        label: last.label,
        provider: last.provider,
        password: last.password,
        unzipCode: unzipCode,
      );
    }

    return GameInfo(
      title: titleWithoutVersion,
      version: version,
      tags: tags,
      category: category,
      description: description,
      changelog: changelog,
      screenshots: screenshots,
      downloads: downloads,
      platforms: platforms,
      sourceUrl: url,
    );
  }

  @override
  GameMetadata parse(Document document, String url) {
    final metadata = GameMetadata();

    // Title from span#thread_subject
    final titleEl = document.querySelector('span#thread_subject');
    if (titleEl != null) {
      metadata.title = titleEl.text.trim();
    }

    // Extract tags and series from title brackets like 【SLG/汉化/NTR】
    if (metadata.title != null) {
      final bracketMatch =
          RegExp(r'【([^】]+)】').firstMatch(metadata.title!);
      if (bracketMatch != null) {
        final parts = bracketMatch.group(1)!.split('/');
        final tagList = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
        if (tagList.isNotEmpty) {
          metadata.series = normalizeSeries(tagList.first); // e.g. "SLG"
        }
        metadata.tags = tagList;
      }

      // Remove all bracket parts from title
      metadata.title = metadata.title!
          .replaceAll(RegExp(r'【[^】]*】'), '')
          .replaceAll(RegExp(r'\[[^\]]*\]'), '')
          .trim();
    }

    // Extract version from title
    if (metadata.title != null) {
      final versionMatch =
          RegExp(r'(?:[Vv](?:er(?:sion)?)?|build)\s*(\d[\w.]*)', caseSensitive: false).firstMatch(metadata.title!);
      if (versionMatch != null) {
        metadata.version = 'V${versionMatch.group(1)}';
        metadata.title = removeVersionFromTitle(metadata.title!);
      }
    }

    // Extract classification info from typeoption table
    final typeOption = document.querySelector('div.typeoption table');
    if (typeOption != null) {
      final rows = typeOption.querySelectorAll('tr');
      for (final row in rows) {
        final th = row.querySelector('th');
        final td = row.querySelector('td');
        if (th != null && td != null) {
          final label = th.text.trim();
          final value = td.text.trim().replaceAll('\u00A0', '').trim();
          if (value.isEmpty) continue;

          switch (label) {
            case '游戏类型':
              final normalized = normalizeSeries(value);
              if (normalized != null) metadata.series ??= normalized;
              if (!metadata.tags.contains(value)) {
                metadata.tags = [...metadata.tags, value];
              }
            case '游玩平台':
            case '游戏语言':
            case '偏好类型':
            case 'XP口味':
              if (!metadata.tags.contains(value)) {
                metadata.tags = [...metadata.tags, value];
              }
          }
        }
      }
    }

    // Extract main post content from first td.t_f (OP's post only)
    final postContent = document.querySelector('td.t_f');
    if (postContent != null) {
      // Remove hidden tooltip divs that contain attachment metadata
      for (final tipDiv in postContent.querySelectorAll('div.tip, div.tip_4, div.aimg_tip')) {
        tipDiv.remove();
      }
      // Remove script elements
      for (final script in postContent.querySelectorAll('script')) {
        script.remove();
      }

      // Extract download links from showhide div BEFORE removing it
      final downloadUrls = <String>[];
      final showhideDiv = postContent.querySelector('div.showhide');
      if (showhideDiv != null) {
        // Use text content to get clean text without HTML tags
        var showhideText = showhideDiv.text;
        // Filter out hidden content marker
        showhideText = showhideText.replaceAll('本帖隱藏的內容', '').trim();

        // Parse each line
        final lines = showhideText.split('\n').where((l) => l.trim().isNotEmpty).toList();
        for (final line in lines) {
          final trimmedLine = line.trim();
          // Skip promotional codes
          if (trimmedLine.contains('优惠码')) continue;
          // Skip VIP-related text
          if (trimmedLine.contains('VIP') || trimmedLine.contains('免飞猫')) continue;

          // Parse labeled download links like "飞猫直链①：https://..."
          final labeledMatch = RegExp(r'^([^：:]+)[：:]\s*(https?://.+)$').firstMatch(trimmedLine);
          if (labeledMatch != null) {
            final label = labeledMatch.group(1)!.trim();
            final url = labeledMatch.group(2)!.trim();
            if (_isDownloadLink(url)) {
              downloadUrls.add('$label $url');
            }
            continue;
          }

          // Parse standalone URLs
          final urlMatch = RegExp(r'https?://\S+').firstMatch(trimmedLine);
          if (urlMatch != null) {
            final url = urlMatch.group(0)!;
            if (_isDownloadLink(url) && !downloadUrls.any((u) => u.contains(url))) {
              downloadUrls.add(url);
            }
          }
        }
      }

      // Now remove locked and showhide divs from post content
      for (final lockedDiv in postContent.querySelectorAll('div.locked')) {
        lockedDiv.remove();
      }
      for (final showhide in postContent.querySelectorAll('div.showhide')) {
        showhide.remove();
      }

      var fullText = postContent.text;

      // Filter out image attachment patterns
      fullText = fullText.replaceAll(RegExp(r'[\w.]+\.\w+\s*\([^)]*KB[^)]*\)[^\n]*下載附件[^\n]*(?:\d+\s*天前|\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})\s*上傳'), '');
      fullText = fullText.replaceAll(RegExp(r'[\w.]+\.\w+\s*\([^)]*KB[^)]*\)[^\n]*下載附件'), '');

      // Find the last upload marker and take content after it
      final uploadMarker = RegExp(r'(?:\d+\s*天前|\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})\s*上傳');
      final allMarkers = uploadMarker.allMatches(fullText).toList();
      if (allMarkers.isNotEmpty) {
        final lastMarker = allMarkers.last;
        fullText = fullText.substring(lastMarker.end).trim();
      }

      // Clean up multiple newlines
      fullText = fullText.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

      // Extract intro section after "概要："
      metadata.intro = _extractSection(fullText, '概要');

      // Filter out promotional codes and decompress passwords from intro
      if (metadata.intro != null) {
        var intro = metadata.intro!;
        // Remove lines containing promotional codes (优惠码、折扣码、优惠卷)
        intro = intro.replaceAll(RegExp(r'[^\n]*(优惠码|折扣码|优惠卷)[^\n]*'), '');
        // Remove lines containing decompress passwords (解压码、解压密码、解压口令)
        intro = intro.replaceAll(RegExp(r'[^\n]*(解压码|解压密码|解压口令)[^\n]*'), '');
        // Remove lines containing extract codes (提取码)
        intro = intro.replaceAll(RegExp(r'[^\n]*提取码[^\n]*'), '');
        // Remove lines containing VIP-related text
        intro = intro.replaceAll(RegExp(r'[^\n]*(VIP|vip|Vip)[^\n]*'), '');
        // Remove lines containing 飞猫云 related text
        intro = intro.replaceAll(RegExp(r'[^\n]*飞猫云[^\n]*'), '');
        // Clean up multiple newlines after filtering
        intro = intro.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
        metadata.intro = intro.isNotEmpty ? intro : null;
      }

      // Extract images from post content using zoomfile/file attributes
      final images = postContent.querySelectorAll('img.zoom, ignore_js_op img');
      if (images.isEmpty) {
        // Fallback: all images in post
        final allImages = postContent.querySelectorAll('img');
        metadata.imageUrls = allImages
            .map((img) {
              // Prefer zoomfile > file > src
              return img.attributes['zoomfile'] ??
                  img.attributes['file'] ??
                  img.attributes['src'] ??
                  '';
            })
            .where((src) =>
                src.isNotEmpty &&
                !src.contains('static/image/common') &&
                !src.endsWith('.svg') &&
                !src.endsWith('.ico'))
            .toList();
      } else {
        metadata.imageUrls = images
            .map((img) {
              return img.attributes['zoomfile'] ??
                  img.attributes['file'] ??
                  img.attributes['src'] ??
                  '';
            })
            .where((src) =>
                src.isNotEmpty &&
                !src.contains('static/image/common') &&
                !src.endsWith('.svg') &&
                !src.endsWith('.ico'))
            .toList();
      }

      // If still no links found in showhide, check full text
      if (downloadUrls.isEmpty) {
        final linkMatches =
            RegExp(r'https?://[^\s<>"\u3000\]]+').allMatches(fullText);
        for (final match in linkMatches) {
          final link = match.group(0)!;
          if (_isDownloadLink(link) && !downloadUrls.any((u) => u.startsWith(link))) {
            // Look for extract code right after this URL
            final afterUrl = fullText.substring(match.end).trim();
            final codeMatch = RegExp(r'^(?:提取码|密码)[：:]\s*(\w+)').firstMatch(afterUrl);
            if (codeMatch != null) {
              downloadUrls.add('$link 提取码: ${codeMatch.group(1)}');
            } else {
              downloadUrls.add(link);
            }
          }
        }
      }

      if (downloadUrls.isNotEmpty) {
        metadata.downloadUrl = downloadUrls.join('\n');
      }
    }

    // Extract unzip code from signature (div.sign)
    final signDiv = document.querySelector('div.sign');
    if (signDiv != null) {
      final unzipMatch = RegExp(r'解压(?:码|密码)[：:]\s*(.{1,50})', multiLine: true).firstMatch(signDiv.text);
      if (unzipMatch != null) {
        final unzipCode = unzipMatch.group(1)?.trim() ?? '';
        if (unzipCode.isNotEmpty) {
          if (metadata.downloadUrl != null && metadata.downloadUrl!.isNotEmpty) {
            metadata.downloadUrl = '${metadata.downloadUrl}\n解压码: $unzipCode';
          } else {
            metadata.downloadUrl = '解压码: $unzipCode';
          }
        }
      }
    }

    // Extract post tags from div.ptg a
    final ptgLinks = document.querySelectorAll('div.ptg a');
    for (final a in ptgLinks) {
      final tag = a.text.trim();
      if (tag.isNotEmpty && !metadata.tags.contains(tag)) {
        metadata.tags = [...metadata.tags, tag];
      }
    }

    return metadata;
  }

  /// Check if a URL is a known download/pan link
  bool _isDownloadLink(String url) {
    return url.contains('pan.baidu.com') ||
        url.contains('pan.xunlei.com') ||
        url.contains('share.weiyun.com') ||
        url.contains('drive.uc.cn') ||
        url.contains('feixue.cloud') ||
        url.contains('gofile.io') ||
        url.contains('cm1.hk') ||
        url.contains('cm2.hk') ||
        url.contains('feimaocloud');
  }

  /// Extract text after a section label until the next recognizable section.
  String? _extractSection(String fullText, String sectionName) {
    // Try with Chinese colon first, then English colon
    final patterns = ['$sectionName：', '$sectionName:'];
    int? contentStart;
    for (final pattern in patterns) {
      final index = fullText.indexOf(pattern);
      if (index != -1) {
        contentStart = index + pattern.length;
        break;
      }
    }
    if (contentStart == null) return null;

    // Find next section or end
    // 使用行首匹配，避免匹配到"本次更新内容："中的"更新内容："
    final nextSectionMatch = RegExp(
      r'(?:^|\n)\s*(游戏介绍[：:]|游戏特点[：:]|更新日志[：:]|更新内容[：:]|链接[：:]|下载链接[：:]|解压码[：:]|解压密码[：:])',
      multiLine: true,
    ).firstMatch(fullText.substring(contentStart));

    final contentEnd = nextSectionMatch != null
        ? contentStart + nextSectionMatch.start
        : fullText.length;

    return fullText.substring(contentStart, contentEnd).trim();
  }
}

/// Parser for 微咔ACG / VikACG (vikacg.com / weika)
/// Nuxt.js/Vue.js SPA with SSR-rendered content.
class VikAcgParser extends SiteParser {
  @override
  String get domain => 'vikacg';

  Element _findContentContainer(Document document) {
    const selectors = [
      'article',
      '.prose',
      '.p-4',
      '.content',
      '.article-content',
      'main',
    ];
    for (final selector in selectors) {
      final el = document.querySelector(selector);
      if (el != null && el.querySelectorAll('p').isNotEmpty) return el;
    }
    return document.body ?? document.documentElement!;
  }

  @override
  GameInfo? parseGameInfo(Document document, String url) {
    final ogTitle = document.querySelector('meta[property="og:title"]');
    var rawTitle = ogTitle?.attributes['content']?.trim() ?? '';
    if (rawTitle.isEmpty) {
      rawTitle = document.querySelector('title')?.text.trim() ?? '';
    }
    if (rawTitle.isEmpty) return null;

    final dashIndex = rawTitle.lastIndexOf(' - ');
    if (dashIndex > 0) {
      rawTitle = rawTitle.substring(0, dashIndex).trim();
    }

    final tags = extractBracketsFromTitle(rawTitle) ?? [];
    final category = normalizeSeries(tags.isNotEmpty ? tags.first : null);

    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();

    final version = extractVersion(cleanTitle);
    final titleWithoutVersion = version != null ? removeVersionFromTitle(cleanTitle) : cleanTitle;

    final ogDesc = document.querySelector('meta[property="og:description"]') ??
        document.querySelector('meta[name="description"]');
    String? description = ogDesc?.attributes['content']?.trim();

    final tagMetas = document.querySelectorAll('meta[property="article:tag"]');
    for (final meta in tagMetas) {
      final tag = meta.attributes['content']?.trim() ?? '';
      if (tag.isNotEmpty && !tags.contains(tag)) {
        tags.add(tag);
      }
    }

    final tagLinks = document.querySelectorAll('a[href^="/post/tag/"]');
    for (final a in tagLinks) {
      var tag = a.text.trim();
      if (tag.startsWith('#')) tag = tag.substring(1).trim();
      if (tag.isNotEmpty && !tags.contains(tag)) {
        tags.add(tag);
      }
    }

    final screenshots = <String>[];
    final ogImage = document.querySelector('meta[property="og:image"]');
    if (ogImage != null) {
      final imgUrl = ogImage.attributes['content'];
      if (imgUrl != null && imgUrl.isNotEmpty) {
        screenshots.add(imgUrl);
      }
    }

    final contentImages = document.querySelectorAll(
      'img.render-arco-image, div.arco-image img',
    );
    for (final img in contentImages) {
      final src = img.attributes['src'] ?? '';
      if (src.isNotEmpty && !screenshots.contains(src)) {
        screenshots.add(src);
      }
    }

    final contentContainer = _findContentContainer(document);
    final paragraphs = contentContainer.querySelectorAll('p');
    final introBuffer = StringBuffer();
    bool collecting = false;
    bool foundStartMarker = false;
    for (final p in paragraphs) {
      final text = _elementText(p).trim();
      if (_isCopyrightText(text)) continue;
      if (RegExp(r'^游戏(?:介绍|内容|概述)[：:]\s*').hasMatch(text)) {
        collecting = true;
        foundStartMarker = true;
        final afterMarker = text.replaceFirst(
          RegExp(r'^游戏(?:介绍|内容|概述)[：:]\s*'),
          '',
        );
        if (afterMarker.isNotEmpty) introBuffer.writeln(afterMarker);
        continue;
      }
      if (collecting) {
        if (text.contains('游戏特点') ||
            text.contains('更新内容') ||
            RegExp(r'^下载(?:链接|地址)?[：:]?\s*$').hasMatch(text) ||
            RegExp(r'^链接[：:]?\s*$').hasMatch(text)) {
          collecting = false;
          continue;
        }
        if (text.isNotEmpty && !_containsUnzipCode(text)) introBuffer.writeln(text);
      }
    }
    // Fallback: if no start marker found, collect all text before first stop marker
    if (!foundStartMarker) {
      for (final p in paragraphs) {
        final text = _elementText(p).trim();
        if (_isCopyrightText(text)) continue;
        if (text.contains('游戏特点') ||
            text.contains('更新内容') ||
            RegExp(r'^下载(?:链接|地址)?[：:]?\s*$').hasMatch(text) ||
            RegExp(r'^链接[：:]?\s*$').hasMatch(text)) {
          break;
        }
        if (text.isNotEmpty && !_containsUnzipCode(text)) introBuffer.writeln(text);
      }
    }
    if (introBuffer.isNotEmpty) {
      final collected = introBuffer.toString().trim();
      if (description == null || description.isEmpty || collected.length > description.length) {
        description = collected;
      }
    }

    final downloads = <DownloadLink>[];
    final contentText = _elementText(contentContainer);
    final unzipCode = extractUnzipCode(contentText);
    if (unzipCode != null) {
      downloads.add(DownloadLink(
        url: '',
        unzipCode: unzipCode,
      ));
    }

    return GameInfo(
      title: titleWithoutVersion,
      version: version,
      tags: tags,
      category: category,
      description: description,
      screenshots: screenshots,
      downloads: downloads,
      sourceUrl: url,
    );
  }

  @override
  GameMetadata parse(Document document, String url) {
    final metadata = GameMetadata();

    // Title from og:title meta or <title>
    final ogTitle = document.querySelector('meta[property="og:title"]');
    if (ogTitle != null) {
      var title = ogTitle.attributes['content']?.trim() ?? '';
      // Remove site suffix like " - 维咔VikACG[V站]"
      final dashIndex = title.lastIndexOf(' - ');
      if (dashIndex > 0) {
        title = title.substring(0, dashIndex).trim();
      }
      metadata.title = title.isEmpty ? null : title;
    }
    metadata.title ??= document.querySelector('title')?.text.trim();

    // Extract tags and series from title brackets like [SLG/中文]
    if (metadata.title != null) {
      final bracketMatch =
          RegExp(r'\[([^\]]+)\]').firstMatch(metadata.title!);
      if (bracketMatch != null) {
        final parts = bracketMatch.group(1)!.split('/');
        final tagList = parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
        if (tagList.isNotEmpty) {
          metadata.series = normalizeSeries(tagList.first); // e.g. "SLG"
        }
        metadata.tags = tagList;
      }

      // Remove all bracket parts from title
      metadata.title = metadata.title!
          .replaceAll(RegExp(r'【[^】]*】'), '')
          .replaceAll(RegExp(r'\[[^\]]*\]'), '')
          .trim();
    }

    // Extract version from title
    if (metadata.title != null) {
      final versionMatch =
          RegExp(r'(?:[Vv](?:er(?:sion)?)?|build)\s*(\d[\w.]*)', caseSensitive: false).firstMatch(metadata.title!);
      if (versionMatch != null) {
        metadata.version = 'V${versionMatch.group(1)}';
        metadata.title = removeVersionFromTitle(metadata.title!);
      }
    }

    // Description from og:description or meta description
    final ogDesc =
        document.querySelector('meta[property="og:description"]') ??
            document.querySelector('meta[name="description"]');
    if (ogDesc != null) {
      metadata.intro = ogDesc.attributes['content']?.trim();
    }

    // Extract tags from article:tag meta tags
    final tagMetas = document.querySelectorAll('meta[property="article:tag"]');
    for (final meta in tagMetas) {
      final tag = meta.attributes['content']?.trim() ?? '';
      if (tag.isNotEmpty && !metadata.tags.contains(tag)) {
        metadata.tags = [...metadata.tags, tag];
      }
    }

    // Also extract tags from rendered tag links a[href^="/post/tag/"]
    final tagLinks = document.querySelectorAll('a[href^="/post/tag/"]');
    for (final a in tagLinks) {
      var tag = a.text.trim();
      if (tag.startsWith('#')) {
        tag = tag.substring(1).trim();
      }
      if (tag.isNotEmpty && !metadata.tags.contains(tag)) {
        metadata.tags = [...metadata.tags, tag];
      }
    }

    // Extract images
    final imageUrls = <String>[];

    // Cover image from og:image
    final ogImage = document.querySelector('meta[property="og:image"]');
    if (ogImage != null) {
      final imgUrl = ogImage.attributes['content'];
      if (imgUrl != null && imgUrl.isNotEmpty) {
        imageUrls.add(imgUrl);
      }
    }

    // Content images from img.render-arco-image and div.arco-image img
    final contentImages = document.querySelectorAll(
      'img.render-arco-image, div.arco-image img',
    );
    for (final img in contentImages) {
      final src = img.attributes['src'] ?? '';
      if (src.isNotEmpty && !imageUrls.contains(src)) {
        imageUrls.add(src);
      }
    }
    metadata.imageUrls = imageUrls;

    // Extract game intro from rendered content paragraphs
    final contentContainer = _findContentContainer(document);
    final paragraphs = contentContainer.querySelectorAll('p');
    final introBuffer = StringBuffer();
    bool collecting = false;
    bool foundStartMarker = false;
    for (final p in paragraphs) {
      final text = _elementText(p).trim();
      if (_isCopyrightText(text)) continue;
      if (RegExp(r'^游戏(?:介绍|内容|概述)[：:]\s*').hasMatch(text)) {
        collecting = true;
        foundStartMarker = true;
        final afterMarker = text.replaceFirst(
          RegExp(r'^游戏(?:介绍|内容|概述)[：:]\s*'),
          '',
        );
        if (afterMarker.isNotEmpty) {
          introBuffer.writeln(afterMarker);
        }
        continue;
      }
      if (collecting) {
        if (text.contains('游戏特点') ||
            text.contains('更新内容') ||
            RegExp(r'^下载(?:链接|地址)?[：:]?\s*$').hasMatch(text) ||
            RegExp(r'^链接[：:]?\s*$').hasMatch(text)) {
          collecting = false;
          continue;
        }
        if (text.isNotEmpty && !_containsUnzipCode(text)) {
          introBuffer.writeln(text);
        }
      }
    }
    // Fallback: if no start marker found, collect all text before first stop marker
    if (!foundStartMarker) {
      for (final p in paragraphs) {
        final text = _elementText(p).trim();
        if (_isCopyrightText(text)) continue;
        if (text.contains('游戏特点') ||
            text.contains('更新内容') ||
            RegExp(r'^下载(?:链接|地址)?[：:]?\s*$').hasMatch(text) ||
            RegExp(r'^链接[：:]?\s*$').hasMatch(text)) {
          break;
        }
        if (text.isNotEmpty && !_containsUnzipCode(text)) introBuffer.writeln(text);
      }
    }
    if (introBuffer.isNotEmpty) {
      final collected = introBuffer.toString().trim();
      // Prefer paragraph-collected intro over meta description if it's longer
      if (metadata.intro == null || metadata.intro!.isEmpty || collected.length > metadata.intro!.length) {
        metadata.intro = collected;
      }
    }

    // Extract unzip code from content container
    final contentText = _elementText(contentContainer);
    final unzipMatch = RegExp(r'(?:默认)?解压(?:码|密码)[：:]?\s*(.{1,50})|(?<!提取)密码[：:]?\s*(\S+)', multiLine: true).firstMatch(contentText);
    if (unzipMatch != null) {
      final unzipCode = (unzipMatch.group(1) ?? unzipMatch.group(2))?.trim() ?? '';
      if (unzipCode.isNotEmpty) {
        if (metadata.downloadUrl != null && metadata.downloadUrl!.isNotEmpty) {
          metadata.downloadUrl = '${metadata.downloadUrl}\n解压码: $unzipCode';
        } else {
          metadata.downloadUrl = '解压码: $unzipCode';
        }
      }
    }

    return metadata;
  }
}

/// Register all site parsers into the ParserRegistry.
/// Called by HtmlScraper._ensureRegistered() to guarantee registration.
void registerAllParsers() {
  if (ParserRegistry.allParsers.isEmpty) {
    ParserRegistry.register(AcgYingParser());
    ParserRegistry.register(VikAcgParser());
    ParserRegistry.register(FeiXueAcgParser());
    ParserRegistry.register(DlsiteParser());
    // Register domain alias parsers that share the same parsing logic
    ParserRegistry.register(_AliasParser('acgying', AcgYingParser()));
    ParserRegistry.register(_AliasParser('weika', VikAcgParser()));
    AppLogger.instance.info('Scraper', 'Registered ${ParserRegistry.allParsers.length} site parsers (including aliases): AcgYing/acgying, VikAcg/weika, FeiXueAcg, Dlsite');
  }
}

Future<void> registerCustomDomainParsers() async {
  final prefs = await AppSettings.load();

  final domainAcgying = prefs.getString('domain_acgying') ?? '';
  if (domainAcgying.isNotEmpty) {
    ParserRegistry.register(_AliasParser(domainAcgying.toLowerCase(), AcgYingParser()));
    AppLogger.instance.info('Scraper', 'Registered custom domain for AcgYing: $domainAcgying');
  }

  final domainFeixue = prefs.getString('domain_feixue') ?? '';
  if (domainFeixue.isNotEmpty) {
    ParserRegistry.register(_AliasParser(domainFeixue.toLowerCase(), FeiXueAcgParser()));
    AppLogger.instance.info('Scraper', 'Registered custom domain for FeiXue: $domainFeixue');
  }

  final domainVikacg = prefs.getString('domain_vikacg') ?? '';
  if (domainVikacg.isNotEmpty) {
    ParserRegistry.register(_AliasParser(domainVikacg.toLowerCase(), VikAcgParser()));
    AppLogger.instance.info('Scraper', 'Registered custom domain for VikAcg: $domainVikacg');
  }
}

/// A lightweight wrapper that delegates to another parser under a different domain alias.
class _AliasParser extends SiteParser {
  final String _domain;
  final SiteParser _delegate;

  _AliasParser(this._domain, this._delegate);

  @override
  String get domain => _domain;

  @override
  GameMetadata parse(Document document, String url) => _delegate.parse(document, url);
}
