import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

import 'package:hgame_manager/core/services/webdav_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final gzipContent in [false, true]) {
    for (final interrupted in [false, true]) {
      final encoding = gzipContent ? 'gzip' : '普通';
      testWidgets(
          interrupted ? '中断 $encoding 下载保留已有备份' : '完整 $encoding 响应可下载为原始备份',
          (tester) async {
        final temporary =
            await Directory.systemTemp.createTemp('hgm_webdav_gzip_');
        final destination = File(path.join(temporary.path, 'backup.zip'));
        final original = List<int>.generate(1024, (index) => index % 256);
        final compressed = gzipContent ? gzip.encode(original) : original;
        final previous = [1, 2, 3];
        await destination.writeAsBytes(previous);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          if (gzipContent) {
            request.response.headers
                .set(HttpHeaders.contentEncodingHeader, 'gzip');
          }
          request.response.contentLength = compressed.length;
          if (interrupted) {
            final socket =
                await request.response.detachSocket(writeHeaders: true);
            socket.add(compressed.sublist(0, compressed.length ~/ 2));
            await socket.flush();
            await socket.close();
          } else {
            request.response.add(compressed);
            await request.response.close();
          }
        });
        try {
          final success = await WebdavService().downloadBackup(
            serverUrl: 'http://127.0.0.1:${server.port}',
            username: '',
            password: '',
            remoteFileName: 'backup.zip',
            localPath: destination.path,
          );
          expect(success, !interrupted);
          expect(await destination.readAsBytes(),
              interrupted ? previous : original);
          expect(
              await temporary
                  .list()
                  .where((entry) => entry is Directory)
                  .toList(),
              isEmpty);
        } finally {
          await server.close(force: true);
          await temporary.delete(recursive: true);
        }
      }, skip: !Platform.isWindows);
    }
  }
}
