import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/app_update_service.dart';
import 'package:http/http.dart' as http;

class _FakeHttpClient extends http.BaseClient {
  final int statusCode;
  final String body;

  _FakeHttpClient({
    required this.statusCode,
    required this.body,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      headers: {'content-type': 'text/plain; charset=utf-8'},
    );
  }
}

void main() {
  test('selects the highest version from changelog entries', () async {
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        statusCode: 200,
        body: '''
# Changelog

## v1.9.0
- Older

## v1.10.0
- Newest
''',
      ),
    );

    final result = await service.checkForUpdate(currentVersion: '1.8.0');

    expect(result.status, AppUpdateStatus.updateAvailable);
    expect(result.latestEntry?.version, '1.10.0');
    expect(result.latestEntry?.body, contains('Newest'));
  });

  test('returns all versions newer than the current version', () async {
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        statusCode: 200,
        body: '''
## v1.4.7
- Newest

## v1.4.6
- Middle

## v1.4.5
- Current
''',
      ),
    );

    final result = await service.checkForUpdate(currentVersion: '1.4.5');

    expect(
      result.updateEntries.map((entry) => entry.version),
      ['1.4.7', '1.4.6'],
    );
  });

  test('returns up-to-date when remote version is not newer', () async {
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(
        statusCode: 200,
        body: '## v1.4.6\n- Older release',
      ),
    );

    final result = await service.checkForUpdate(currentVersion: '1.4.7');

    expect(result.status, AppUpdateStatus.upToDate);
    expect(result.latestEntry?.version, '1.4.6');
  });

  test('returns unavailable for failed HTTP response', () async {
    final service = AppUpdateService(
      httpClient: _FakeHttpClient(statusCode: 503, body: ''),
    );

    final result = await service.checkForUpdate(currentVersion: '1.4.7');

    expect(result.status, AppUpdateStatus.unavailable);
    expect(result.currentVersion, '1.4.7');
  });

  test('builds the release ZIP URL from the version', () {
    expect(
      AppUpdateService.buildReleaseDownloadUri('1.4.8').toString(),
      'https://github.com/LinYuanovo/HGame-Manager/releases/download/'
      'v1.4.8/HGame-Manager-v1.4.8-windows.zip',
    );
  });

  test('checks update frequency thresholds', () {
    final now = DateTime(2026, 8, 9, 12);

    expect(
      AppUpdateService.shouldCheck(
        enabled: true,
        frequency: AppUpdateFrequency.startup,
        lastChecked: now,
        now: now,
      ),
      isTrue,
    );
    expect(
      AppUpdateService.shouldCheck(
        enabled: true,
        frequency: AppUpdateFrequency.daily,
        lastChecked: now.subtract(const Duration(hours: 23)),
        now: now,
      ),
      isFalse,
    );
    expect(
      AppUpdateService.shouldCheck(
        enabled: true,
        frequency: AppUpdateFrequency.weekly,
        lastChecked: now.subtract(const Duration(days: 7)),
        now: now,
      ),
      isTrue,
    );
    expect(
      AppUpdateService.shouldCheck(
        enabled: false,
        frequency: AppUpdateFrequency.monthly,
        lastChecked: null,
        now: now,
      ),
      isFalse,
    );
  });

  group('extractAndVerifyZip', () {
    test('extracts a valid zip successfully', () async {
      final temp = await Directory.systemTemp.createTemp('update_zip_test_');
      try {
        final zipFile = File('${temp.path}\\update.zip')
          ..writeAsBytesSync(
            _buildZip({'hgame_manager.exe': 'exe-bytes', 'data\\readme.txt': 'hi'}),
          );
        final dest = Directory('${temp.path}\\out');
        await dest.create();

        await AppUpdateService.extractAndVerifyZip(zipFile, dest);

        expect(
          await File('${dest.path}\\hgame_manager.exe').readAsString(),
          'exe-bytes',
        );
        expect(
          await File('${dest.path}\\data\\readme.txt').readAsString(),
          'hi',
        );
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('rejects corrupted zip instead of extracting silently', () async {
      final temp = await Directory.systemTemp.createTemp('update_zip_test_');
      try {
        final bytes = _buildZip({
          'data.bin': List<int>.generate(64 * 1024, (i) => (i * 31) % 251),
        });
        // 篡改压缩数据区域的一个字节
        bytes[bytes.length ~/ 3] ^= 0xFF;
        final zipFile = File('${temp.path}\\update.zip')..writeAsBytesSync(bytes);
        final dest = Directory('${temp.path}\\out');
        await dest.create();

        await expectLater(
          () => AppUpdateService.extractAndVerifyZip(zipFile, dest),
          throwsA(anything),
        );
      } finally {
        await temp.delete(recursive: true);
      }
    });
  });
}

List<int> _buildZip(Map<String, Object> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final data =
        content is String ? utf8.encode(content) : content as List<int>;
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return ZipEncoder().encode(archive);
}
