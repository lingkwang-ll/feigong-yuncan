import 'package:flutter/foundation.dart';

import '../mock/mock_data.dart';
import '../models/dish_model.dart';
import '../repositories/dish_repository.dart';

/// 商家自有菜品状态
///
/// - 启动时从本地缓存恢复
/// - 商家登录后，可调用 [refreshFor] 从后端拉取最新菜品
class MerchantDishState extends ChangeNotifier {
  MerchantDishState({required DishRepository dishRepository})
      : _repo = dishRepository;

  final DishRepository _repo;

  List<Dish> _dishes = [];
  bool _initialized = false;
  String? _currentMerchantId;

  bool get isInitialized => _initialized;
  String? get currentMerchantId => _currentMerchantId;

  List<Dish> get dishes => List.unmodifiable(_dishes);

  List<Dish> byMealType(MealType? type) {
    if (type == null) return dishes;
    return _dishes.where((d) => d.mealType == type).toList();
  }

  int countByMealType(MealType? type) => byMealType(type).length;

  /// 从本地存储加载菜品（若无则使用 Mock 种子菜品）
  Future<void> initialize() async {
    if (_initialized) return;
    _dishes = await _repo.loadDishes();
    _initialized = true;
    notifyListeners();
  }

  /// 从后端拉取指定商家的菜品（api 模式）
  Future<void> refreshFor(String merchantId) async {
    _currentMerchantId = merchantId;
    final remote = await _repo.fetchRemoteDishes(merchantId);
    if (remote != null) {
      _dishes = remote;
      notifyListeners();
    }
  }

  Future<void> toggleAvailable(String dishId, bool value) async {
    final i = _dishes.indexWhere((d) => d.id == dishId);
    if (i < 0) return;
    _dishes[i] = _dishes[i].copyWith(isAvailable: value);
    await _repo.toggleDishAvailable(dishId, value, _dishes);
    notifyListeners();
  }

  Future<void> toggleSoldOut(String dishId, bool value) async {
    final i = _dishes.indexWhere((d) => d.id == dishId);
    if (i < 0) return;
    _dishes[i] = _dishes[i].copyWith(isSoldOut: value);
    await _repo.toggleDishSoldOut(dishId, value, _dishes);
    notifyListeners();
  }

  Future<void> updateDish(Dish updated) async {
    final i = _dishes.indexWhere((d) => d.id == updated.id);
    if (i < 0) return;
    _dishes[i] = updated;
    final saved = await _repo.updateDish(updated, _dishes);
    final idx2 = _dishes.indexWhere((d) => d.id == saved.id);
    if (idx2 >= 0) _dishes[idx2] = saved;
    notifyListeners();
  }

  Future<void> addDish({
    required String name,
    required double price,
    required String description,
    required MealType mealType,
    required List<String> tags,
    String image = 'dish',
    DishCategory category = DishCategory.none,
    double extraPrice = 0,
    List<MealType> mealTypes = const [],
  }) async {
    final id = 'mo_${DateTime.now().millisecondsSinceEpoch}';
    final draft = Dish(
      id: id,
      merchantId: _currentMerchantId ?? MockData.currentMerchant.id,
      name: name,
      image: image,
      description: description,
      price: price,
      mealType: mealType,
      tags: tags,
      category: category,
      extraPrice: extraPrice,
      mealTypes: mealTypes,
    );
    final saved = await _repo.createDish(draft, _dishes);
    if (!_dishes.contains(saved)) _dishes.add(saved);
    notifyListeners();
  }

  /// 透传图片上传（字节）
  Future<String?> uploadDishImageBytes(Uint8List bytes, String filename) =>
      _repo.uploadDishImageBytes(bytes, filename);

  Future<String> uploadDishImage(String localPathOrBase64) =>
      _repo.uploadDishImage(localPathOrBase64);
}
