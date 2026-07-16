import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/backup_image_service.dart';
import 'package:hgame_manager/core/services/webdav_service.dart';

void main() {
  test('WebDAV 增量图片仅上传云端缺少的文件', () async {
    final tempDir = await Directory.systemTemp.createTemp('hgm_webdav_test_');
    final source = File('${tempDir.path}${Platform.pathSeparator}cover.png');
    await source.writeAsBytes([1, 2, 3, 4]);
    final uploadedNames = <String>{};
    var uploadCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(_propfindResponse(uploadedNames));
      } else if (request.method == 'PUT') {
        await request.drain<void>();
        uploadedNames.add(request.uri.pathSegments.last);
        uploadCount++;
        request.response.statusCode = 201;
      } else if (request.method == 'MKCOL') {
        request.response.statusCode = 201;
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    try {
      final service = WebdavService();
      final asset = BackupImageAsset(
        originalPath: source.path,
        archivePath: 'images/test.png',
        filePath: source.path,
      );
      final serverUrl = 'http://${server.address.host}:${server.port}';

      expect(
        await service.uploadMissingBackupImages(
          serverUrl: serverUrl,
          username: 'user',
          password: 'password',
          assets: [asset],
        ),
        isTrue,
      );
      expect(uploadCount, 1);

      expect(
        await service.uploadMissingBackupImages(
          serverUrl: serverUrl,
          username: 'user',
          password: 'password',
          assets: [asset],
        ),
        isTrue,
      );
      expect(uploadCount, 1);
    } finally {
      await server.close(force: true);
      await tempDir.delete(recursive: true);
    }
  });
}

String _propfindResponse(Set<String> fileNames) {
  final files = fileNames.map(
    (name) => '''
<D:response>
  <D:href>/hgame_manager_backups/images/$name</D:href>
  <D:propstat>
    <D:prop>
      <D:getcontentlength>4</D:getcontentlength>
    </D:prop>
    <D:status>HTTP/1.1 200 OK</D:status>
  </D:propstat>
</D:response>''',
  );
  return '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
${files.join('\n')}
</D:multistatus>''';
}
