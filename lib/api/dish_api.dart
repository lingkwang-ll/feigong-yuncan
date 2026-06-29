import 'dart:typed_data';

import '../models/dish_model.dart';
import 'api_client.dart';

/// 菜品 API（与 `server/` 后端对齐）
class DishApi {
  DishApi(this._client);

  final ApiClient _client;

  /// GET /api/merchants/:merchantId/dishes?mealType=lunch
  Future<List<Dish>> getMerchantDishes(
    String merchantId, {
    MealType? mealType,
  }) async {
    final data = await _client.get(
      '/merchants/$merchantId/dishes',
      query: {
        if (mealType != null) 'mealType': mealType.name,
      },
    );
    final list = (data as List? ?? const []);
    return list
        .map((e) => Dish.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /api/dishes
  Future<Dish> createDish(Dish dish) async {
    final data = await _client.post(
      '/dishes',
      body: {
        'merchantId': dish.merchantId,
        'name': dish.name,
        'image': dish.image,
        'description': dish.description,
        'price': dish.price,
        'mealType': dish.mealType.name,
        'tags': dish.tags,
        'isAvailable': dish.isAvailable,
        'isSoldOut': dish.isSoldOut,
        if (dish.category != DishCategory.none) 'category': dish.category.apiValue,
        if (dish.category == DishCategory.extra) 'extraPrice': dish.extraPrice,
        if (dish.mealTypes.isNotEmpty)
          'mealTypes': dish.mealTypes.map((m) => m.name).toList(),
      },
    );
    return Dish.fromJson((data as Map).cast<String, dynamic>());
  }

  /// PUT /api/dishes/:dishId
  Future<Dish> updateDish(Dish dish) async {
    final data = await _client.put(
      '/dishes/${dish.id}',
      body: {
        'name': dish.name,
        'image': dish.image,
        'description': dish.description,
        'price': dish.price,
        'mealType': dish.mealType.name,
        'tags': dish.tags,
        'isAvailable': dish.isAvailable,
        'isSoldOut': dish.isSoldOut,
        if (dish.category != DishCategory.none) 'category': dish.category.apiValue,
        'extraPrice': dish.extraPrice,
        'mealTypes': dish.mealTypes.map((m) => m.name).toList(),
      },
    );
    return Dish.fromJson((data as Map).cast<String, dynamic>());
  }

  /// PUT /api/dishes/:dishId/available
  Future<void> toggleDishAvailable(String dishId, bool isAvailable) async {
    await _client.put(
      '/dishes/$dishId/available',
      body: {'isAvailable': isAvailable},
    );
  }

  /// PUT /api/dishes/:dishId/sold-out
  Future<void> toggleDishSoldOut(String dishId, bool isSoldOut) async {
    await _client.put(
      '/dishes/$dishId/sold-out',
      body: {'isSoldOut': isSoldOut},
    );
  }

  /// POST /api/uploads/dish-image
  Future<String> uploadDishImage(String filePathOrBase64) async {
    final data = await _client.uploadFile(
      '/uploads/dish-image',
      fieldName: 'file',
      filePathOrBase64: filePathOrBase64,
      filename: 'dish.png',
    );
    return (data as Map)['url'].toString();
  }

  Future<String> uploadDishImageBytes(Uint8List bytes, String filename) async {
    final data = await _client.uploadBytes(
      '/uploads/dish-image',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return (data as Map)['url'].toString();
  }
}
