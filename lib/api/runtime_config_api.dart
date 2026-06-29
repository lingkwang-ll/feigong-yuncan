import '../models/payment_config.dart';
import 'api_client.dart';

class AppRuntimeSettings {
  final bool enableReview;
  final bool allowCancelOrder;
  final bool requirePaymentScreenshot;
  final bool showSoldOutDishes;

  const AppRuntimeSettings({
    this.enableReview = true,
    this.allowCancelOrder = true,
    this.requirePaymentScreenshot = true,
    this.showSoldOutDishes = true,
  });

  factory AppRuntimeSettings.fromJson(Map<String, dynamic> json) =>
      AppRuntimeSettings(
        enableReview: json['enableReview'] != false,
        allowCancelOrder: json['allowCancelOrder'] != false,
        requirePaymentScreenshot: json['requirePaymentScreenshot'] != false,
        showSoldOutDishes: json['showSoldOutDishes'] != false,
      );
}

class RuntimeConfigApi {
  RuntimeConfigApi(this._client);
  final ApiClient _client;

  Future<PaymentConfig> fetchPaymentConfig() async {
    try {
      final data = await _client.get('/payments/config');
      return PaymentConfig.fromJson((data as Map).cast<String, dynamic>());
    } catch (_) {
      return PaymentConfig.defaults;
    }
  }

  Future<AppRuntimeSettings> fetchAppSettings() async {
    try {
      final data = await _client.get('/config/runtime');
      final map = (data as Map).cast<String, dynamic>();
      final app = (map['appSettings'] as Map?)?.cast<String, dynamic>() ?? {};
      return AppRuntimeSettings.fromJson(app);
    } catch (_) {
      return const AppRuntimeSettings();
    }
  }
}
