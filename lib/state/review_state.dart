import 'package:flutter/foundation.dart';

import '../models/dish_review_model.dart';
import '../repositories/review_repository.dart';

/// 员工端菜品评价状态（本地 Mock 持久化）
class ReviewState extends ChangeNotifier {
  ReviewState({required ReviewRepository reviewRepository})
      : _repo = reviewRepository;

  final ReviewRepository _repo;

  List<DishReview> _reviews = [];
  bool _initialized = false;

  bool get isInitialized => _initialized;

  List<DishReview> get reviews => List.unmodifiable(_reviews);

  Future<void> initialize() async {
    if (_initialized) return;
    _reviews = await _repo.loadReviews();
    _initialized = true;
    notifyListeners();
  }

  bool isOrderReviewed(String orderId) {
    return _reviews.any((r) => r.orderId == orderId);
  }

  List<DishReview> reviewsForOrder(String orderId) {
    return _reviews.where((r) => r.orderId == orderId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 某道菜的全部历史评价（跨订单）
  List<DishReview> reviewsForDish(String dishId) {
    return _reviews.where((r) => r.dishId == dishId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> submitOrderReviews({
    required String orderId,
    required String merchantId,
    required String userId,
    required List<DishReviewInput> items,
  }) async {
    if (isOrderReviewed(orderId)) return;

    final now = DateTime.now();
    final batch = items.map((item) {
      return DishReview(
        id: 'R${now.millisecondsSinceEpoch}_${item.dishId}',
        orderId: orderId,
        dishId: item.dishId,
        dishName: item.dishName,
        merchantId: merchantId,
        userId: userId,
        rating: item.rating.clamp(1, 5),
        comment: item.comment.trim(),
        createdAt: now,
      );
    }).toList();

    _reviews.addAll(batch);
    await _repo.saveReviews(_reviews);
    notifyListeners();
  }
}
