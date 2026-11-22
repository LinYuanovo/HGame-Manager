import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'design_tokens_exe_test.dart' as tokens;
import 'duplicate_import_exe_test.dart' as duplicate;
import 'image_refresh_windows_test.dart' as images;
import 'scrape_review_windows_test.dart' as review;
import 'ui_translation_merge_test.dart' as translation;
import 'webdav_download_windows_test.dart' as webdav;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    if (!Platform.isWindows) {
      throw StateError('原生验收仅支持 Windows');
    }
  });
  group('翻译持久化与显示', translation.main);
  group('重复导入', duplicate.main);
  group('主题与页面', tokens.main);
  group('封面刷新', images.main);
  group('WebDAV 下载', webdav.main);
  group('刮削确认', review.main);
}
