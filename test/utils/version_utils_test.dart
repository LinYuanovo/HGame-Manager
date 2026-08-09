import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/version_utils.dart';

void main() {
  test('compares numeric version segments', () {
    expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    expect(compareVersions('1.4.7', '1.4.7'), 0);
    expect(compareVersions('v1.4.6', '1.4.7'), lessThan(0));
  });

  test('treats missing trailing segments as zero', () {
    expect(compareVersions('1.4', '1.4.0'), 0);
    expect(compareVersions('2', '1.9.9'), greaterThan(0));
  });
}
