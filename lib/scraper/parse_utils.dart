class DownloadLink {
  final String url;
  final String? provider;
  final String? password;
  final String? label;
  final String? unzipCode;

  DownloadLink({
    required this.url,
    this.provider,
    this.password,
    this.label,
    this.unzipCode,
  });

  @override
  String toString() {
    final parts = <String>[url];
    if (provider != null) parts.insert(0, provider!);
    if (password != null) parts.add('提取码: $password');
    if (unzipCode != null) parts.add('解压码: $unzipCode');
    return parts.join(' ');
  }
}

class GameInfo {
  String? title;
  String? version;
  List<String> tags;
  String? category;
  String? description;
  List<String> features;
  String? changelog;
  List<String> screenshots;
  List<DownloadLink> downloads;
  String? fileSize;
  List<String> platforms;
  String? publishDate;
  String? maker;
  String? makerUrl;
  String? descriptionHtml; // 原始HTML片段，用于保留布局
  String sourceUrl;

  GameInfo({
    this.maker,
    this.makerUrl,
    this.descriptionHtml,
    this.title,
    this.version,
    this.tags = const [],
    this.category,
    this.description,
    this.features = const [],
    this.changelog,
    this.screenshots = const [],
    this.downloads = const [],
    this.fileSize,
    this.platforms = const [],
    this.publishDate,
    required this.sourceUrl,
  });

  String get downloadUrl {
    final parts = downloads.where((d) => d.url.trim().isNotEmpty).map((d) {
      final linkParts = <String>[d.url.trim()];
      if (d.password != null) linkParts.add('提取码: ${d.password}');
      final link = linkParts.join(' ');
      final label = d.label?.trim() ?? '';
      return label.isNotEmpty ? '$label $link' : link;
    }).toList();
    // Include unzip code if present
    final code = unzipCode;
    if (code != null) {
      parts.add('解压码: $code');
    }
    return parts.join('\n');
  }

