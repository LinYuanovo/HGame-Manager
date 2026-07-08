import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/changelog_parser.dart';

void main() {
  test('parseChangelogEntries keeps version order and body', () {
    final entries = parseChangelogEntries('''
# Changelog

## v1.4.5 (2026-07-08)

### 新功能

- WebView2 静默加载

## v1.4.4 (2026-07-06)

- 旧版本内容
''');

    expect(entries, hasLength(2));
    expect(entries.first.version, '1.4.5');
    expect(entries.first.date, '2026-07-08');
    expect(entries.first.body, contains('WebView2 静默加载'));
    expect(entries.last.version, '1.4.4');
  });
}
