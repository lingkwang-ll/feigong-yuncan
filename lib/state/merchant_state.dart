import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/merchant_model.dart';
import '../repositories/merchant_repository.dart';

/// 商家信息状态
class MerchantState extends ChangeNotifier {
  MerchantState({required MerchantRepository merchantRepository})
      : _repo = merchantRepository;

  final MerchantRepository _repo;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  List<Merchant> _nearby = const [];
  Merchant? _current;

  Future<void> initialize() async {
    if (_initialized) return;
    _current = _repo.currentMerchant();
    _nearby = _repo.nearbyMerchants();
    _initialized = true;
    notifyListeners();
  }

  Merchant get currentMerchant => _current ?? _repo.currentMerchant();

  Future<Merchant?> refreshMerchantProfile(String userId) async {
    final m = await _repo.fetchMerchantProfile(userId);
    if (m != null) {
      _applyCurrent(m);
    }
    return m;
  }

  void _applyCurrent(Merchant m) {
    _current = m;
    _nearby = _nearby
        .map((item) => item.id == m.id ? m : item)
        .toList();
    notifyListeners();
  }

  List<Merchant> get nearbyMerchants => _nearby.isEmpty
      ? _repo.nearbyMerchants()
      : List.unmodifiable(_nearby);

  /// 按商家 ID 取 logo URL；无自定义 logo 时返回空字符串（由 MerchantBadgeLogo 回退 P+）
  String logoForMerchant(String merchantId) {
    if (_current?.id == merchantId && (_current!.logo.isNotEmpty)) {
      return _current!.logo;
    }
    for (final m in nearbyMerchants) {
      if (m.id == merchantId && m.logo.isNotEmpty) return m.logo;
    }
    return '';
  }

  /// 按商家 ID 取展示名（用于订单列表兜底）
  String? merchantNameFor(String merchantId) {
    if (_current?.id == merchantId && _current!.name.isNotEmpty) {
      return _current!.name;
    }
    for (final m in nearbyMerchants) {
      if (m.id == merchantId && m.name.isNotEmpty) return m.name;
    }
    return null;
  }

  Future<List<Merchant>> refreshNearbyMerchants() async {
    final list = await _repo.fetchNearbyMerchants();
    _nearby = list;
    notifyListeners();
    return list;
  }

  Future<void> setMerchantOpen(bool isOpen) async {
    final m = currentMerchant;
    await _repo.saveMerchantIsOpen(m.id, isOpen);
    _applyCurrent(m.copyWith(isOpen: isOpen));
  }

  String get currentQrSeed => _repo.currentPaymentQrSeed();

  Future<bool> changePaymentQrBytes(
    Uint8List bytes,
    String filename, {
    String? channel,
  }) async {
    final url = await _repo.uploadMerchantQrBytes(
      bytes,
      filename,
      merchantId: _current?.id,
      channel: channel,
    );
    if (url == null || url.isEmpty) return false;
    if (_current != null) {
      if (channel == 'wechat') {
        _applyCurrent(_current!.copyWith(wechatPaymentQrUrl: url));
      } else if (channel == 'alipay') {
        _applyCurrent(_current!.copyWith(alipayPaymentQrUrl: url));
      } else {
        _applyCurrent(_current!.copyWith(paymentQrCode: url));
      }
    }
    notifyListeners();
    return true;
  }

  Future<void> changePaymentQr(String seed) async {
    await _repo.uploadMerchantQrCode(seed, merchantId: _current?.id);
    if (_current != null) {
      _applyCurrent(
        _current!.copyWith(paymentQrCode: _repo.currentPaymentQrSeed()),
      );
    } else {
      notifyListeners();
    }
  }

  Future<bool> uploadLogoBytes(Uint8List bytes, String filename) async {
    final url = await _repo.uploadMerchantLogoBytes(
      bytes,
      filename,
      merchantId: _current?.id,
    );
    if (url == null || url.isEmpty) return false;
    final updated = await _repo.updateProfile(
      merchantId: _current!.id,
      logo: url,
    );
    if (updated != null) _applyCurrent(updated);
    return true;
  }

  Future<bool> saveShopProfile({
    required String name,
    required String contactName,
    required String contactPhone,
    required String address,
    required String description,
    String? logo,
  }) async {
    final m = _current ?? currentMerchant;
    final updated = await _repo.updateProfile(
      merchantId: m.id,
      name: name,
      contactName: contactName,
      contactPhone: contactPhone,
      address: address,
      description: description,
      logo: logo,
    );
    if (updated == null) return false;
    _applyCurrent(updated);
    return true;
  }

  Future<bool> saveDeliverySettings({
    required List<String> deliveryModes,
    required double deliveryFee,
    required String deliveryScope,
    required String estimatedDeliveryTime,
  }) async {
    final m = _current ?? currentMerchant;
    final updated = await _repo.updateDeliverySettings(
      merchantId: m.id,
      deliveryModes: deliveryModes,
      deliveryFee: deliveryFee,
      deliveryScope: deliveryScope,
      estimatedDeliveryTime: estimatedDeliveryTime,
    );
    if (updated == null) return false;
    _applyCurrent(updated);
    return true;
  }

  Future<bool> saveBusinessHours({
    required List<String> supportedMealTypes,
    required Map<String, MealHoursSetting> mealOpeningHours,
  }) async {
    final m = _current ?? currentMerchant;
    final updated = await _repo.updateBusinessHours(
      merchantId: m.id,
      supportedMealTypes: supportedMealTypes,
      mealOpeningHours: mealOpeningHours,
    );
    if (updated == null) return false;
    _applyCurrent(updated);
    return true;
  }

  Future<void> clearLocalCache() async {
    await _repo.clearLocalCache();
    _current = _repo.currentMerchant();
    notifyListeners();
  }

  String? paymentScreenshotOf(String orderId) =>
      _repo.getPaymentScreenshot(orderId);

  Future<String> uploadPaymentScreenshot({
    required String orderId,
    required Uint8List imageBytes,
    required String filename,
    String? manualPayChannel,
  }) async {
    final v = await _repo.uploadPaymentScreenshot(
      orderId: orderId,
      imageBytes: imageBytes,
      filename: filename,
      manualPayChannel: manualPayChannel,
    );
    notifyListeners();
    return v;
  }
}
