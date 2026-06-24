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
  String? descriptionHtml;  // 原始HTML片段，用于保留布局
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
    final parts = downloads.map((d) {
      final linkParts = <String>[d.url];
      if (d.password != null) linkParts.add('提取码: ${d.password}');
      return linkParts.join(' ');
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
  'gofile.io',
  'feixue.cloud',
  'cm1.hk',
  'cm2.hk',
  'feimaocloud',
];

const _kProviderPatterns = {
  'baidu': 'pan.baidu.com',
  'xunlei': 'pan.xunlei.com',
  'weiyun': 'share.weiyun.com',
  'uc': 'drive.uc.cn',
  'gofile': 'gofile.io',
  'feimaocloud': 'feimaocloud',
  'feimao': 'cm1.hk',
  'feimao2': 'cm2.hk',
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
        RegExp(r'\s*(?:[Vv](?:er(?:sion)?)?|build)\s*\d[\w.]*', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

String? extractUnzipCode(String text) {
  final match = RegExp(
    r'(?:默认)?解压(?:码|密码)[：:]?\s*(.{1,50})|(?<!提取)密码[：:]?\s*(\S+)',
    multiLine: true,
  ).firstMatch(text);
  final code = (match?.group(1) ?? match?.group(2))?.trim();
  return (code != null && code.isNotEmpty) ? code : null;
}

List<DownloadLink> extractDownloadLinks(String text) {
  final results = <DownloadLink>[];
  final seen = <String>{};

  final labeledPattern = RegExp(
    r'^([^：:]+)[：:]\s*(https?://.+)$',
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

  final urlPattern = RegExp(r'https?://[^\s<>"\u3000\]]+');
  for (final match in urlPattern.allMatches(text)) {
    final url = match.group(0)!;
    if (isDownloadLink(url) && !seen.contains(url)) {
      seen.add(url);
      String? password;
      final afterUrl = text.substring(match.end).trim();
      final codeMatch = RegExp(
        r'^(?:提取码|密码)[：:]\s*(\w+)',
      ).firstMatch(afterUrl);
      if (codeMatch != null) {
        password = codeMatch.group(1);
      }
      results.add(DownloadLink(
        url: url,
        provider: detectProvider(url),
        password: password,
      ));
    }
  }

  final codePattern = RegExp(r'(?:提取码|密码)[：:]\s*(\w+)');
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
      .replaceAll(RegExp(r'本帖最后由\s*\S+\s*于\s*\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}\s*编辑'), '')
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
      .replaceAll(RegExp(r'本帖最后由\s*\S+\s*于\s*\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}\s*编辑'), '')
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
