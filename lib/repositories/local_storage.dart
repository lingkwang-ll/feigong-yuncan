import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储统一入口
///
/// 用一个 SharedPreferences 实例供各 repository 复用。
class LocalStorage {
  LocalStorage._(this._prefs);

  final SharedPreferences _prefs;

  static LocalStorage? _instance;

  static Future<LocalStorage> instance() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    _instance = LocalStorage._(prefs);
    return _instance!;
  }

  String? getString(String key) => _prefs.getString(key);
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);
  Future<bool> remove(String key) => _prefs.remove(key);
  bool containsKey(String key) => _prefs.containsKey(key);
}
