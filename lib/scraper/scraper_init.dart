import 'site_parsers.dart';

/// Initialize scrapers by registering all site parsers.
/// This is now also handled automatically by HtmlScraper._ensureRegistered(),
/// but kept for explicit initialization if needed.
void initScrapers() {
  registerAllParsers();
}
