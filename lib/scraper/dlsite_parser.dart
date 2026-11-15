import 'dart:convert';

import 'package:html/dom.dart';
import 'html_parser.dart';
import 'parse_utils.dart';
import 'rich_text_extractor.dart';

class DlsiteParser extends SiteParser {
  @override
  String get domain => 'dlsite';

  final List<String> _descriptionImageUrls = [];

  @override
  GameInfo? parseGameInfo(Document document, String url) {
    // 每次解析前清空描述图片列表
    _descriptionImageUrls.clear();

    final titleEl = document.querySelector('#work_name');
    final product = _findProduct(document, url, titleEl?.text.trim());
    final rawTitle = _text(titleEl?.text) ?? _text(product?['name']);
    if (rawTitle == null || rawTitle.isEmpty) return null;

    final tags = extractBracketsFromTitle(rawTitle) ?? [];
    final cleanTitle = rawTitle
        .replaceAll(RegExp(r'【[^】]*】'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .trim();

    final galleryImages = <String>[];
    // 新版画廊有两种容器；控制栏和懒加载节点可能混有缩略图。
    final galleryNodes = document.querySelectorAll(
        '.product-slider-data [data-src], #work_visual .slider_body img, '
        '.work_slider img');
    for (final image in galleryNodes) {
      final imageUrl =
          _imageUrl(RichTextExtractor.resolveImageUrl(image, url), url);
      if (imageUrl != null && !galleryImages.contains(imageUrl)) {
        galleryImages.add(imageUrl);
      }
    }
    for (final imageUrl in _productImages(product?['image'], url)) {
      if (!galleryImages.contains(imageUrl)) galleryImages.add(imageUrl);
    }
    final ogImage = document
        .querySelector('meta[property="og:image"]')
        ?.attributes['content'];
    final coverImage = galleryImages.isNotEmpty
        ? galleryImages.first
        : _imageUrl(ogImage, url, allowThumbnail: true);

    String? description;
    String? descriptionHtml;
    var hasBodyText = false;
    final legacyDescription =
        document.querySelector('[itemprop="description"]');
    final descriptionParts = legacyDescription != null &&
            (legacyDescription.text.trim().isNotEmpty ||
                legacyDescription.querySelector('img') != null)
        ? [legacyDescription]
        : document.querySelectorAll('.c-productContent');
    if (descriptionParts.isNotEmpty) {
      final descEl = Element.tag('div');
      for (final part in descriptionParts) {
        descEl.append(part.clone(true));
      }
      // 富文本与图片下载列表使用同一绝对 URL，下载后可统一替换本地引用。
      for (final image in descEl.querySelectorAll('img')) {
        final imageUrl = RichTextExtractor.resolveImageUrl(image, url);
        if (imageUrl == null) continue;
        image.attributes['src'] = imageUrl;
        image.attributes.remove('data-original');
        image.attributes.remove('data-src');
      }
      description = _extractDescriptionWithImages(descEl);
      descriptionHtml = descEl.innerHtml;
      final textOnly = descEl.clone(true);
      for (final node in textOnly.querySelectorAll(
          'h1, h2, h3, h4, h5, h6, img, script, style, noscript')) {
        node.remove();
      }
      hasBodyText = textOnly.text.trim().isNotEmpty;
    }
    // 结构化摘要较短，只补缺失正文；纯图片介绍仍保留内嵌图和原有 HTML。
    final summary = _text(product?['description']);
    if (!hasBodyText && summary != null) {
      description =
          [summary, if (_text(description) != null) description!].join('\n\n');
      final paragraph = Element.tag('p')..text = summary;
      descriptionHtml = '${paragraph.outerHtml}${descriptionHtml ?? ''}';
    }

    // 提取厂商名和链接
    String? maker;
    String? makerUrl;
    final makerEl = document.querySelector('.maker_name a') ??
        document.querySelector('.c-productInfo__makerName');
    if (makerEl != null) {
      maker = makerEl.text.trim();
      final href = makerEl.attributes['href'];
      if (href != null && href.isNotEmpty) {
        makerUrl = Uri.tryParse(url)?.resolve(href).toString();
      }
    }
    if (_text(maker) == null) {
      final brand = product?['brand'];
      maker = _text(brand is Map ? brand['name'] : brand);
      makerUrl = brand is Map ? _httpUrl(brand['url'], url) : null;
    }

    final tagList = <String>[];
    // 厂商名作为第一个标签
    if (maker != null && maker.isNotEmpty) {
      tagList.add(maker);
    }
    final mainGenreLinks = document
        .querySelectorAll('.main_genre a, .c-productInfo__item a.tag_general, '
            '.c-productInfo__item a.tag_game, '
            'dd.c-productInfo__value a.tag_general, '
            'dd.c-productInfo__value a.tag_game');
    for (final a in mainGenreLinks) {
      final tag = a.text.trim();
      if (tag.isNotEmpty && !tagList.contains(tag)) {
        tagList.add(tag);
      }
    }

    final tableRows =
        document.querySelectorAll('table.work_work_table tr, table tr');
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

    // 截图列表：封面 + 画廊原图 + 描述中的图片（去重）
    final screenshots = <String>[];
    if (coverImage != null) {
      screenshots.add(coverImage);
    }
    for (final imageUrl in galleryImages) {
      if (!screenshots.contains(imageUrl)) {
        screenshots.add(imageUrl);
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
      descriptionHtml: descriptionHtml,
      screenshots: screenshots,
      maker: maker,
      makerUrl: makerUrl,
      sourceUrl: url,
    );
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static String? _httpUrl(Object? value, String baseUrl) {
    final raw = _text(value);
    if (raw == null) return null;
    final parsed = Uri.tryParse(raw.startsWith('//') ? 'https:$raw' : raw);
    if (parsed == null) return null;
    final resolved = Uri.tryParse(baseUrl)?.resolveUri(parsed);
    if (resolved == null ||
        !{'http', 'https'}.contains(resolved.scheme) ||
        resolved.host.isEmpty) {
      return null;
    }
    return resolved.toString();
  }

  static String? _imageUrl(Object? value, String baseUrl,
      {bool allowThumbnail = false}) {
    final resolved = _httpUrl(value, baseUrl);
    if (resolved == null) return null;
    final imagePath = Uri.parse(resolved).path.toLowerCase();
    if (RegExp(r'\.(?:mp4|webm|m3u8|svg|ico)$').hasMatch(imagePath) ||
        (!allowThumbnail &&
            (imagePath.contains('/resize/') ||
                RegExp(r'[_-]\d+x\d+\.[^/]+$').hasMatch(imagePath)))) {
      return null;
    }
    return resolved;
  }

  static Iterable<String> _productImages(Object? value, String url) sync* {
    if (value is List) {
      for (final image in value) {
        yield* _productImages(image, url);
      }
    } else {
      final raw = value is Map
          ? _text(value['contentUrl']) ?? _text(value['url'])
          : value;
      final imageUrl = _imageUrl(raw, url);
      if (imageUrl != null) yield imageUrl;
    }
  }

  static Iterable<Map<String, dynamic>> _products(Object? value) sync* {
    if (value is List) {
      for (final entry in value) {
        yield* _products(entry);
      }
    } else if (value is Map<String, dynamic>) {
      final type = value['@type'];
      if (type == 'Product' || (type is List && type.contains('Product'))) {
        yield value;
      }
      yield* _products(value['@graph']);
    }
  }

  static final _idPattern =
      RegExp(r'\b(?:RJ|RE|VJ)\d{4,}\b', caseSensitive: false);

  static Set<String> _productIds(Map<String, dynamic> product) {
    final offers = product['offers'];
    final values = [
      for (final key in ['sku', 'productID', 'url', '@id']) product[key],
      if (offers is Map) offers['url'],
      if (offers is List)
        for (final offer in offers)
          if (offer is Map) offer['url'],
    ];
    return {
      for (final value in values.whereType<String>())
        for (final match in _idPattern.allMatches(value))
          match.group(0)!.toUpperCase(),
    };
  }

  static Map<String, dynamic>? _findProduct(
      Document document, String url, String? title) {
    final products = <Map<String, dynamic>>[];
    for (final script
        in document.querySelectorAll('script[type="application/ld+json"]')) {
      try {
        products.addAll(_products(jsonDecode(script.text)));
      } on FormatException {
        // 个别损坏的结构化数据不影响其余脚本和正文解析。
      }
    }
    final expectedId = _idPattern.firstMatch(url)?.group(0)?.toUpperCase();
    final unidentified = <Map<String, dynamic>>[];
    final matching = <Map<String, dynamic>>[];
    for (final product in products) {
      final ids = _productIds(product);
      if (ids.isEmpty) {
        unidentified.add(product);
      } else if (expectedId != null && ids.every((id) => id == expectedId)) {
        matching.add(product);
      }
    }
    if (matching.length == 1) return matching.single;
    final candidates = matching.isNotEmpty ? matching : unidentified;
    final titled = candidates
        .where((product) => title != null && _text(product['name']) == title)
        .toList();
    if (titled.length == 1) return titled.single;
    // 无标识的唯一 Product 可作兜底，多作品且无对应标题时不猜测。
    return products.length == 1 && unidentified.length == 1
        ? unidentified.single
        : null;
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
        if (node.localName == 'script' ||
            node.localName == 'style' ||
            node.localName == 'noscript') {
          continue;
        } else if (node.localName == 'img') {
          final src = node.attributes['data-original'] ??
              node.attributes['data-src'] ??
              node.attributes['src'] ??
              '';
          if (src.isNotEmpty &&
              !src.contains('static/image') &&
              !src.endsWith('.svg')) {
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
