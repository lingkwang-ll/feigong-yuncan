/// 数据源模式
///
/// - [local]：使用 SharedPreferences 本地存储
/// - [api]：通过 ApiClient 调用真实后端（第十步起默认）
///
/// 切换方式：修改 [AppConfig.dataSourceMode] 即可。
/// `local` 分支保留不删除，方便没有后端时仍能跑通。
enum DataSourceMode {
  local,
  api,
}

/// 编译环境：dev | prod（`--dart-define=ENV=prod`）
const String appEnv = String.fromEnvironment('ENV', defaultValue: 'dev');

/// 后端 API 根地址
///
/// 默认指向本地后端 `server/`。
/// - Web / iOS 模拟器 / Windows 桌面：`http://localhost:3000/api`
/// - Android 模拟器：`http://10.0.2.2:3000/api`
///
/// 部署到测试 / 生产环境时，用 `--dart-define` 覆盖：
/// ```bash
/// # 开发跑 Web 端
/// flutter run -d chrome \
///   --dart-define=API_BASE_URL=http://192.168.0.10:3000/api
///
/// # 构建生产 Web 包
/// flutter build web \
///   --dart-define=API_BASE_URL=http://118.31.188.176:3000/api
/// ```
///
/// 注意：仅在编译时生效；运行时再改环境变量不会反映到 const 上。
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
);

/// 静态资源根地址（去掉 `/api` 后缀）
///
/// 用于把后端返回的相对路径 `/uploads/xxx.png`
/// 拼接成可被 `Image.network` 访问的完整 URL。
String get assetBaseUrl {
  const suffix = '/api';
  if (apiBaseUrl.endsWith(suffix)) {
    return apiBaseUrl.substring(0, apiBaseUrl.length - suffix.length);
  }
  return apiBaseUrl;
}

/// 全局应用配置
///
/// 通过这里集中切换"本地 / API"两种数据源。
class AppConfig {
  /// 当前数据源模式
  ///
  /// 第十步起默认为 [DataSourceMode.api]。
  /// 没有后端时改回 [DataSourceMode.local] 即可纯本地运行。
  static const DataSourceMode dataSourceMode = DataSourceMode.api;

  /// 请求超时时间（毫秒）
  static const int requestTimeoutMs = 15000;

  /// 是否开启 API 调用日志（生产环境 ENV=prod 时关闭）
  static const bool enableApiLog = appEnv != 'prod';

  /// 是否为生产编译
  static const bool isProduction = appEnv == 'prod';
}

/// 把后端返回的图片路径转成可访问的完整 URL
///
/// - `null` / 空 / `'qr'` / `'logo'` / `'dish'` / `'cover'` 等占位标识：原样返回
/// - 以 `http(s)://` 开头：直接返回
/// - 以 `/` 开头：拼接 [assetBaseUrl]
/// - 其他（如 `local://...`、本地路径、base64）：原样返回，
///   由调用方决定怎么显示
String? resolveAssetUrl(String? raw) {
  if (raw == null || raw.isEmpty) return raw;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  if (raw.startsWith('/')) return '$assetBaseUrl$raw';
  return raw;
}
