import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'app_settings.dart';
import '../services/app_logger.dart';

class _ClientEntry {
  final http.Client client;
  int refCount;
  Timer? idleTimer;
  bool inUse;

  _ClientEntry(this.client) : refCount = 0, inUse = false;

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
    final match = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(serverOutput);
    if (match != null) {
      final proxy = match.group(1)!.trim();
      AppLogger.instance.info('Proxy', 'System proxy found: $proxy');
      return proxy;
    }
    return null;
  } catch (e) {
    AppLogger.instance.error('Proxy', 'Failed to read system proxy', e);
    return null;
  }
}

Future<http.Client> createProxyClient({String? proxyMode, String? proxyUrl}) async {
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
      AppLogger.instance.warning('Proxy', 'System proxy not set, falling back to environment variables');
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
    final client = await createProxyClient(proxyMode: proxyMode, proxyUrl: proxyUrl);
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
    case 'acgying': return 'acgyyg.ru';
    case 'feixue': return 'feixueacg.org';
    case 'vikacg': return 'vikacg.com';
    case '2dfan': return 'fan2d.top';
    default: return '';
  }
}

Future<String> getCookieForSite(String url) async {
  final prefs = await AppSettings.load();
  final uri = Uri.tryParse(url);
  if (uri == null) return '';
  final host = uri.host.toLowerCase();

  final jsonStr = prefs.getString('xpath_parsers');
  if (jsonStr != null && jsonStr.isNotEmpty) {
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final domain = (item['domain'] as String? ?? '').toLowerCase();
        final cookie = item['cookie'] as String? ?? '';
        if (domain.isNotEmpty && cookie.isNotEmpty && host.contains(domain)) {
          return cookie;
        }
      }
    } catch (e) {
      debugPrint('[Proxy] 解析Cookie配置失败: $e');
    }
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

  if (host.contains('acgyyg') || host.contains('acgying')) {
    return prefs.getString('cookie_acgying') ?? '';
  } else if (host.contains('feixueacg') || host.contains('feixue')) {
    return prefs.getString('cookie_feixue') ?? '';
  } else if (host.contains('vikacg') || host.contains('weika')) {
    return prefs.getString('cookie_vikacg') ?? '';
  }
  return '';
}

Future<Map<String, String>> buildScrapeHeaders(String url) async {
  final cookie = await getCookieForSite(url);
  final uri = Uri.tryParse(url);
  final origin = uri != null ? '${uri.scheme}://${uri.host}' : '';
  final headers = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
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
    final isVikacg = host.contains('vikacg') || host.contains('weika') ||
        (domainVikacg.isNotEmpty && host.contains(domainVikacg.toLowerCase()));
    if (isVikacg) {
      headers['Authorization'] = cookie;
    } else {
      headers['Cookie'] = cookie;
    }
  }
  return headers;
}

Future<bool> testProxyConnection(String testUrl) async {
  final client = await createProxyClientFromPrefs();
  try {
    AppLogger.instance.info('Proxy', 'Testing connection to: $testUrl');
    final response = await client.get(
      Uri.parse(testUrl),
      headers: {'User-Agent': 'HGame-Manager/1.0'},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      AppLogger.instance.info('Proxy', 'Connection test SUCCESS (${response.statusCode}) for: $testUrl');
    } else {
      AppLogger.instance.warning('Proxy', 'Connection test returned ${response.statusCode} for: $testUrl');
    }
    return response.statusCode == 200;
  } catch (e) {
    AppLogger.instance.error('Proxy', 'Connection test FAILED for: $testUrl', e);
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
      final response = await httpClient.get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 429) {
        if (attempt < maxRetries) {
          final delay = baseDelaySeconds * (attempt + 1);
          AppLogger.instance.warning('HTTP', '429 限流，$delay秒后重试 (${attempt + 1}/$maxRetries): $url');
          await Future.delayed(Duration(seconds: delay));
          continue;
        }
      }

      return response;
    }
    return await httpClient.get(url, headers: headers)
        .timeout(const Duration(seconds: 30));
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}
