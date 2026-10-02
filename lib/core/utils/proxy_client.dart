import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'app_settings.dart';
import '../services/app_logger.dart';

class _ClientEntry {
  final http.Client client;
  int refCount;
  Timer? idleTimer;
  bool inUse;

  _ClientEntry(this.client)
      : refCount = 0,
        inUse = false;

  void cancelIdleTimer() {
    idleTimer?.cancel();
    idleTimer = null;
  }
}

class _DomainPool {
  final List<_ClientEntry> connections = [];
  int nextIndex = 0;
  static const int maxSize = 3;
}

final Map<String, _DomainPool> _clientPool = {};
String _proxyConfigKey = '';
const String defaultScrapeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36';

Future<void> _updatePoolProxyConfig() async {
  final prefs = await AppSettings.load();
  final proxyMode = prefs.getString('proxy_mode') ?? 'none';
  final proxyUrl = prefs.getString('proxy_url') ?? '';
  final newKey = '$proxyMode:$proxyUrl';
  if (newKey != _proxyConfigKey) {
    _proxyConfigKey = newKey;
    for (final pool in _clientPool.values) {
      for (final entry in pool.connections) {
        entry.cancelIdleTimer();
        entry.client.close();
      }
    }
    _clientPool.clear();
  }
}

/// 把注册表 ProxyServer 原始值规范化为 dart:io 可用的 host:port。
/// 兼容分协议格式（http=h:p;https=h:p，https 优先）；仅含其他协议时返回 null。
@visibleForTesting
String? normalizeSystemProxyServer(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (!value.contains('=')) return value;
  String? httpEntry;
  for (final part in value.split(';')) {
    final kv = part.split('=');
    if (kv.length != 2) continue;
    final scheme = kv[0].trim().toLowerCase();
    final addr = kv[1].trim();
    if (addr.isEmpty) continue;
    if (scheme == 'https') return addr;
    if (scheme == 'http') httpEntry = addr;
  }
  return httpEntry;
}

Future<String?> readWindowsSystemProxy() async {
  try {
    final result = await Process.run(
      'reg',
      [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
      ],
      runInShell: true,
    );
    final output = result.stdout.toString();
    if (!output.contains('0x1')) {
      AppLogger.instance.info('Proxy', 'System proxy is disabled');
      return null;
    }

    final serverResult = await Process.run(
      'reg',
      [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
      ],
      runInShell: true,
    );
    final serverOutput = serverResult.stdout.toString();
    final match =
        RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(serverOutput);
    if (match != null) {
      final proxy = normalizeSystemProxyServer(match.group(1)!);
      if (proxy != null) {
        AppLogger.instance.info('Proxy', 'System proxy found: $proxy');
      }
      return proxy;
    }
    return null;
  } catch (e) {
    AppLogger.instance.error('Proxy', 'Failed to read system proxy', e);
    return null;
  }
}

Future<http.Client> createProxyClient(
    {String? proxyMode, String? proxyUrl}) async {
  final mode = proxyMode ?? 'none';

  if (mode == 'none') {
    AppLogger.instance.info('Proxy', 'No proxy configured');
    final httpClient = HttpClient()..autoUncompress = true;
    return IOClient(httpClient);
  }

  final httpClient = HttpClient()..autoUncompress = true;

  if (mode == 'system') {
    final systemProxy = await readWindowsSystemProxy();
    if (systemProxy != null) {
      httpClient.findProxy = (uri) => 'PROXY $systemProxy';
      AppLogger.instance.info('Proxy', 'Using system proxy: $systemProxy');
    } else {
      httpClient.findProxy = HttpClient.findProxyFromEnvironment;
      AppLogger.instance.warning('Proxy',
          'System proxy not set, falling back to environment variables');
    }
  } else if (mode == 'custom' && proxyUrl != null && proxyUrl.isNotEmpty) {
    httpClient.findProxy = (uri) => 'PROXY $proxyUrl';
    AppLogger.instance.info('Proxy', 'Using custom proxy: $proxyUrl');
  }

  httpClient.badCertificateCallback = (cert, host, port) => true;

  return IOClient(httpClient);
}

class _PooledClient extends http.BaseClient {
  final http.Client _inner;
  final String _domain;
  final _ClientEntry _entry;
  bool _closed = false;

