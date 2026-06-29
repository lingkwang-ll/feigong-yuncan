import '../api/api_config.dart';

/// 高德地图 Web 配置（编译时注入，不写死 Key）
///
/// ```bash
/// flutter run -d chrome \
///   --dart-define=AMAP_WEB_KEY=your_key \
///   --dart-define=AMAP_SECURITY_CODE=your_code
/// ```
class MapConfig {
  static const String amapWebKey = String.fromEnvironment(
    'AMAP_WEB_KEY',
    defaultValue: '',
  );

  static const String amapSecurityCode = String.fromEnvironment(
    'AMAP_SECURITY_CODE',
    defaultValue: '',
  );

  static const bool enableMapLocation = bool.fromEnvironment(
    'ENABLE_MAP_LOCATION',
    defaultValue: true,
  );

  static bool get isConfigured =>
      amapWebKey.trim().isNotEmpty && enableMapLocation;

  /// dev 可 mock（占位地图 + 手动输入）；prod 必须配置 Key
  static bool get canShowInteractiveMap {
    if (!enableMapLocation) return false;
    if (isConfigured) return true;
    return !AppConfig.isProduction;
  }

  static String get notConfiguredHint => AppConfig.isProduction
      ? '地图服务未配置'
      : '地图服务未配置，可先手动填写地址';
}
