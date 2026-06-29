// ignore_for_file: use_null_aware_elements

import '../models/dish_model.dart';
import '../models/package_model.dart';
import '../models/package_order_data_model.dart';
import 'api_client.dart';

/// 套餐 API（员工端与商家端共用）
class PackageApi {
  PackageApi(this._client);

  final ApiClient _client;

  /// GET /api/merchants/:merchantId/package-order-data?mealType=lunch
  Future<PackageOrderData> getPackageOrderData(
    String merchantId, {
    required MealType mealType,
  }) async {
    final data = await _client.get(
      '/merchants/$merchantId/package-order-data',
      query: {'mealType': mealType.name},
    );
    return PackageOrderData.fromJson((data as Map).cast<String, dynamic>());
  }

  /// GET /api/merchants/:merchantId/packages?mealType=lunch
  /// 员工端：仅返回该商家、is_enabled=1、可用餐段匹配的套餐
  Future<List<MealPackage>> getMerchantPackages(
    String merchantId, {
    MealType? mealType,
  }) async {
    final data = await _client.get(
      '/merchants/$merchantId/packages',
      query: {
        if (mealType != null) 'mealType': mealType.name,
      },
    );
    final list = (data as List? ?? const []);
    return list
        .map((e) => MealPackage.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 按商家 + 餐段拉套餐列表并定位单个套餐（员工点餐刷新用）。
  Future<MealPackage?> fetchPackageDetail({
    required String merchantId,
    required String packageId,
    required MealType mealType,
  }) async {
    final list = await getMerchantPackages(merchantId, mealType: mealType);
    for (final p in list) {
      if (p.id == packageId) return p;
    }
    return null;
  }

  /// GET /api/packages?merchantId=...（商家维护页：含未启用）
  Future<List<MealPackage>> listOwnPackages({String? merchantId}) async {
    final data = await _client.get(
      '/packages',
      query: {
        if (merchantId != null) 'merchantId': merchantId,
      },
    );
    final list = (data as List? ?? const []);
    return list
        .map((e) => MealPackage.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /api/packages
  Future<MealPackage> createPackage({
    required String merchantId,
    required String name,
    String description = '',
    required double basePrice,
    List<MealType> mealTypes = const [],
    required PackageRules rules,
    bool allowExtra = true,
    List<String> extraDishIds = const [],
    bool isEnabled = true,
  }) async {
    final data = await _client.post(
      '/packages',
      body: {
        'merchantId': merchantId,
        'name': name,
        'description': description,
        'basePrice': basePrice,
        'mealTypes': mealTypes.map((m) => m.name).toList(),
        'rules': rules.toJson(),
        'allowExtra': allowExtra,
        'extraDishIds': extraDishIds,
        'isEnabled': isEnabled,
      },
    );
    return MealPackage.fromJson((data as Map).cast<String, dynamic>());
  }

  /// PUT /api/packages/:id
  Future<MealPackage> updatePackage(
    String packageId, {
    String? name,
    String? description,
    double? basePrice,
    List<MealType>? mealTypes,
    PackageRules? rules,
    bool? allowExtra,
    List<String>? extraDishIds,
    bool? isEnabled,
  }) async {
    final data = await _client.put(
      '/packages/$packageId',
      body: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (basePrice != null) 'basePrice': basePrice,
        if (mealTypes != null) 'mealTypes': mealTypes.map((m) => m.name).toList(),
        if (rules != null) 'rules': rules.toJson(),
        if (allowExtra != null) 'allowExtra': allowExtra,
        if (extraDishIds != null) 'extraDishIds': extraDishIds,
        if (isEnabled != null) 'isEnabled': isEnabled,
      },
    );
    return MealPackage.fromJson((data as Map).cast<String, dynamic>());
  }

  /// PUT /api/packages/:id/enabled
  Future<MealPackage> setEnabled(String packageId, bool isEnabled) async {
    final data = await _client.put(
      '/packages/$packageId/enabled',
      body: {'isEnabled': isEnabled},
    );
    return MealPackage.fromJson((data as Map).cast<String, dynamic>());
  }

  /// DELETE /api/packages/:id
  Future<void> deletePackage(String packageId) async {
    await _client.delete('/packages/$packageId');
  }
}
