import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'app_settings.dart';
import '../services/app_logger.dart';

String? readWindowsSystemProxy() {
  try {
    final result = Process.runSync(
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

    final serverResult = Process.runSync(
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

http.Client createProxyClient({String? proxyMode, String? proxyUrl}) {
  final mode = proxyMode ?? 'none';

  if (mode == 'none') {
    AppLogger.instance.info('Proxy', 'No proxy configured');
    return http.Client();
  }

  final httpClient = HttpClient();

  if (mode == 'system') {
    final systemProxy = readWindowsSystemProxy();
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

Future<http.Client> createProxyClientFromPrefs() async {
  final prefs = await AppSettings.load();
  final proxyMode = prefs.getString('proxy_mode') ?? 'none';
  final proxyUrl = prefs.getString('proxy_url') ?? '';
  return createProxyClient(proxyMode: proxyMode, proxyUrl: proxyUrl);
}

/// Get cookie string for a specific site from preferences
Future<String> getCookieForSite(String url) async {
  final prefs = await AppSettings.load();
  final uri = Uri.tryParse(url);
  if (uri == null) return '';

  final host = uri.host.toLowerCase();
  if (host.contains('acgyyg') || host.contains('acgying')) {
    return prefs.getString('cookie_acgying') ?? '';
  } else if (host.contains('feixueacg') || host.contains('feixue')) {
    return prefs.getString('cookie_feixue') ?? '';
  } else if (host.contains('vikacg') || host.contains('weika')) {
    return prefs.getString('cookie_vikacg') ?? '';
  }
  return '';
}

/// Build request headers with User-Agent and site-specific authentication.
/// VikACG/weika uses Authorization header; other sites use Cookie.
Future<Map<String, String>> buildScrapeHeaders(String url) async {
  final cookie = await getCookieForSite(url);
  final headers = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };
  if (cookie.isNotEmpty) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (host.contains('vikacg') || host.contains('weika')) {
      headers['Authorization'] = cookie;
    } else {
      headers['Cookie'] = cookie;
    }
  }
  return headers;
}

Future<bool> testProxyConnection(String testUrl) async {
  try {
    AppLogger.instance.info('Proxy', 'Testing connection to: $testUrl');
    final client = await createProxyClientFromPrefs();
    final response = await client.get(
      Uri.parse(testUrl),
      headers: {'User-Agent': 'HGame-Manager/1.0'},
    ).timeout(const Duration(seconds: 10));
    client.close();

    if (response.statusCode == 200) {
      AppLogger.instance.info('Proxy', 'Connection test SUCCESS (${response.statusCode}) for: $testUrl');
    } else {
      AppLogger.instance.warning('Proxy', 'Connection test returned ${response.statusCode} for: $testUrl');
    }
    return response.statusCode == 200;
  } catch (e) {
    AppLogger.instance.error('Proxy', 'Connection test FAILED for: $testUrl', e);
    return false;
  }
}
