import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/dlsite_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _id = 'RJ01684124';
const _restrictedPage = '''
<h1 id="work_name">测试作品 [测试系列]</h1>
<div class="maker_name"><a href="/maniax/circle/test">测试厂商</a></div>
<section class="p-restricted"><div class="error_message">访问受限</div></section>
<meta property="og:image" content="https://www.dlsite.com/modpub/images/web/home/summary_large_image_ja_jp.png">
<script type="application/ld+json">{
  "@type":"Product","sku":"RJ01684124","name":"测试作品",
  "description":"宣传摘要","image":["https://www.dlsite.com/images/web/home/no_img_main.gif"]
}</script>
''';

http.Response _response(String text, {int status = 200}) => http.Response(
      text,
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _product({String id = _id}) => {
      'workno': id,
      'product_id': id,
      'intro': null,
      'intro_s': '不能代替正文的宣传摘要',
      'image_main': {'url': '//img.dlsite.jp/cover.jpg'},
      'image_samples': [
        {'url': '//img.dlsite.jp/sample.jpg'},
        {'url': '//img.dlsite.jp/sample.jpg'},
        {'url': 'https://www.dlsite.com/images/web/home/no_img_main.gif'},
        {'url': 'javascript:alert(1)'},
        {'url': '//img.dlsite.jp/trailer.mp4'},
      ],
      'work_type_string': '冒险',
      'genres': [
        {'name': '探索'},
        {'name': '探索'},
        {'name': '解谜'},
      ],
    };

void main() {
  test('站点判断仅使用真实主机而不是路径或查询参数', () {
    for (final url in [
      'https://www.dlsite.com/maniax/work/=/product_id/RJ100001.html',
      'https://DLSITE.COM/pro/work/=/product_id/VJ100001.html',
    ]) {
      expect(DlsiteService.isDlsiteUrl(url), isTrue);
    }
    for (final url in [
      'https://example.test/post/RJ100001?from=dlsite',
      'https://example.test/dlsite.com/RJ100001',
      'https://www.dlsite.com.example.test/RJ100001',
      'https://dlsite.com@example.test/RJ100001',
      'RJ100001',
    ]) {
      expect(DlsiteService.isDlsiteUrl(url), isFalse);
    }
  });

  group('DLsite 限定作品获取', () {
    test('同一代理客户端补公开图片和类型，不把摘要当正文', () async {
      final requests = <http.Request>[];
      var clients = 0;
      final service = DlsiteService(clientFactory: () async {
        clients++;
        return MockClient((request) async {
          requests.add(request);
          if (!request.url.path.endsWith('product.json')) {
            return _response(_restrictedPage);
          }
          return _response(jsonEncode([_product()]));
        });
      });

      final info = (await service.fetchById(_id))!;
      expect(clients, 1);
      expect(requests, hasLength(2));
      expect(requests.last.url.path, '/maniax/api/=/product.json');
      expect(requests.last.url.queryParameters,
          {'workno': _id, 'locale': 'zh_CN'});
      expect(info.isDlsiteUserOnly, isTrue);
      expect(info.description, isNull);
      expect(info.descriptionHtml, isNull);
      expect(info.screenshots, [
        'https://img.dlsite.jp/cover.jpg',
        'https://img.dlsite.jp/sample.jpg',
      ]);
      expect(info.tags, containsAll(['测试厂商', '测试系列', '冒险', '探索', '解谜']));
      expect(info.tags.where((tag) => tag == '探索'), hasLength(1));
    });

    test('正常正文只请求作品页，不额外调用 API', () async {
      var requests = 0;
      final service = DlsiteService(
          clientFactory: () async => MockClient((request) async {
                requests++;
                expect(request.url.path, isNot(endsWith('product.json')));
                return _response('''
          <h1 id="work_name">正常作品</h1>
          <div class="c-productContent">完整作品正文</div>
          <div class="main_genre"><a>探索</a></div>
          <div class="work_slider"><img src="//img.dlsite.jp/cover.jpg"></div>
        ''');
              }));
      final info = (await service.fetchById(_id))!;
      expect(requests, 1);
      expect(info.isDlsiteUserOnly, isFalse);
      expect(info.description, contains('完整作品正文'));
      expect(info.screenshots, ['https://img.dlsite.jp/cover.jpg']);
    });

    test('公开接口返回其他作品时不应用残缺候选', () async {
      final service = DlsiteService(
          clientFactory: () async => MockClient((request) async {
                return request.url.path.endsWith('product.json')
                    ? _response(jsonEncode([_product(id: 'RJ99999999')]))
                    : _response(_restrictedPage);
              }));
      expect(await service.fetchById(_id), isNull);
    });

    test('多作品 API 只采用当前作品，不混入推荐作品图片', () async {
      final other = _product(id: 'RJ99999999')
        ..['image_main'] = {'url': '//img.dlsite.jp/other.jpg'};
      final service = DlsiteService(
          clientFactory: () async => MockClient((request) async {
                return request.url.path.endsWith('product.json')
                    ? _response(jsonEncode([other, _product()]))
                    : _response(_restrictedPage);
              }));
      final info = (await service.fetchById(_id))!;
      expect(
          info.screenshots, isNot(contains('https://img.dlsite.jp/other.jpg')));
      expect(info.screenshots.first, 'https://img.dlsite.jp/cover.jpg');
    });

    test('拒绝作品标识冲突和重复匹配结果', () async {
      for (final products in [
        [_product()..['product_id'] = 'RJ99999999'],
        [_product(), _product()],
      ]) {
        final service = DlsiteService(
            clientFactory: () async => MockClient((request) async {
                  return request.url.path.endsWith('product.json')
                      ? _response(jsonEncode(products))
                      : _response(_restrictedPage);
                }));
        expect(await service.fetchById(_id), isNull);
      }
    });

    test('公开接口异常或响应损坏时不返回残缺结果', () async {
      for (final mode in ['network', 'http', 'json', 'shape']) {
        final service = DlsiteService(
            clientFactory: () async => MockClient((request) async {
                  if (!request.url.path.endsWith('product.json')) {
                    return _response(_restrictedPage);
                  }
                  if (mode == 'network') throw http.ClientException('网络不可用');
                  if (mode == 'http') return _response('服务暂不可用', status: 503);
                  if (mode == 'json') return _response('{invalid');
                  return _response(jsonEncode(_product()));
                }));
        expect(await service.fetchById(_id), isNull, reason: mode);
      }
    });

    test('缺少可用主图、类型或标签时不以部分信息覆盖原数据', () async {
      for (final change in <String, dynamic>{
        'image_main': {
          'url': 'https://www.dlsite.com/images/web/home/no_img_main.gif'
        },
        'image_samples': 'invalid',
        'work_type_string': '',
        'genres': <dynamic>[],
      }.entries) {
        final product = _product()..[change.key] = change.value;
        final service = DlsiteService(
            clientFactory: () async => MockClient((request) async {
                  return request.url.path.endsWith('product.json')
                      ? _response(jsonEncode([product]))
                      : _response(_restrictedPage);
                }));
        expect(await service.fetchById(_id), isNull, reason: change.key);
      }
    });

    test('有示例图字段却全部无效时拒绝残缺结果，真实空图集可接受', () async {
      for (final samples in <List<dynamic>>[
        [
          {'url': 'https://www.dlsite.com/images/web/home/no_img.gif'},
        ],
        [],
      ]) {
        final product = _product()..['image_samples'] = samples;
        final service = DlsiteService(
            clientFactory: () async => MockClient((request) async {
                  return request.url.path.endsWith('product.json')
                      ? _response(jsonEncode([product]))
                      : _response(_restrictedPage);
                }));
        final info = await service.fetchById(_id);
        expect(info, samples.isEmpty ? isNotNull : isNull);
      }
    });

    test('VJ 作品公开 API 使用 pro 通道', () async {
      const id = 'VJ01684124';
      final service = DlsiteService(
          clientFactory: () async => MockClient((request) async {
                if (!request.url.path.endsWith('product.json')) {
                  return _response(_restrictedPage.replaceAll(_id, id));
                }
                expect(request.url.path, '/pro/api/=/product.json');
                return _response(jsonEncode([_product(id: id)]));
              }));
      expect(await service.fetchById(id), isNotNull);
    });

    test('无效作品 ID 不创建客户端或发出请求', () async {
      final service = DlsiteService(clientFactory: () async {
        fail('不应创建客户端');
      });
      expect(await service.fetchById('invalid'), isNull);
    });
  });
}
