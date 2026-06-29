import 'dart:convert';

import 'dart:typed_data';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/dish_api.dart';
import '../mock/mock_data.dart';
import '../models/dish_model.dart';
import 'local_storage.dart';

/// 商家自有菜品持久化
///
/// 支持 [DataSourceMode.local] / [DataSourceMode.api] 两种模式。
class DishRepository {
  DishRepository(this._storage, {DishApi? dishApi}) : _api = dishApi;

  final LocalStorage _storage;
  final DishApi? _api;

  static const _keyDishes = 'dish.merchant_own';
  static const _keyCatalogPatch = 'dish.catalog_patch';

  bool get _useApi =>
      AppConfig.dataSourceMode == DataSourceMode.api && _api != null;

  /// 启动时使用：本地缓存恢复（如果没有则用 seed）
  Future<List<Dish>> loadDishes() async {
    final raw = _storage.getString(_keyDishes);
    if (raw == null || raw.isEmpty) {
      // api 模式启动时还没登录商家，先用空列表占位；商家登录后会再 fetch
      final seed =
          _useApi ? <Dish>[] : [...MockData.merchantOwnDishes];
      await _saveLocal(seed);
      return seed;
    }
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Dish.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      final seed =
          _useApi ? <Dish>[] : [...MockData.merchantOwnDishes];
      await _saveLocal(seed);
      return seed;
    }
  }

  /// API 模式：根据 merchantId 拉真实菜品列表（可按餐段过滤）
  Future<List<Dish>?> fetchRemoteDishes(
    String merchantId, {
    MealType? mealType,
  }) async {
    if (!_useApi) return null;
    try {
      final list = await _api!.getMerchantDishes(
        merchantId,
        mealType: mealType,
      );
      // 按餐段过滤为空时回退全量，避免 meal_type 列与 mealTypes 不一致导致 0 条
      if (list.isEmpty && mealType != null) {
        final all = await _api!.getMerchantDishes(merchantId);
        if (all.isNotEmpty) {
          await _saveLocal(all);
          return all;
        }
      }
      await _saveLocal(list);
      return list;
    } on ApiException {
      return null;
    }
  }

  Future<void> saveDishes(List<Dish> dishes) => _saveLocal(dishes);

  Future<Dish> createDish(Dish dish, List<Dish> currentAll) async {
    if (_useApi) {
      try {
        final created = await _api!.createDish(dish);
        currentAll.add(created);
        await _saveLocal(currentAll);
        return created;
      } on ApiException {
        // 降级
      }
    }
    currentAll.add(dish);
    await _saveLocal(currentAll);
    return dish;
  }

  Future<Dish> updateDish(Dish dish, List<Dish> currentAll) async {
    if (_useApi) {
      try {
        final updated = await _api!.updateDish(dish);
        final idx = currentAll.indexWhere((d) => d.id == updated.id);
        if (idx >= 0) currentAll[idx] = updated;
        await _saveLocal(currentAll);
        return updated;
      } on ApiException {
        // 降级
      }
    }
    final idx = currentAll.indexWhere((d) => d.id == dish.id);
    if (idx >= 0) currentAll[idx] = dish;
    await _saveLocal(currentAll);
    return dish;
  }

  Future<void> toggleDishAvailable(
    String dishId,
    bool value,
    List<Dish> currentAll,
  ) async {
    await _patchCatalog(dishId, isAvailable: value);
    if (_useApi) {
      try {
        await _api!.toggleDishAvailable(dishId, value);
      } on ApiException {
        // 降级
      }
    }
    await _saveLocal(currentAll);
  }

  Future<void> toggleDishSoldOut(
    String dishId,
    bool value,
    List<Dish> currentAll,
  ) async {
    await _patchCatalog(dishId, isSoldOut: value);
    if (_useApi) {
      try {
        await _api!.toggleDishSoldOut(dishId, value);
      } on ApiException {
        // 降级
      }
    }
    await _saveLocal(currentAll);
  }

  /// 员工端拉取菜品后应用本地/商家端的上下架与售罄补丁
  List<Dish> applyCatalogPatch(List<Dish> dishes) {
    final patch = _loadCatalogPatch();
    return dishes.map((d) {
      final p = patch[d.id];
      if (p == null) return d;
      return d.copyWith(
        isAvailable: p['isAvailable'] as bool? ?? d.isAvailable,
        isSoldOut: p['isSoldOut'] as bool? ?? d.isSoldOut,
      );
    }).toList();
  }

  Map<String, Map<String, dynamic>> _loadCatalogPatch() {
    final raw = _storage.getString(_keyCatalogPatch);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map(
        (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _patchCatalog(
    String dishId, {
    bool? isAvailable,
    bool? isSoldOut,
  }) async {
    final patch = _loadCatalogPatch();
    final current = Map<String, dynamic>.from(patch[dishId] ?? {});
    if (isAvailable != null) current['isAvailable'] = isAvailable;
    if (isSoldOut != null) current['isSoldOut'] = isSoldOut;
    patch[dishId] = current;
    await _storage.setString(_keyCatalogPatch, jsonEncode(patch));
  }

  Future<void> _saveLocal(List<Dish> dishes) async {
    final list = dishes.map((d) => d.toJson()).toList();
    await _storage.setString(_keyDishes, jsonEncode(list));
  }

  /// 菜品图上传：优先真实字节，否则占位路径
  Future<String> uploadDishImage(String localPathOrBase64) async {
    if (_useApi) {
      try {
        return await _api!.uploadDishImage(localPathOrBase64);
      } on ApiException {
        // 降级到本地占位
      }
    }
    return localPathOrBase64;
  }

  Future<String?> uploadDishImageBytes(Uint8List bytes, String filename) async {
    if (!_useApi || _api == null) return null;
    try {
      return await _api!.uploadDishImageBytes(bytes, filename);
    } on ApiException {
      return null;
    }
  }
}
