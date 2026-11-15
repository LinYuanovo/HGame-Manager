import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'metadata_translation_settings_exe_test.dart' as translation;
import 'release_merge_validation.dart' as release;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('翻译内联设置', translation.main);
  group('界面与业务回归', release.main);
}
