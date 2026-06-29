/// 单道菜品评价
class DishReview {
  final String id;
  final String orderId;
  final String dishId;
  final String dishName;
  final String merchantId;
  final String userId;
  final int rating;
  final String comment;
  final DateTime createdAt;

  const DishReview({
    required this.id,
    required this.orderId,
    required this.dishId,
    required this.dishName,
    required this.merchantId,
    required this.userId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderId': orderId,
        'dishId': dishId,
        'dishName': dishName,
        'merchantId': merchantId,
        'userId': userId,
        'rating': rating,
        'comment': comment,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DishReview.fromJson(Map<String, dynamic> json) => DishReview(
        id: json['id'] as String,
        orderId: json['orderId'] as String,
        dishId: json['dishId'] as String,
        dishName: json['dishName'] as String,
        merchantId: json['merchantId'] as String,
        userId: json['userId'] as String,
        rating: (json['rating'] as num).toInt(),
        comment: (json['comment'] as String?) ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// 提交评价时的单菜输入
class DishReviewInput {
  final String dishId;
  final String dishName;
  final int rating;
  final String comment;

  const DishReviewInput({
    required this.dishId,
    required this.dishName,
    required this.rating,
    required this.comment,
  });
}