  String? get unzipCode {
    // 从 downloads 中提取解压码
    for (final d in downloads) {
      if (d.unzipCode != null) return d.unzipCode;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (version != null) 'version': version,
        if (tags.isNotEmpty) 'tags': tags,
        if (category != null) 'series': category,
        if (description != null) 'intro': description,
        if (features.isNotEmpty) 'features': features.join('\n'),
        if (changelog != null) 'changelog': changelog,
        if (downloadUrl.isNotEmpty) 'download_url': downloadUrl,
        if (maker != null) 'maker': maker,
        if (makerUrl != null) 'maker_url': makerUrl,
        if (descriptionHtml != null) 'intro_html': descriptionHtml,
        'source_url': sourceUrl,
        if (screenshots.isNotEmpty) 'image_urls': screenshots,
      };
}

const _kDownloadDomains = [
  'pan.baidu.com',
  'pan.xunlei.com',
  'share.weiyun.com',
  'drive.uc.cn',
  'pan.quark.cn',
  'gofile.io',
  'feixue.cloud',
  'cm1.hk',
  'cm2.hk',
  'feimaocloud',
  '1024terabox.com',
  'terabox.com',
  'terabox.app',
  'dropbox.com',
  'drive.google.com',
  '1drv.ms',
  'onedrive.live.com',
  'sharepoint.com',
  'lanzou',
  '115.com',
  'mypikpak.com',
  'cloud.189.cn',
  'jianguoyun.com',
  'alipan.com',
  'aliyundrive.com',
  'mega.nz',
  'mediafire.com',
  'mypikpak.com',
];

const _kProviderPatterns = {
  'baidu': 'pan.baidu.com',
  'xunlei': 'pan.xunlei.com',
  'weiyun': 'share.weiyun.com',
  'uc': 'drive.uc.cn',
  'quark': 'pan.quark.cn',
  'gofile': 'gofile.io',
  'feimaocloud': 'feimaocloud',
  'feimao': 'cm1.hk',
  'feimao2': 'cm2.hk',
  'terabox': 'terabox.com',
  'dropbox': 'dropbox.com',
  'google': 'drive.google.com',
  'onedrive': '1drv.ms',
  'lanzou': 'lanzou',
  '115': '115.com',
  'pikpak': 'mypikpak.com',
  '189': 'cloud.189.cn',
  'jianguoyun': 'jianguoyun.com',
  'aliyun': 'alipan.com',
  'mega': 'mega.nz',
  'mediafire': 'mediafire.com',
};

bool isDownloadLink(String url) {
  return _kDownloadDomains.any((domain) => url.contains(domain));
}

String? detectProvider(String url) {
  for (final entry in _kProviderPatterns.entries) {
    if (url.contains(entry.value)) return entry.key;
  }
  return null;
}

List<String>? extractBracketsFromTitle(String title) {
  final match = RegExp(r'[【\[]([^】\]]+)[】\]]').firstMatch(title);
  if (match == null) return null;
  return match
      .group(1)!
      .split('/')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
}

String? extractVersion(String text) {
  final match = RegExp(
    r'(?:[Vv](?:er(?:sion)?)?|build)\s*(\d[\w.]*)',
    caseSensitive: false,
  ).firstMatch(text);
  return match != null ? 'V${match.group(1)}' : null;
}

/// 从标题中移除版本号文本（如 "v5.0.3"、"V1.2"、"ver1.0"、"Build123"）
String removeVersionFromTitle(String title) {
  return title
      .replaceAll(
        RegExp(r'\s*(?:[Vv](?:er(?:sion)?)?|build)\s*\d[\w.]*',
            caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

String? extractUnzipCode(String text) {
  final match = RegExp(
    r'(?:默认)?解压(?:码|密码)(?:[：:]\s*|\s+)([^\n\r]{1,50})|(?<!提取)密码[：:]\s*(\S+)',
    multiLine: true,
  ).firstMatch(text);
  final code = (match?.group(1) ?? match?.group(2))?.trim();
  return (code != null && code.isNotEmpty) ? code : null;
}

/// 解析下载区的标签行（如「备用」「百度 （提取码436o）」）。
/// 返回清理后的标签与附带的提取码；不适合作为标签时返回 null。
(String, String?)? _parseLabelLine(String line) {
  var label = line.trim();
  if (label.isEmpty) return null;
  if (label.endsWith(':') || label.endsWith('：')) return null;
  if (label.contains(RegExp(r'https?://'))) return null;

  String? password;
  label = label.replaceAllMapped(
    RegExp(r'[（(]\s*(?:提取码|密码)[：:]?\s*([A-Za-z0-9]+)\s*[)）]'),
    (m) {
      password = m.group(1);
      return '';
    },
  );
  // 其余括号说明（如「（教程）」）一并剔除
  label = label.replaceAll(RegExp(r'[（(][^)）]*[)）]'), '');
  label = label.replaceAll(RegExp(r'[：:\s]+$'), '').trim();
  if (label.isEmpty || label.length > 15) return null;
  if (RegExp(r'解压(?:码|密码|口令)|提取码|密码|优惠码|折扣码').hasMatch(label)) {
    return null;
  }
  return (label, password);
}

List<DownloadLink> extractDownloadLinks(String text) {
  final results = <DownloadLink>[];
  final seen = <String>{};

  final labeledPattern = RegExp(
    r'^([^：:]+)[：:]\s*(https?://[^\s<>"\u3000\[\]（）()]+)',
    multiLine: true,
  );
  for (final match in labeledPattern.allMatches(text)) {
    final label = match.group(1)!.trim();
    final url = match.group(2)!.trim();
    if (isDownloadLink(url) && !seen.contains(url)) {
      seen.add(url);
      results.add(DownloadLink(
        url: url,
        label: label,
        provider: detectProvider(url),
      ));
    }
  }

  final urlPattern = RegExp(r'https?://[^\s<>"\u3000\[\]（）()]+');
  final lines = text.split('\n');
  String? pendingLabel;
  String? pendingPassword;
  for (var li = 0; li < lines.length; li++) {
    final line = lines[li].trim();
    if (line.isEmpty) continue;
    final matches = urlPattern.allMatches(line).toList();
    if (matches.isEmpty) {
      // 无 URL 行：作为下一链接行的候选标签（维咔等站点标签独占一行）
      final labelInfo = _parseLabelLine(line);
      if (labelInfo != null) {
        pendingLabel = labelInfo.$1;
        pendingPassword = labelInfo.$2;
      } else {
        pendingLabel = null;
        pendingPassword = null;
      }
      continue;
    }
    for (var mi = 0; mi < matches.length; mi++) {
      final match = matches[mi];
      final url = match.group(0)!;
      if (!isDownloadLink(url) || seen.contains(url)) continue;
      seen.add(url);

      // 提取码：优先行内 URL 之后，其次下一行开头（跨行配对保持原有行为）
      var afterUrl = line.substring(match.end).trim();
      if (afterUrl.isEmpty && li + 1 < lines.length) {
        afterUrl = lines[li + 1].trim();
      }
      final codeMatch = RegExp(
        r'^(?:提取码|密码)[：:]\s*(\w+)',
      ).firstMatch(afterUrl);
      var password = codeMatch?.group(1);

      String? label;
      if (mi == 0) {
        // 行内前缀（空格分隔）优先，否则用上一行的候选标签
        final prefix = line.substring(0, match.start).trim();
        final prefixInfo = prefix.isNotEmpty ? _parseLabelLine(prefix) : null;
        if (prefixInfo != null) {
          label = prefixInfo.$1;
          password ??= prefixInfo.$2;
        } else if (pendingLabel != null) {
          label = pendingLabel;
          password ??= pendingPassword;
        }
      }

      results.add(DownloadLink(
        url: url,
        label: label,
        provider: detectProvider(url),
        password: password,
      ));
    }
    pendingLabel = null;
    pendingPassword = null;
  }

  // 「解压密码/解压码」不是提取码，不参与兜底配对
  final codePattern = RegExp(r'(?<!解压)(?:提取码|密码)[：:]\s*(\w+)');
  final unpairedCodes = <String>[];
  for (final match in codePattern.allMatches(text)) {
    final code = match.group(1)!;
    if (!results.any((d) => d.password == code)) {
      unpairedCodes.add(code);
    }
  }
  if (unpairedCodes.isNotEmpty && results.isNotEmpty) {
    final last = results.last;
    if (last.password == null) {
      results[results.length - 1] = DownloadLink(
        url: last.url,
        label: last.label,
        provider: last.provider,
        password: unpairedCodes.first,
      );
    }
  }

  return results;
}

String filterCommonNoise(String text) {
  return text
      .replaceAll(
          RegExp(
              r'本帖最后由\s*\S+\s*于\s*\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}\s*编辑'),
          '')
      .replaceAll(RegExp(r'本帖隱藏的內容'), '')
      .replaceAll(RegExp(r'[^\n]*(优惠码|折扣码|优惠卷)[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*飞猫云[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*(VIP|vip|Vip)[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*免飞猫[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*已补档[^\n]*'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String filterDescription(String text, {String? unzipCodeFromSign}) {
  var result = text
      .replaceAll(
          RegExp(
              r'本帖最后由\s*\S+\s*于\s*\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}\s*编辑'),
          '')
      .replaceAll(RegExp(r'本帖隱藏的內容'), '')
      .replaceAll(RegExp(r'[^\n]*(优惠码|折扣码|优惠卷)[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*(解压码|解压密码|解压口令)[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*提取码[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*(VIP|vip|Vip)[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*飞猫云[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*免飞猫[^\n]*'), '')
      .replaceAll(RegExp(r'[^\n]*已补档[^\n]*'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  if (unzipCodeFromSign != null && unzipCodeFromSign.isNotEmpty) {
    result = result.replaceAll(
      RegExp('[^\\n]*${RegExp.escape(unzipCodeFromSign)}[^\\n]*'),
      '',
    );
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  return result;
}

String? extractAndFilterSignContent(String signText) {
  final unzipCode = extractUnzipCode(signText);
  return unzipCode;
}
