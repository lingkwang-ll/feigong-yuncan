import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/merchant_api.dart';
import '../api/order_api.dart';
import '../mock/mock_data.dart';
import '../models/merchant_model.dart';
import 'local_storage.dart';

/// 商家信息持久化（含收款码、付款截图）
///
/// 支持 [DataSourceMode.local] / [DataSourceMode.api] 两种模式。
class MerchantRepository {
  MerchantRepository(
    this._storage, {
    MerchantApi? merchantApi,
    OrderApi? orderApi,
  })  : _api = merchantApi,
        _orderApi = orderApi;

  final LocalStorage _storage;
  final MerchantApi? _api;
  final OrderApi? _orderApi;

  static const _keyQrSeed = 'merchant.payment_qr_seed';
  static const _keyPaymentScreenshots = 'merchant.payment_screenshots';
  static const _keyCurrentMerchantId = 'merchant.current_id';
  static const _keyCurrentMerchantJson = 'merchant.current_json';
  static const _keyIsOpenOverrides = 'merchant.is_open_overrides';

  bool get _useApi =>
      AppConfig.dataSourceMode == DataSourceMode.api && _api != null;

  // =========== 当前商家（商家端"我的"页用） ===========

  String? get currentMerchantIdCache =>
      _storage.getString(_keyCurrentMerchantId);

