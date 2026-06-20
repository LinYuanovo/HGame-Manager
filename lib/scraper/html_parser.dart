import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../core/services/app_logger.dart';
import '../core/utils/app_settings.dart';
import 'site_parsers.dart';
import 'parse_utils.dart';
import 'xpath_evaluator.dart';

/// Base class for site-specific parsers
abstract class SiteParser {
  /// The domain this parser handles (e.g., 'acgying.com')
  String get domain;

  /// Parse metadata from HTML content (legacy)
  GameMetadata parse(Document document, String url);

  /// Parse game info from HTML content (new unified model)
  GameInfo? parseGameInfo(Document document, String url) => null;
}

/// Parsed game metadata
class GameMetadata {
  String? title;
  String? version;
  String? intro;
  String? features;
  String? changelog;
  String? downloadUrl;
  String? sourceUrl;
  List<String> imageUrls;
  List<String> tags;
  String? series;

  GameMetadata({
    this.title,
    this.version,
    this.intro,
    this.features,
    this.changelog,
    this.downloadUrl,
    this.sourceUrl,
    this.imageUrls = const [],
    this.tags = const [],
    this.series,
  });

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (version != null) 'version': version,
        if (intro != null) 'intro': intro,
        if (features != null) 'features': features,
        if (changelog != null) 'changelog': changelog,
        if (downloadUrl != null) 'download_url': downloadUrl,
        if (sourceUrl != null) 'source_url': sourceUrl,
        if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
        if (tags.isNotEmpty) 'tags': tags,
        if (series != null) 'series': series,
      };
}

/// Registry of all site parsers
class ParserRegistry {
  static final List<SiteParser> _parsers = [];

  static void register(SiteParser parser) {
    _parsers.add(parser);
  }

  static void unregister(String domain) {
    _parsers.removeWhere((p) => p.domain == domain);
  }

  static SiteParser? getParserForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    for (final parser in _parsers) {
      if (parser.domain.isEmpty) continue;
      if (host.contains(parser.domain) || host == parser.domain) {
        return parser;
      }
    }
    return null;
  }

  static List<SiteParser> get allParsers => List.unmodifiable(_parsers);
}

/// Main scraper that dispatches to site-specific parsers
class HtmlScraper {
  static bool _registered = false;
  static bool _xpathLoaded = false;
  final _log = AppLogger.instance;

  /// Ensure all site parsers are registered (called once).
  void _ensureRegistered() {
    if (_registered) return;
    _registered = true;
    registerAllParsers();
    registerCustomDomainParsers();
  }

