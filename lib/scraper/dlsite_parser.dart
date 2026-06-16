import 'package:html/dom.dart';
import 'html_parser.dart';
import 'parse_utils.dart';

class DlsiteParser extends SiteParser {
  @override
  String get domain => 'dlsite';

  @override
  GameInfo? parseGameInfo(Document document, String url) {
    final titleEl = document.querySelector('#work_name');
    var rawTitle = titleEl?.text.trim();
    if (rawTitle == null || rawTitle.isEmpty) return null;

    final tags = extractBracketsFromTitle(rawTitle) ?? [];
    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();

    String? coverImage;
    final productSlider = document.querySelector('.product-slider-data');
    if (productSlider != null) {
      final firstSlide = productSlider.querySelector('div[data-src]');
      if (firstSlide != null) {
        final dataSrc = firstSlide.attributes['data-src'];
        if (dataSrc != null && dataSrc.isNotEmpty) {
          coverImage = dataSrc.startsWith('//') ? 'https:$dataSrc' : dataSrc;
        }
      }
    }
    coverImage ??= document.querySelector('meta[property="og:image"]')
        ?.attributes['content'];

    String? description;
    final descEl = document.querySelector('[itemprop="description"]');
    if (descEl != null) {
      description = descEl.text.trim();
    }

    final tagList = <String>[];
    final mainGenreLinks = document.querySelectorAll('.main_genre a');
    for (final a in mainGenreLinks) {
      final tag = a.text.trim();
      if (tag.isNotEmpty && !tagList.contains(tag)) {
        tagList.add(tag);
      }
    }

    final tableRows = document.querySelectorAll('table.work_work_table tr, table tr');
    for (final row in tableRows) {
      final th = row.querySelector('th');
      final td = row.querySelector('td');
      if (th != null && td != null) {
        final label = th.text.trim();
        if (['ジャンル', '作品形式', '販売形式', '年齢指定'].contains(label)) {
          final links = td.querySelectorAll('a');
          for (final a in links) {
            final tag = a.text.trim();
            if (tag.isNotEmpty && !tagList.contains(tag)) {
              tagList.add(tag);
            }
          }
        }
      }
    }

    final screenshots = <String>[];
    if (productSlider != null) {
      final slides = productSlider.querySelectorAll('div[data-src]');
      for (final slide in slides) {
        final dataSrc = slide.attributes['data-src'];
        if (dataSrc != null && dataSrc.isNotEmpty) {
          final imgUrl = dataSrc.startsWith('//') ? 'https:$dataSrc' : dataSrc;
          if (!screenshots.contains(imgUrl)) {
            screenshots.add(imgUrl);
          }
        }
      }
    }

    return GameInfo(
      title: cleanTitle,
      tags: [...tags, ...tagList],
      description: description,
      screenshots: screenshots,
      sourceUrl: url,
    );
  }

  @override
  GameMetadata parse(Document document, String url) {
    final gameInfo = parseGameInfo(document, url);
    if (gameInfo == null) return GameMetadata();
    return GameMetadata(
      title: gameInfo.title,
      intro: gameInfo.description,
      tags: gameInfo.tags,
      imageUrls: gameInfo.screenshots,
      sourceUrl: url,
    );
  }
}