  _PooledClient(this._inner, this._domain, this._entry);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_closed) throw StateError('Client has been closed');
    return _inner.send(request);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    releaseClient(domain: _domain, entry: _entry);
  }
}

Future<http.Client> createProxyClientFromPrefs({String? domain}) async {
  await _updatePoolProxyConfig();
  final key = domain ?? '_default';

  var pool = _clientPool[key];
  if (pool == null) {
    pool = _DomainPool();
    _clientPool[key] = pool;
  }

  // 尝试找到一个空闲连接
  _ClientEntry? idleEntry;
  for (final entry in pool.connections) {
    if (!entry.inUse) {
      idleEntry = entry;
      break;
    }
  }

  // 没有空闲连接且池未满 → 创建新连接
  if (idleEntry == null && pool.connections.length < _DomainPool.maxSize) {
    final prefs = await AppSettings.load();
    final proxyMode = prefs.getString('proxy_mode') ?? 'none';
    final proxyUrl = prefs.getString('proxy_url') ?? '';
    final client =
        await createProxyClient(proxyMode: proxyMode, proxyUrl: proxyUrl);
    idleEntry = _ClientEntry(client);
    pool.connections.add(idleEntry);
  }

  // 如果所有连接都在用（池已满）→ round-robin 复用
  if (idleEntry == null) {
    idleEntry = pool.connections[pool.nextIndex];
    pool.nextIndex = (pool.nextIndex + 1) % pool.connections.length;
  }

  idleEntry.cancelIdleTimer();
  idleEntry.refCount++;
  idleEntry.inUse = true;

  return _PooledClient(idleEntry.client, key, idleEntry);
}

void releaseClient({String? domain, _ClientEntry? entry}) {
  final key = domain ?? '_default';
  final pool = _clientPool[key];
  if (pool == null || entry == null) return;

  entry.refCount--;
  if (entry.refCount <= 0) {
    entry.refCount = 0;
    entry.inUse = false;
    entry.cancelIdleTimer();
    entry.idleTimer = Timer(const Duration(seconds: 60), () {
      pool.connections.remove(entry);
      entry.cancelIdleTimer();
      entry.client.close();
      if (pool.connections.isEmpty) {
        _clientPool.remove(key);
      }
    });
  }
}

void closeAllClients() {
  for (final pool in _clientPool.values) {
    for (final entry in pool.connections) {
      entry.cancelIdleTimer();
      entry.client.close();
    }
  }
  _clientPool.clear();
}

Future<String> getEffectiveDomain(String siteKey) async {
  final prefs = await AppSettings.load();
  final customDomain = prefs.getString('domain_$siteKey') ?? '';
  if (customDomain.isNotEmpty) return customDomain;
  switch (siteKey) {
    case 'acgying':
      return 'acgyyg.ru';
    case 'feixue':
      return 'feixueacg.org';
    case 'vikacg':
      return 'vikacg.com';
    case '2dfan':
      return 'fan2d.top';
    default:
      return '';
  }
}

Future<String> getCookieForSite(String url) async {
  final prefs = await AppSettings.load();
  final uri = Uri.tryParse(url);
  if (uri == null) return '';
  final host = uri.host.toLowerCase();

  final customConfig = await getCustomXpathParserConfigForSite(url);
  final customCookie = customConfig?['cookie'] ?? '';
  if (customCookie.isNotEmpty) {
    return customCookie;
  }

  final domainAcgying = prefs.getString('domain_acgying') ?? '';
  final domainFeixue = prefs.getString('domain_feixue') ?? '';
  final domainVikacg = prefs.getString('domain_vikacg') ?? '';

  if (domainAcgying.isNotEmpty && host.contains(domainAcgying.toLowerCase())) {
    return prefs.getString('cookie_acgying') ?? '';
  }
  if (domainFeixue.isNotEmpty && host.contains(domainFeixue.toLowerCase())) {
    return prefs.getString('cookie_feixue') ?? '';
  }
  if (domainVikacg.isNotEmpty && host.contains(domainVikacg.toLowerCase())) {
    return prefs.getString('cookie_vikacg') ?? '';
  }

  final domain2dfan = prefs.getString('domain_2dfan') ?? '';
  if (domain2dfan.isNotEmpty && host.contains(domain2dfan.toLowerCase())) {
    return prefs.getString('cookie_2dfan') ?? '';
  }

  if (host.contains('acgyyg') || host.contains('acgying')) {
    return prefs.getString('cookie_acgying') ?? '';
  } else if (host.contains('feixueacg') || host.contains('feixue')) {
    return prefs.getString('cookie_feixue') ?? '';
  } else if (host.contains('vikacg') || host.contains('weika')) {
    return prefs.getString('cookie_vikacg') ?? '';
  } else if (host.contains('fan2d') || host.contains('2dfan')) {
    return prefs.getString('cookie_2dfan') ?? '';
  }
  return '';
}

