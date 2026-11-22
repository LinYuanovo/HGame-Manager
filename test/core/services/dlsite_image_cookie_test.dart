import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/concurrent_image_downloader.dart';
import 'package:hgame_manager/core/services/dlsite_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/proxy_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final direct in [false, true]) {
    test('${direct ? 'DLsite 服务' : '共享刮削'}图片下载实际发送登录凭据', () async {
      final temporary =
          await Directory.systemTemp.createTemp('hgm_dlsite_image_cookie_');
      final settings = await AppSettings.loadFromFileForTest(
          '${temporary.path}/settings.json');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <String, String?>{};
      final destinations = <Uri>[];
      const cookie = 'session=image-session==';
      const imageUrls = [
        'https://img.dlsite.jp/official.jpg',
        'https://media.dlsite.com/sample.jpg',
        'https://external.example/other.jpg',
      ];
      server.listen((request) async {
        received[request.uri.path] =
            request.headers.value(HttpHeaders.cookieHeader);
        request.response.add([1, 2, 3]);
        await request.response.close();
      });
      try {
        await settings.setString('cookie_dlsite', cookie);
        await settings.setString('proxy_mode', 'none');
        closeAllClients();
        final downloaded = await HttpOverrides.runWithHttpOverrides(() async {
          if (direct) {
            return DlsiteService().downloadAllImages(imageUrls, temporary.path);
          }
          return ConcurrentImageDownloader.downloadAll(
            imageUrls: imageUrls,
            saveDir: temporary.path,
            headers: await buildScrapeImageHeaders('https://www.dlsite.com/'),
          );
        }, _LocalImageHttpOverrides(server.port, destinations));

        expect(destinations.map((uri) => uri.toString()),
            unorderedEquals(imageUrls));
        expect(received, {
          '/official.jpg': cookie,
          '/sample.jpg': cookie,
          '/other.jpg': null,
        });
        expect(downloaded, hasLength(3));
        for (final file in downloaded.values) {
          expect(await File(file).readAsBytes(), [1, 2, 3]);
        }
      } finally {
        closeAllClients();
        await server.close(force: true);
        await settings.flush();
        AppSettings.invalidateCache();
        await temporary.delete(recursive: true);
      }
    });
  }
}

/// 保留真实下载和请求头生成，仅将网络目的地映射到本机测试服务器。
class _LocalImageHttpOverrides extends HttpOverrides {
  _LocalImageHttpOverrides(this.port, this.destinations);

  final int port;
  final List<Uri> destinations;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _LocalImageHttpClient(
          super.createHttpClient(context), port, destinations);
}

class _LocalImageHttpClient implements HttpClient {
  _LocalImageHttpClient(this.inner, this.port, this.destinations);

  final HttpClient inner;
  final int port;
  final List<Uri> destinations;

  @override
  set autoUncompress(bool value) => inner.autoUncompress = value;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    destinations.add(url);
    return inner.openUrl(method, Uri.http('127.0.0.1:$port', url.path));
  }

  @override
  void close({bool force = false}) => inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
