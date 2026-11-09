import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/backup_image_service.dart';
import 'package:hgame_manager/core/services/webdav_service.dart';

void main() {
  test('两种备份上传复用流式请求并保留完整字节', () async {
    final directory =
        await Directory.systemTemp.createTemp('hgm_stream_backup_');
    final source = File('${directory.path}${Platform.pathSeparator}backup.zip');
    final bytes = List<int>.generate(8 * 1024 * 1024, (index) => index % 251);
    await source.writeAsBytes(bytes);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final lengths = <int>[];
    final matched = <bool>[];
    var reject = false;
    server.listen((request) async {
      if (request.method == 'PUT') {
        var offset = 0;
        var same = true;
        await for (final chunk in request) {
          for (final value in chunk) {
            if (offset >= bytes.length || value != bytes[offset]) same = false;
            offset++;
          }
        }
        lengths.add(request.contentLength);
        matched.add(same && offset == bytes.length);
        request.response.statusCode = reject ? 507 : 201;
      } else {
        await request.drain<void>();
        request.response.statusCode = 201;
      }
      await request.response.close();
    });
    try {
      final service = WebdavService();
      final url = 'http://${server.address.host}:${server.port}';
      expect(
          await service.uploadBackup(
              serverUrl: url,
              username: 'user',
              password: 'test',
              localFilePath: source.path),
          isTrue);
      expect(
          await service.uploadGameBackup(
              serverUrl: url,
              username: 'user',
              password: 'test',
              gameFolder: '游戏',
              localFilePath: source.path),
          isTrue);
      reject = true;
      expect(
          await service.uploadBackup(
              serverUrl: url,
              username: 'user',
              password: 'test',
              localFilePath: source.path),
          isFalse);
      expect(lengths, everyElement(bytes.length));
      expect(matched, [true, true, true]);
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

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
