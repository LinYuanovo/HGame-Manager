import 'dart:convert';

class ScrapedImageReferenceRewriter {
  const ScrapedImageReferenceRewriter._();

  static String replacePlainTextImages(
    String value,
    Map<String, String> urlToLocal,
  ) {
    if (value.isEmpty || urlToLocal.isEmpty) return value;
    var result = value;
    for (final entry in urlToLocal.entries) {
      for (final candidate in _referenceCandidates(entry.key)) {
        result = result.replaceAll(
          '[图片:$candidate]',
          '[图片:${entry.value}]',
        );
      }
    }
    return result;
  }

  static String replaceHtmlImages(
    String value,
    Map<String, String> urlToLocal,
  ) {
    if (value.isEmpty || urlToLocal.isEmpty) return value;
    var result = value;
    for (final entry in urlToLocal.entries) {
      for (final candidate in _referenceCandidates(entry.key)) {
        result = result.replaceAll(candidate, entry.value);
      }
    }
    return result;
  }

  static String replaceAllReferences(
    String value,
    Map<String, String> urlToLocal,
  ) {
    if (value.isEmpty || urlToLocal.isEmpty) return value;
    return replaceHtmlImages(
      replacePlainTextImages(value, urlToLocal),
      urlToLocal,
    );
  }

  static Set<String> _referenceCandidates(String value) {
    final candidates = <String>{value};
    if (value.startsWith('https:')) {
      candidates.add(value.replaceFirst('https:', ''));
    } else if (value.startsWith('http:')) {
      candidates.add(value.replaceFirst('http:', ''));
    }

    final htmlEscaped = const HtmlEscape(HtmlEscapeMode.element).convert(value);
    candidates.add(htmlEscaped);
    if (htmlEscaped.startsWith('https:')) {
      candidates.add(htmlEscaped.replaceFirst('https:', ''));
    } else if (htmlEscaped.startsWith('http:')) {
      candidates.add(htmlEscaped.replaceFirst('http:', ''));
    }
    return candidates;
  }
}
