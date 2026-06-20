import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

class SteamHtmlConverter {
  static String convertToPlainText(String html) {
    final document = html_parser.parse(html);
    final body = document.body;
    if (body == null) return '';

    final buffer = StringBuffer();
    _processNode(body, buffer);
    return buffer.toString().trim();
  }

  static void _processNode(Element element, StringBuffer buffer) {
    for (final node in element.nodes) {
      if (node is Text) {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          buffer.write(text);
        }
      } else if (node is Element) {
        final tag = node.localName;
        switch (tag) {
          case 'h1':
          case 'h2':
          case 'h3':
          case 'h4':
            final text = _getElementText(node).trim();
            if (text.isNotEmpty) {
              if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
                buffer.write('\n');
              }
              buffer.write('\n$text\n');
            }
            break;
          case 'p':
            final text = _getElementText(node).trim();
            if (text.isNotEmpty) {
              buffer.write(text);
              buffer.write('\n');
            }
            break;
          case 'br':
            buffer.write('\n');
            break;
          case 'ul':
          case 'ol':
            buffer.write('\n');
            for (final li in node.children) {
              if (li.localName == 'li') {
                final text = _getElementText(li).trim();
                if (text.isNotEmpty) {
                  buffer.write('- $text\n');
                }
              }
            }
            break;
          case 'img':
            final src = node.attributes['src'] ?? '';
            if (src.isNotEmpty && !src.endsWith('.svg') && !src.endsWith('.ico')) {
              buffer.write('\n[图片:$src]\n');
            }
            break;
          case 'video':
            final videoUrl = _extractBestVideoUrl(node);
            if (videoUrl != null) {
              buffer.write('\n[视频:$videoUrl]\n');
            } else {
              final poster = node.attributes['poster'] ?? '';
              if (poster.isNotEmpty) {
                buffer.write('\n[图片:$poster]\n');
              }
            }
            break;
          case 'strong':
          case 'b':
            final text = _getElementText(node).trim();
            if (text.isNotEmpty) {
              buffer.write(text);
            }
            break;
          case 'span':
            final innerVideo = node.querySelector('video');
            if (innerVideo != null) {
              final videoUrl = _extractBestVideoUrl(innerVideo);
              if (videoUrl != null) {
                buffer.write('\n[视频:$videoUrl]\n');
              } else {
                final poster = innerVideo.attributes['poster'] ?? '';
                if (poster.isNotEmpty) {
                  buffer.write('\n[图片:$poster]\n');
                }
              }
            } else {
              _processNode(node, buffer);
            }
            break;
          default:
            _processNode(node, buffer);
        }
      }
    }
  }

  /// Extract the best video URL from a <video> element.
  /// Priority: webm > mp4 > any source > poster fallback
  static String? _extractBestVideoUrl(Element videoEl) {
    final sources = videoEl.querySelectorAll('source');
    String? webmUrl;
    String? mp4Url;
    String? fallbackUrl;

    for (final source in sources) {
      final src = source.attributes['src'] ?? '';
      if (src.isEmpty) continue;

      final type = source.attributes['type'] ?? '';
      if (src.contains('.webm') || type.contains('webm')) {
        webmUrl ??= src;
      } else if (src.contains('.mp4') || type.contains('mp4')) {
        mp4Url ??= src;
      } else {
        fallbackUrl ??= src;
      }
    }

    return webmUrl ?? mp4Url ?? fallbackUrl;
  }

  static String _getElementText(Element element) {
    final buffer = StringBuffer();
    for (final child in element.nodes) {
      if (child is Text) {
        buffer.write(child.text);
      } else if (child is Element) {
        switch (child.localName) {
          case 'br':
            buffer.write('\n');
            break;
          case 'strong':
          case 'b':
            buffer.write(_getElementText(child));
            break;
          case 'img':
            final src = child.attributes['src'] ?? '';
            if (src.isNotEmpty) {
              buffer.write('\n[图片:$src]\n');
            }
            break;
          case 'video':
            final videoUrl = _extractBestVideoUrl(child);
            if (videoUrl != null) {
              buffer.write('\n[视频:$videoUrl]\n');
            } else {
              final poster = child.attributes['poster'] ?? '';
              if (poster.isNotEmpty) {
                buffer.write('\n[图片:$poster]\n');
              }
            }
            break;
          case 'span':
            final innerVideo = child.querySelector('video');
            if (innerVideo != null) {
              final videoUrl = _extractBestVideoUrl(innerVideo);
              if (videoUrl != null) {
                buffer.write('\n[视频:$videoUrl]\n');
              } else {
                final poster = innerVideo.attributes['poster'] ?? '';
                if (poster.isNotEmpty) {
                  buffer.write('\n[图片:$poster]\n');
                }
              }
            } else {
              buffer.write(_getElementText(child));
            }
            break;
          case 'ul':
            buffer.write('\n');
            for (final li in child.children) {
              if (li.localName == 'li') {
                final text = _getElementText(li).trim();
                if (text.isNotEmpty) {
                  buffer.write('- $text\n');
                }
              }
            }
            break;
          default:
            buffer.write(_getElementText(child));
        }
      }
    }
    return buffer.toString();
  }
}
