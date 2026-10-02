import 'package:flutter/foundation.dart' show visibleForTesting;
import 'app_settings.dart';

/// 论坛自定义域名工具。
///
/// 当用户为某个论坛配置了自定义域名时，游戏中保存的旧域名来源链接
/// （与该论坛同源的域名）在访问/刮削时自动重写为自定义域名。
///
/// 匹配策略相对宽松但有限制：只比较 URL 主域名（host 最后两段）的首标签
/// 是否等于或包含论坛品牌关键词。例如品牌 `acgyyg` 可匹配
/// acgyyg.ru / acgyyg.cc / acgyyg.me 等历史或未来域名；
/// 而 acgyyg.evil.com（主域名为 evil.com）不会匹配。
class ForumDomainUtils {
  /// 各论坛站点的品牌关键词（用于识别同站的其他域名）
  static const Map<String, List<String>> siteBrandKeys = {
    'acgying': ['acgyyg', 'acgying'],
    'feixue': ['feixueacg', 'feixue'],
    'vikacg': ['vikacg', 'weika'],
    '2dfan': ['fan2d', '2dfan'],
  };

  static const Map<String, String> _settingsKeyBySite = {
    'acgying': 'domain_acgying',
    'feixue': 'domain_feixue',
    'vikacg': 'domain_vikacg',
    '2dfan': 'domain_2dfan',
  };

  /// 读取设置并尝试重写 [url]；无匹配或无需重写时原样返回。永不抛异常。
  static Future<String> resolveWithCustomDomain(String url) async {
    try {
      final prefs = await AppSettings.load();
      final customDomains = <String, String>{};
      for (final entry in _settingsKeyBySite.entries) {
        final domain = normalizeDomain(prefs.getString(entry.value) ?? '');
        if (domain.isNotEmpty) customDomains[entry.key] = domain;
      }
      return rewriteWithCustomDomain(url, customDomains) ?? url;
    } catch (_) {
      return url;
    }
  }

  /// 纯函数：若 [url] 的 host 属于某个已配置自定义域名的论坛
  /// （同品牌宽松匹配，仅限主域名首标签），返回替换 host 后的新 URL；
  /// 已是自定义域名或不匹配任何论坛时返回 null。
  @visibleForTesting
  static String? rewriteWithCustomDomain(
      String url, Map<String, String> customDomains) {
    if (customDomains.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final host = uri.host.toLowerCase();
    for (final entry in customDomains.entries) {
      final customDomain = normalizeDomain(entry.value);
      if (customDomain.isEmpty) continue;
      // 已是自定义域名（或其子域名），无需重写
      if (host == customDomain || host.endsWith('.$customDomain')) {
        return null;
      }
      final brands = siteBrandKeys[entry.key];
      if (brands == null) continue;
      if (hostMatchesBrand(host, brands)) {
        return uri.replace(host: customDomain).toString();
      }
    }
    return null;
  }

  /// 宽松但有限制的同站判断：取 host 主域名（最后两段）的首标签，
  /// 该标签等于或包含任一品牌关键词即视为同站。
  /// 例如 acgyyg.ru / acgyyg.cc / acgyyg2.me 均匹配品牌 acgyyg；
  /// 而 acgyyg.evil.com（主域名为 evil.com）不匹配。
  @visibleForTesting
  static bool hostMatchesBrand(String host, List<String> brands) {
    final labels =
        host.toLowerCase().split('.').where((l) => l.isNotEmpty).toList();
    if (labels.isEmpty) return false;
    final rootFirstLabel =
        labels.length >= 2 ? labels[labels.length - 2] : labels.first;
    for (final brand in brands) {
      if (rootFirstLabel == brand || rootFirstLabel.contains(brand)) {
        return true;
      }
    }
    return false;
  }

  @visibleForTesting
  static String normalizeDomain(String domain) {
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
}
