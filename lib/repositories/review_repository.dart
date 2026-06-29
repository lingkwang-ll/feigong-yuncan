import 'dart:convert';

import '../models/dish_review_model.dart';
import 'local_storage.dart';

/// 菜品评价本地持久化（SharedPreferences）
///
/// 后续可扩展为 API 模式，与 [OrderRepository] 结构类似。
class ReviewRepository {
  ReviewRepository(this._storage);

  final LocalStorage _storage;
  static const _keyReviews = 'review.dish_list';

  Future<List<DishReview>> loadReviews() async {
    final raw = _storage.getString(_keyReviews);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => DishReview.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveReviews(List<DishReview> reviews) async {
    final encoded = jsonEncode(reviews.map((e) => e.toJson()).toList());
    await _storage.setString(_keyReviews, encoded);
  }
}