  /// 同步读取当前商家信息
  ///
  /// - 优先返回 api 模式下缓存到本地的真实商家 DTO
  /// - 否则使用 MockData，叠加本地保存的收款码 seed
  Merchant currentMerchant() {
    final raw = _storage.getString(_keyCurrentMerchantJson);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return merchantFromJson(map);
      } catch (_) {
        // 损坏的缓存，落回 Mock
      }
    }
    final m = MockData.currentMerchant;
    final seed = _storage.getString(_keyQrSeed);
    final base = seed == null || seed.isEmpty
        ? m
        : m.copyWith(paymentQrCode: seed);
    return _merchantWithOpenOverride(base);
  }

  /// API 模式：拉取当前登录商家用户对应的商家
  Future<Merchant?> saveCurrentMerchant(Merchant m) async {
    await _storage.setString(_keyCurrentMerchantId, m.id);
    await _storage.setString(_keyCurrentMerchantJson, jsonEncode(merchantToJsonMap(m)));
    await _storage.setString(_keyQrSeed, m.paymentQrCode);
    return _merchantWithOpenOverride(m);
  }

  Future<Merchant?> updateProfile({
    required String merchantId,
    String? name,
    String? logo,
    String? contactName,
    String? contactPhone,
    String? address,
    String? description,
  }) async {
    if (!_useApi) return null;
    try {
      final m = await _api!.updateProfile(
        merchantId: merchantId,
        name: name,
        logo: logo,
        contactName: contactName,
        contactPhone: contactPhone,
        address: address,
        description: description,
      );
      return saveCurrentMerchant(m);
    } on ApiException {
      return null;
    }
  }

  Future<Merchant?> updateDeliverySettings({
    required String merchantId,
    List<String>? deliveryModes,
    double? deliveryFee,
    String? deliveryScope,
    String? estimatedDeliveryTime,
  }) async {
    if (!_useApi) return null;
    try {
      final m = await _api!.updateDeliverySettings(
        merchantId: merchantId,
        deliveryModes: deliveryModes,
        deliveryFee: deliveryFee,
        deliveryScope: deliveryScope,
        estimatedDeliveryTime: estimatedDeliveryTime,
      );
      return saveCurrentMerchant(m);
    } on ApiException {
      return null;
    }
  }

  Future<Merchant?> updateBusinessHours({
    required String merchantId,
    List<String>? supportedMealTypes,
    Map<String, MealHoursSetting>? mealOpeningHours,
  }) async {
    if (!_useApi) return null;
    try {
      final m = await _api!.updateBusinessHours(
        merchantId: merchantId,
        supportedMealTypes: supportedMealTypes,
        mealOpeningHours: mealOpeningHours,
      );
      return saveCurrentMerchant(m);
    } on ApiException {
      return null;
    }
  }

  Future<Merchant?> fetchMerchantProfile(String userId) async {
    if (!_useApi) return null;
    try {
      final m = await _api!.getMerchantProfile(userId: userId);
      await _storage.setString(_keyCurrentMerchantId, m.id);
      await _storage.setString(_keyCurrentMerchantJson, jsonEncode(merchantToJsonMap(m)));
      await _storage.setString(_keyQrSeed, m.paymentQrCode);
      return _merchantWithOpenOverride(m);
    } on ApiException {
      return null;
    }
  }

  Future<void> clearCurrentMerchantCache() async {
    await _storage.remove(_keyCurrentMerchantId);
    await _storage.remove(_keyCurrentMerchantJson);
  }

  // =========== 附近商家（员工首页用） ===========

  /// 同步读取（local 模式 fallback）
  List<Merchant> nearbyMerchants() => MockData.merchants;

  Future<List<Merchant>> fetchNearbyMerchants() async {
    List<Merchant> list;
    if (_useApi) {
      try {
        list = await _api!.getNearbyMerchants();
      } on ApiException {
        list = nearbyMerchants();
      }
    } else {
      list = nearbyMerchants();
    }
    return _applyIsOpenOverrides(list);
  }

  Map<String, bool> _loadIsOpenOverrides() {
    final raw = _storage.getString(_keyIsOpenOverrides);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v == true));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveMerchantIsOpen(String merchantId, bool isOpen) async {
    if (_useApi) {
      try {
        await _api!.updateIsOpen(merchantId: merchantId, isOpen: isOpen);
      } on ApiException {
        // 降级本地
      }
    }
    final map = _loadIsOpenOverrides();
    map[merchantId] = isOpen;
    await _storage.setString(_keyIsOpenOverrides, jsonEncode(map));

    final raw = _storage.getString(_keyCurrentMerchantJson);
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (j['id'] == merchantId) {
          j['isOpen'] = isOpen;
          await _storage.setString(_keyCurrentMerchantJson, jsonEncode(j));
        }
      } catch (_) {}
    }
  }

  List<Merchant> _applyIsOpenOverrides(List<Merchant> list) {
    final overrides = _loadIsOpenOverrides();
    if (overrides.isEmpty) return list;
    return list
        .map((m) => overrides.containsKey(m.id)
            ? m.copyWith(isOpen: overrides[m.id]!)
            : m)
        .toList();
  }

  Merchant _merchantWithOpenOverride(Merchant m) {
    final overrides = _loadIsOpenOverrides();
    if (!overrides.containsKey(m.id)) return m;
    return m.copyWith(isOpen: overrides[m.id]!);
  }

  // =========== 收款码 ===========

  String currentPaymentQrSeed() {
    final seed = _storage.getString(_keyQrSeed);
    if (seed != null && seed.isNotEmpty) return seed;
    return MockData.currentMerchant.paymentQrCode;
  }

  Future<void> saveMerchantQrSeed(String seed) async {
    await _storage.setString(_keyQrSeed, seed);
  }

  /// 收款码图片上传（或更换 seed）
  ///
  /// - local：只把字符串作为 seed 保存
  /// - api：上传到 `/uploads/merchant-qr-code`，并自动绑定到 [merchantId]
  Future<String> uploadMerchantQrCode(
    String localPathOrBase64, {
    String? merchantId,
  }) async {
    String finalSeed = localPathOrBase64;
    final api = _api;
    if (_useApi && api != null) {
      try {
        final url = await api.uploadMerchantQrCode(
          localPathOrBase64,
          merchantId: merchantId,
        );
        finalSeed = url;
      } on ApiException {
        // 降级保存原始 seed
      }
    }
    await saveMerchantQrSeed(finalSeed);
    return finalSeed;
  }

  Future<String?> uploadMerchantQrBytes(
    Uint8List bytes,
    String filename, {
    String? merchantId,
    String? channel,
  }) async {
    if (!_useApi || _api == null) return null;
    try {
      final url = await _api!.uploadMerchantQrCodeBytes(
        bytes,
        filename,
        merchantId: merchantId,
        channel: channel,
      );
      if (channel == null || channel.isEmpty) {
        await saveMerchantQrSeed(url);
      }
      return url;
    } on ApiException {
      return null;
    }
  }

  Future<String?> uploadMerchantLogoBytes(
    Uint8List bytes,
    String filename, {
    String? merchantId,
  }) async {
    if (!_useApi || _api == null) return null;
    try {
      return await _api!.uploadMerchantLogoBytes(
        bytes,
        filename,
        merchantId: merchantId,
      );
    } on ApiException {
      return null;
    }
  }

  // =========== 付款截图 ===========

  Map<String, String> _loadScreenshotMap() {
    final raw = _storage.getString(_keyPaymentScreenshots);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveScreenshotMap(Map<String, String> map) async {
    await _storage.setString(_keyPaymentScreenshots, jsonEncode(map));
  }

  String? getPaymentScreenshot(String orderId) {
    return _loadScreenshotMap()[orderId];
  }

  /// 付款截图上传
  ///
  /// - local：把字符串作为占位写入本地 map
  /// - api：通过 [OrderApi.uploadPaymentScreenshot] 上传，
  ///   并把返回 URL 写回本地 map（后端也会自动更新订单）
  Future<String> uploadPaymentScreenshot({
    required String orderId,
    required Uint8List imageBytes,
    required String filename,
    String? manualPayChannel,
  }) async {
    String finalUrl = '';
    if (_useApi && _orderApi != null) {
      finalUrl = await _orderApi.uploadPaymentScreenshot(
        orderId: orderId,
        imageBytes: imageBytes,
        filename: filename,
        manualPayChannel: manualPayChannel ?? 'wechat',
      );
    }
    if (finalUrl.isNotEmpty) {
      final map = _loadScreenshotMap();
      map[orderId] = finalUrl;
      await _saveScreenshotMap(map);
    }
    return finalUrl;
  }

  Future<void> clearLocalCache() async {
    await _storage.remove(_keyCurrentMerchantJson);
    await _storage.remove(_keyQrSeed);
    await _storage.remove(_keyPaymentScreenshots);
    await _storage.remove(_keyIsOpenOverrides);
  }
}