  /// Load user-configured XPath parsers from settings.
  Future<void> _ensureXpathParsersLoaded() async {
    if (_xpathLoaded) return;
    _xpathLoaded = true;
    try {
      final prefs = await AppSettings.load();
      final jsonStr = prefs.getString('xpath_parsers');
      if (jsonStr == null || jsonStr.isEmpty) return;
      final List<dynamic> list = jsonDecode(jsonStr);
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final domain = item['domain'] as String? ?? '';
        if (domain.isEmpty) continue;
        final xpathMap = <String, String>{};
        for (final key in ['title', 'description', 'images', 'downloadLinks', 'tags', 'signUnzipCode', 'version', 'changelog', 'features']) {
          final val = item[key] as String?;
          if (val != null && val.isNotEmpty) {
            xpathMap[key] = val;
          }
        }
        if (xpathMap.isNotEmpty) {
          final cookie = item['cookie'] as String?;
          ParserRegistry.register(XpathParser(domain, xpathMap, cookie: cookie));
          _log.info('Scraper', 'Loaded XPath parser for domain: $domain');
        }
      }
    } catch (e) {
      _log.error('Scraper', 'Failed to load XPath parsers', e);
    }
  }

  /// Reload XPath parsers from settings (called after user updates config).
  static Future<void> reloadXpathParsers() async {
    _xpathLoaded = false;
    try {
      final prefs = await AppSettings.load();
      final jsonStr = prefs.getString('xpath_parsers');
      if (jsonStr == null || jsonStr.isEmpty) return;
      final List<dynamic> list = jsonDecode(jsonStr);
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final domain = item['domain'] as String? ?? '';
        if (domain.isEmpty) continue;
        ParserRegistry.unregister(domain);
      }
    } catch (_) {}
    _xpathLoaded = false;
  }

  static Future<void> reloadCustomDomains() async {
    final prefs = await AppSettings.load();
    for (final key in ['domain_acgying', 'domain_feixue', 'domain_vikacg']) {
      final domain = prefs.getString(key) ?? '';
      if (domain.isNotEmpty) {
        ParserRegistry.unregister(domain.toLowerCase());
      }
    }
    await registerCustomDomainParsers();
  }

  GameInfo? scrapeGameInfo(String htmlContent, String url) {
    _ensureRegistered();

    var parser = ParserRegistry.getParserForUrl(url);
    if (parser != null) {
      _log.info('Scraper', 'Using built-in parser: ${parser.runtimeType} for: $url');
    }

    if (parser == null) {
      if (!_xpathLoaded) {
        _log.warning('Scraper', 'XPath parsers not yet loaded (async), returning null for: $url');
        return null;
      }
      parser = ParserRegistry.getParserForUrl(url);
      if (parser == null) {
        _log.warning('Scraper', 'No parser found (built-in or XPath) for URL: $url');
        return null;
      }
      _log.info('Scraper', 'Using XPath parser for: $url');
    }

    try {
      _log.info('Scraper', 'HTML response: ${htmlContent.length} chars, url=$url');
      _log.info('Scraper', 'HTML preview (first 500 chars): ${htmlContent.substring(0, htmlContent.length.clamp(0, 500))}');
      final document = html_parser.parse(htmlContent);
      final root = document.documentElement;
      if (root != null) {
        _log.info('Scraper', 'Parsed document root: <${root.localName}>, children: ${root.children.length}');
        final body = root.querySelector('body');
        if (body != null) {
          _log.info('Scraper', 'Body element: <body>, children: ${body.children.length}, direct child tags: ${body.children.take(10).map((c) => c.localName).join(", ")}');
        } else {
          _log.info('Scraper', 'No <body> element found in document');
        }
      } else {
        _log.info('Scraper', 'No documentElement found');
      }
      final gameInfo = parser.parseGameInfo(document, url);
      if (gameInfo != null) {
        _log.info('Scraper', 'Parsed GameInfo: ${gameInfo.title}');
        return gameInfo;
      }

      final metadata = parser.parse(document, url);
      metadata.sourceUrl = url;
      return _metadataToGameInfo(metadata);
    } catch (e, stackTrace) {
      _log.error('Scraper', 'Parse error for $url', e, stackTrace);
      return null;
    }
  }

  Future<void> ensureLoaded() async {
    _ensureRegistered();
    await _ensureXpathParsersLoaded();
  }

  GameInfo _metadataToGameInfo(GameMetadata metadata) {
    return GameInfo(
      title: metadata.title,
      version: metadata.version,
      tags: metadata.tags,
      category: metadata.series,
      description: metadata.intro,
      features: metadata.features != null ? [metadata.features!] : [],
      changelog: metadata.changelog,
      screenshots: metadata.imageUrls,
      downloads: extractDownloadLinks(metadata.downloadUrl ?? ''),
      sourceUrl: metadata.sourceUrl ?? '',
    );
  }

  GameMetadata? scrape(String htmlContent, String url) {
    _ensureRegistered();

    var parser = ParserRegistry.getParserForUrl(url);
    if (parser == null) {
      _log.warning('Scraper', 'No specific parser found for URL: $url, using generic fallback');
      parser = GenericParser();
    } else {
      _log.info('Scraper', 'Using parser: ${parser.runtimeType} for: $url');
    }

    try {
      final document = html_parser.parse(htmlContent);
      final metadata = parser.parse(document, url);
      metadata.sourceUrl = url;

      // Fallback: if intro is empty, try to find article content area
      if (metadata.intro == null || metadata.intro!.trim().isEmpty) {
        final contentSelectors = [
          'td.t_f',           // Discuz! forums (飞雪ACG etc.)
          'div.t_fsz',        // Discuz! post content wrapper
          'div.pcb',          // Discuz! post content block
          'div.post-content', // WordPress post content
          'div.entry-content',// WordPress/standard entry content
          'div.article-content',// Common article content
          'article',          // HTML5 article element
          'div.content',      // Generic content div
          'main',             // HTML5 main element
          'div.main-content', // Common main content
          'div.post-body',    // Blog post body
        ];

        String? contentText;
        for (final selector in contentSelectors) {
          final element = document.querySelector(selector);
          if (element != null) {
            final text = element.text.trim();
            if (text.length > 50) {
              contentText = text;
              _log.info('Scraper', 'Found content in "$selector" (${text.length} chars)');
              break;
            }
          }
        }

        if (contentText != null) {
          metadata.intro = contentText.substring(0, contentText.length > 1500 ? 1500 : contentText.length) + (contentText.length > 1500 ? '...' : '');
        } else if (document.body != null) {
          // Last resort: use body text
          final bodyText = document.body!.text.trim();
          if (bodyText.length > 50) {
            metadata.intro = bodyText.substring(0, bodyText.length > 1500 ? 1500 : bodyText.length) + (bodyText.length > 1500 ? '...' : '');
            _log.info('Scraper', 'Using body text as fallback intro');
          }
        }
      }

      if (metadata.title != null) {
        _log.info('Scraper', 'Parsed successfully: ${metadata.title}');
      } else {
        _log.warning('Scraper', 'Parser returned null title for: $url');
      }

      metadata.intro = _collapseNewlines(metadata.intro);
      metadata.features = _collapseNewlines(metadata.features);
      metadata.changelog = _collapseNewlines(metadata.changelog);

      return metadata;
    } catch (e, stackTrace) {
      _log.error('Scraper', 'Parse error for $url', e, stackTrace);
      return null;
    }
  }
}

