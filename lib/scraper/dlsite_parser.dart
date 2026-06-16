import 'package:html/dom.dart';
import 'html_parser.dart';
import 'parse_utils.dart';

class DlsiteParser extends SiteParser {
  @override
  String get domain => 'dlsite';

  final List<String> _descriptionImageUrls = [];

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
      description = _extractDescriptionWithImages(descEl);
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

    // 截图列表：封面 + slider中的图片 + 描述中的图片（去重）
    final screenshots = <String>[];
    if (coverImage != null) {
      screenshots.add(coverImage);
    }
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
    // 将描述中的图片也加入下载列表
    for (final imgUrl in _descriptionImageUrls) {
      if (!screenshots.contains(imgUrl)) {
        screenshots.add(imgUrl);
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

  String _extractDescriptionWithImages(Element descEl) {
    final buffer = StringBuffer();
    _processNode(descEl, buffer);
    return buffer.toString().trim();
  }

  void _processNode(Element element, StringBuffer buffer) {
    for (final node in element.nodes) {
      if (node is Text) {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          buffer.write(text);
        }
      } else if (node is Element) {
        if (node.localName == 'img') {
          final src = node.attributes['data-original'] ??
              node.attributes['data-src'] ??
              node.attributes['src'] ??
              '';
          if (src.isNotEmpty && !src.contains('static/image') && !src.endsWith('.svg')) {
            final imgUrl = src.startsWith('//') ? 'https:$src' : src;
            _descriptionImageUrls.add(imgUrl);
            buffer.write('\n[图片:$imgUrl]\n');
          }
        } else if (node.localName == 'br') {
          buffer.write('\n');
        } else if (node.localName == 'p' || node.localName == 'div') {
          _processNode(node, buffer);
          buffer.write('\n');
        } else if (node.localName == 'h3' || node.localName == 'h4') {
          buffer.write('\n${node.text.trim()}\n');
        } else {
          _processNode(node, buffer);
        }
      }
    }
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
