import 'package:shared_preferences/shared_preferences.dart';

/// 提示音开关（本地缓存，默认开启；关闭后仍保留未读红点）
class NotificationSettings {
  NotificationSettings._();

  static bool merchantNewOrderSoundEnabled = true;
  static bool merchantMessageSoundEnabled = true;
  static bool employeeMessageSoundEnabled = true;

  static bool _loaded = false;

  static const _kMerchantNewOrder = 'merchantNewOrderSoundEnabled';
  static const _kMerchantMessage = 'merchantMessageSoundEnabled';
  static const _kEmployeeMessage = 'employeeMessageSoundEnabled';

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    merchantNewOrderSoundEnabled =
        prefs.getBool(_kMerchantNewOrder) ?? true;
    merchantMessageSoundEnabled =
        prefs.getBool(_kMerchantMessage) ?? true;
    employeeMessageSoundEnabled =
        prefs.getBool(_kEmployeeMessage) ?? true;
    _loaded = true;
  }

  static Future<void> setMerchantNewOrderSound(bool value) async {
    merchantNewOrderSoundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMerchantNewOrder, value);
  }

  static Future<void> setMerchantMessageSound(bool value) async {
    merchantMessageSoundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMerchantMessage, value);
  }

  static Future<void> setEmployeeMessageSound(bool value) async {
    employeeMessageSoundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEmployeeMessage, value);
  }
}
