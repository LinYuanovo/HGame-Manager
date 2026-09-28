import 'package:package_info_plus/package_info_plus.dart';

/// 应用版本号，启动时由 [initAppVersion] 从 pubspec.yaml 注入的包信息读取。
/// 唯一版本来源是 pubspec.yaml 的 version 字段，禁止在此手动硬编码版本号。
String appVersion = '0.0.0';

Future<void> initAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    appVersion = info.version;
  } catch (_) {
    // 读取失败（如单元测试环境无插件）时保留默认值
  }
}