Future<Map<String, String>?> getCustomXpathParserConfigForSite(
    String url) async {
  final prefs = await AppSettings.load();
  final jsonStr = prefs.getString('xpath_parsers');
  return customXpathParserConfigFromJson(url, jsonStr);
}

@visibleForTesting
Map<String, String>? customXpathParserConfigFromJson(
    String url, String? jsonStr) {
  if (jsonStr == null || jsonStr.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  try {
    final List<dynamic> list = jsonDecode(jsonStr);
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final domain = _normalizeConfigDomain(item['domain']?.toString() ?? '');
      if (domain.isEmpty || !host.contains(domain)) continue;
      return item.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''));
    }
  } catch (e) {
    debugPrint('[Proxy] 解析自定义解析器配置失败: $e');
  }
  return null;
}

@visibleForTesting
String resolveScrapeUserAgentFromConfig(String url, String? jsonStr) {
  final customConfig = customXpathParserConfigFromJson(url, jsonStr);
  final userAgent = customConfig?['userAgent']?.trim() ?? '';
  return userAgent.isNotEmpty ? userAgent : defaultScrapeUserAgent;
}

Future<String> getUserAgentForSite(String url) async {
  final customConfig = await getCustomXpathParserConfigForSite(url);
  final userAgent = customConfig?['userAgent']?.trim() ?? '';
  return userAgent.isNotEmpty ? userAgent : defaultScrapeUserAgent;
}

String _randomHex(int length) {
  final random = Random.secure();
  final buffer = StringBuffer();
  while (buffer.length < length) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString().substring(0, length);
}

Future<Map<String, String>> _getVikacgClientHeaders() async {
  final prefs = await AppSettings.load();
  var deviceCode = prefs.getString(AppSettings.vikacgDeviceCodeKey) ?? '';
  var clientCode = prefs.getString(AppSettings.vikacgClientCodeKey) ?? '';
  if (deviceCode.isEmpty) {
    deviceCode = _randomHex(32);
    await prefs.setString(AppSettings.vikacgDeviceCodeKey, deviceCode);
  }
  if (clientCode.isEmpty) {
    final hex = _randomHex(32).toUpperCase();
    clientCode = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    await prefs.setString(AppSettings.vikacgClientCodeKey, clientCode);
  }
  return {
    'Architecture': 'AixPot',
    'X-Client-Name': 'VikACG Moonlight',
    'X-Device-Code': deviceCode,
    'X-Client-Code': clientCode,
  };
}

@visibleForTesting
String extractVikacgAuthorization(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  final jwt = RegExp(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+')
      .firstMatch(text)
      ?.group(0);
  if (jwt != null) return 'Bearer $jwt';
  final bearer = RegExp(r'Bearer\s+([^\s;]+)', caseSensitive: false)
      .firstMatch(text)
      ?.group(1);
  return bearer == null ? '' : 'Bearer $bearer';
}

Future<bool> isVikacgUrl(String url) async {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (RegExp(r'(^|\.)vikacg\.(com|cc|xyz|net|org)$').hasMatch(host) ||
      host == 'weika' ||
      host.endsWith('.weika')) return true;
  final prefs = await AppSettings.load();
  final customDomain =
      _normalizeConfigDomain(prefs.getString('domain_vikacg') ?? '');
  return customDomain.isNotEmpty &&
      (host == customDomain || host.endsWith('.$customDomain'));
}

/// 维咔服务端校验 sec-ch-ua 客户端提示头，缺失时返回 400「非法的客户端」。
/// 版本号与 UA 保持一致。
@visibleForTesting
String buildSecChUaForUserAgent(String userAgent) {
  final chrome =
      RegExp(r'Chrome/(\d+)').firstMatch(userAgent)?.group(1) ?? '136';
  final edge = RegExp(r'Edg/(\d+)').firstMatch(userAgent)?.group(1);
  if (edge != null) {
    return '"Microsoft Edge";v="$edge", "Not_A Brand";v="8", '
        '"Chromium";v="$chrome"';
  }
  return '"Google Chrome";v="$chrome", "Not_A Brand";v="8", '
      '"Chromium";v="$chrome"';
}

String _normalizeConfigDomain(String domain) {
  final trimmed = domain.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.host.isNotEmpty) return uri.host.toLowerCase();
  return trimmed
      .replaceFirst(RegExp(r'^https?://'), '')
      .split('/')
      .first
      .trim();
}

