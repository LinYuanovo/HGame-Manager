import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/media_reference_parser.dart';

void main() {
  group('MediaReferenceParser', () {
    test('extracts image paths containing bracketed folder names', () {
      const imagePath =
          r'E:\Games\Cleared\Backup\[SLG] Game Title\HGMDatas\images\1.jpg';

      final paths = MediaReferenceParser.extractImagePaths(
        'intro\n[图片:$imagePath]\ntext',
      ).toList();

      expect(paths, [imagePath]);
    });

    test('replaces only full image tag lines', () {
      const imagePath =
          r'E:\Games\Cleared\Backup\[SLG] Game Title\HGMDatas\images\1.jpg';

      final replaced = MediaReferenceParser.replaceImageLines(
        'intro\n[图片:$imagePath]\ntext',
        (path) => '![]($path)',
      );

      expect(replaced, 'intro\n![]($imagePath)\ntext');
    });

    test('replaces inline image paths containing brackets', () {
      const imagePath =
          r'E:\Games\Cleared\Backup\[SLG] Game Title\HGMDatas\images\1.jpg';

      final replaced = MediaReferenceParser.replaceImageLines(
        'before [图片:$imagePath] after',
        (path) => '![]($path)',
      );

      expect(replaced, 'before ![]($imagePath) after');
    });
  });
}
