import 'dart:async';
import 'dart:convert';

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
}