Future<Map<String, String>> buildScrapeHeaders(
  String url, {
  String? userAgentOverride,
  String? cookieOverride,
}) async {
  final cookie = cookieOverride ?? await getCookieForSite(url);
  final userAgent = userAgentOverride?.trim().isNotEmpty == true
      ? userAgentOverride!.trim()
      : await getUserAgentForSite(url);
  final uri = Uri.tryParse(url);
  final origin = uri != null ? '${uri.scheme}://${uri.host}' : '';
  final headers = <String, String>{
    'User-Agent': userAgent,
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Connection': 'keep-alive',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-User': '?1',
    'Upgrade-Insecure-Requests': '1',
    if (origin.isNotEmpty) 'Origin': origin,
    if (uri != null) 'Referer': url,
  };
  if (cookie.isNotEmpty) {
    final host = uri?.host.toLowerCase() ?? '';
    final prefs = await AppSettings.load();
    final domainVikacg = prefs.getString('domain_vikacg') ?? '';
    final isVikacg = host.contains('vikacg') ||
        host.contains('weika') ||
        (domainVikacg.isNotEmpty && host.contains(domainVikacg.toLowerCase()));
    if (isVikacg) {
      final authorization = extractVikacgAuthorization(cookie);
      if (authorization.isNotEmpty) {
        headers['Authorization'] = authorization;
      }
    } else {
      headers['Cookie'] = cookie;
    }
  }
  if (await isVikacgUrl(url)) {
    headers.addAll(await _getVikacgClientHeaders());
    headers['sec-ch-ua'] = buildSecChUaForUserAgent(userAgent);
    headers['sec-ch-ua-mobile'] = '?0';
    headers['sec-ch-ua-platform'] = '"Windows"';
  }
  return headers;
}

Future<Map<String, String>> buildScrapeImageHeaders(String sourceUrl) async {
  if (sourceUrl.isEmpty) return {};
  final cookie = await getCookieForSite(sourceUrl);
  final headers = <String, String>{
    'User-Agent': await getUserAgentForSite(sourceUrl),
    'Accept':
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'Referer': sourceUrl,
    if (cookie.isNotEmpty) 'Cookie': cookie,
  };
  return headers;
}

Future<bool> testProxyConnection(String testUrl) async {
  final uri = Uri.tryParse(testUrl);
  final client = await createProxyClientFromPrefs(domain: uri?.host);
  try {
    AppLogger.instance.info('Proxy', 'Testing connection to: $testUrl');
    final response = await client.get(
      Uri.parse(testUrl),
      headers: {'User-Agent': 'HGame-Manager/1.0'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      AppLogger.instance.info('Proxy',
          'Connection test SUCCESS (${response.statusCode}) for: $testUrl');
    } else {
      AppLogger.instance.warning('Proxy',
          'Connection test returned ${response.statusCode} for: $testUrl');
    }
    return response.statusCode == 200;
  } catch (e) {
    AppLogger.instance
        .error('Proxy', 'Connection test FAILED for: $testUrl', e);
    return false;
  } finally {
    client.close();
  }
}

Future<http.Response> httpGetWithRetry(
  Uri url, {
  Map<String, String>? headers,
  int maxRetries = 3,
  int baseDelaySeconds = 5,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      final response = await httpClient
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 429) {
        if (attempt < maxRetries) {
          final delay = baseDelaySeconds * (attempt + 1);
          AppLogger.instance.warning(
              'HTTP', '429 限流，$delay秒后重试 (${attempt + 1}/$maxRetries): $url');
          await Future.delayed(Duration(seconds: delay));
          continue;
        }
      }

      return response;
    }
    return await httpClient
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 30));
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}