String? _collapseNewlines(String? text) {
  if (text == null) return null;
  return text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
}

/// XPath-based parser for user-configured sites.
/// Uses XPath expressions from settings to extract game info from any site.
class XpathParser extends SiteParser {
  final String _domain;
  final Map<String, String> _xpaths;
  final String? _cookie;

  XpathParser(this._domain, this._xpaths, {String? cookie}) : _cookie = cookie;

  String? get cookie => _cookie;

  @override
  String get domain => _domain;

  @override
  GameInfo? parseGameInfo(Document document, String url) {
    final titleXpath = _xpaths['title'];
    String? rawTitle;
    if (titleXpath != null) {
      rawTitle = XPathEvaluator.queryText(document, titleXpath);
      AppLogger.instance.info('Scraper', '[XpathParser] title xpath=$titleXpath -> ${rawTitle?.substring(0, rawTitle.length.clamp(0, 60)) ?? "null"}');
    }
    if (rawTitle == null || rawTitle.isEmpty) return null;

    final tags = extractBracketsFromTitle(rawTitle) ?? [];
    final category = normalizeSeries(tags.isNotEmpty ? tags.first : null);
    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();
    final version = extractVersion(cleanTitle);
    final titleWithoutVersion = version != null ? removeVersionFromTitle(cleanTitle) : cleanTitle;

    String? description;
    final descXpath = _xpaths['description'];
    if (descXpath != null) {
      final rawDesc = XPathEvaluator.queryText(document, descXpath);
      AppLogger.instance.info('Scraper', '[XpathParser] description xpath=$descXpath -> ${rawDesc != null ? "${rawDesc.length}chars" : "null"}');
      if (rawDesc != null && rawDesc.isNotEmpty) {
        description = _extractSection(rawDesc, '概要') ??
            _extractSection(rawDesc, '游戏介绍') ??
            _extractSection(rawDesc, '简介') ??
            rawDesc;
        description = filterDescription(description);
        if (description.isEmpty) description = null;
      }
    }

    List<String> features = [];
    final featuresXpath = _xpaths['features'];
    if (featuresXpath != null) {
      final featuresText = XPathEvaluator.queryText(document, featuresXpath);
      AppLogger.instance.info('Scraper', '[XpathParser] features xpath=$featuresXpath -> ${featuresText != null ? "${featuresText.length}chars" : "null"}');
      if (featuresText != null) {
        final filtered = filterCommonNoise(featuresText);
        features = filtered
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
      }
    }

    String? changelog;
    final changelogXpath = _xpaths['changelog'];
    if (changelogXpath != null) {
      changelog = XPathEvaluator.queryText(document, changelogXpath);
      AppLogger.instance.info('Scraper', '[XpathParser] changelog xpath=$changelogXpath -> ${changelog != null ? "${changelog.length}chars" : "null"}');
      if (changelog != null) {
        changelog = filterCommonNoise(changelog);
        if (changelog.isEmpty) changelog = null;
      }
    }

    final screenshots = <String>[];
    final imagesXpath = _xpaths['images'];
    if (imagesXpath != null && imagesXpath.isNotEmpty) {
      screenshots.addAll(XPathEvaluator.queryAllAttributes(document, imagesXpath));
      AppLogger.instance.info('Scraper', '[XpathParser] images xpath=$imagesXpath -> ${screenshots.length} urls');
    } else if (descXpath != null) {
      final contentEl = XPathEvaluator.query(document, descXpath);
      if (contentEl != null) {
        for (final img in contentEl.querySelectorAll('img')) {
          final src = img.attributes['data-original'] ??
              img.attributes['zoomfile'] ??
              img.attributes['file'] ??
              img.attributes['src'] ??
              img.attributes['data-src'] ??
              '';
          if (src.isNotEmpty &&
              !src.contains('static/image/common') &&
              !src.contains('smiley') &&
              !src.endsWith('.svg') &&
              !src.endsWith('.ico') &&
              !screenshots.contains(src)) {
            screenshots.add(src);
          }
        }
      }
      AppLogger.instance.info('Scraper', '[XpathParser] images from desc content -> ${screenshots.length} urls');
    }

    final downloads = <DownloadLink>[];
    final dlXpath = _xpaths['downloadLinks'];
    if (dlXpath != null) {
      final dlText = XPathEvaluator.queryText(document, dlXpath);
      AppLogger.instance.info('Scraper', '[XpathParser] downloadLinks xpath=$dlXpath -> ${dlText != null ? "${dlText.length}chars" : "null"}');
      if (dlText != null) {
        final filtered = dlText
            .replaceAll('本帖隱藏的內容', '')
            .replaceAll(RegExp(r'[^\n]*(优惠码|折扣码|优惠卷)[^\n]*'), '')
            .replaceAll(RegExp(r'[^\n]*(VIP|vip|免飞猫)[^\n]*'), '')
            .trim();
        downloads.addAll(extractDownloadLinks(filtered));
      }
    }

    List<String> tagList = [];
    final tagsXpath = _xpaths['tags'];
    if (tagsXpath != null) {
      tagList = XPathEvaluator.queryAllTexts(document, tagsXpath);
      AppLogger.instance.info('Scraper', '[XpathParser] tags xpath=$tagsXpath -> ${tagList.length} tags');
    }
    for (final tag in tagList) {
      if (!tags.contains(tag)) tags.add(tag);
    }

    String? unzipCode;
    final signXpath = _xpaths['signUnzipCode'];
    if (signXpath != null) {
      final signText = XPathEvaluator.queryText(document, signXpath);
      AppLogger.instance.info('Scraper', '[XpathParser] signUnzipCode xpath=$signXpath -> ${signText != null ? "found" : "null"}');
      if (signText != null) {
        unzipCode = extractUnzipCode(signText);
      }
    }

    AppLogger.instance.info('Scraper', '[XpathParser] result: title=$titleWithoutVersion, version=$version, tags=${tags.length}, imgs=${screenshots.length}, dl=${downloads.length}');

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
      sourceUrl: url,
    );
  }

  @override
  GameMetadata parse(Document document, String url) {
    final gameInfo = parseGameInfo(document, url);
    if (gameInfo == null) return GameMetadata();
    return GameMetadata(
      title: gameInfo.title,
      version: gameInfo.version,
      intro: gameInfo.description,
      features: gameInfo.features.isNotEmpty ? gameInfo.features.join('\n') : null,
      changelog: gameInfo.changelog,
      downloadUrl: gameInfo.downloadUrl,
      sourceUrl: url,
      imageUrls: gameInfo.screenshots,
      tags: gameInfo.tags,
      series: gameInfo.category,
    );
  }

  static String? _extractSection(String fullText, String sectionName) {
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

/// Generic fallback parser that tries common HTML patterns
class GenericParser extends SiteParser {
  @override
  String get domain => '';

  @override
  GameMetadata parse(Document document, String url) {
    final metadata = GameMetadata();

    // Try to get title from <title> or <h1>
    final titleEl =
        document.querySelector('h1') ?? document.querySelector('title');
    metadata.title = titleEl?.text.trim();

    // Try to get description from meta tag
    final descMeta = document.querySelector('meta[name="description"]');
    if (descMeta != null) {
      metadata.intro = descMeta.attributes['content']?.trim();
    }

    // Try to get images
    final images = document.querySelectorAll('img');
    metadata.imageUrls = images
        .map((img) => img.attributes['src'] ?? '')
        .where((src) =>
            src.isNotEmpty &&
            !src.endsWith('.svg') &&
            !src.endsWith('.ico'))
        .toList();

    return metadata;
  }
}
