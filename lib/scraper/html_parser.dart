import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../core/services/app_logger.dart';
import 'site_parsers.dart';
import 'parse_utils.dart';

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
  final _log = AppLogger.instance;

  /// Ensure all site parsers are registered (called once).
  void _ensureRegistered() {
    if (_registered) return;
    _registered = true;
    registerAllParsers();
  }

  GameInfo? scrapeGameInfo(String htmlContent, String url) {
    _ensureRegistered();

    var parser = ParserRegistry.getParserForUrl(url);
    if (parser == null) {
      _log.warning('Scraper', 'No specific parser found for URL: $url');
      return null;
    }

    try {
      final document = html_parser.parse(htmlContent);
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
