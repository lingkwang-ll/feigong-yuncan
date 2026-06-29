/// 商家订单评价（与后端 ReviewDto 对齐）
class MerchantReview {
  final String id;
  final String orderId;
  final String merchantId;
  final String userId;
  final int rating;
  final int hygieneRating;
  final String content;
  final List<String> images;
  final bool isAnonymous;
  final String displayUserName;
  final String departmentName;
  final String orderNo;
  final DateTime createdAt;

  const MerchantReview({
    required this.id,
    required this.orderId,
    required this.merchantId,
    required this.userId,
    required this.rating,
    this.hygieneRating = 0,
    required this.content,
    required this.images,
    this.isAnonymous = false,
    this.displayUserName = '',
    this.departmentName = '',
    this.orderNo = '',
    required this.createdAt,
  });

  factory MerchantReview.fromJson(Map<String, dynamic> json) => MerchantReview(
        id: (json['id'] as String?) ?? '',
        orderId: (json['orderId'] as String?) ?? '',
        merchantId: (json['merchantId'] as String?) ?? '',
        userId: (json['userId'] as String?) ?? '',
        rating: ((json['rating'] as num?) ?? json['overallRating'] ?? 0)
            .toInt(),
        hygieneRating: ((json['hygieneRating'] as num?) ?? 0).toInt(),
        content: (json['content'] as String?) ?? '',
        images: ((json['images'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        isAnonymous: json['isAnonymous'] == true,
        displayUserName: (json['displayUserName'] as String?) ?? '',
        departmentName: (json['departmentName'] as String?) ?? '',
        orderNo: (json['orderNo'] as String?) ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  String get userLine {
    if (isAnonymous) return '匿名用户';
    if (departmentName.isNotEmpty) {
      return '$displayUserName｜$departmentName';
    }
    return displayUserName.isNotEmpty ? displayUserName : '员工';
  }
}

class MerchantReviewsPage {
  final MerchantHygieneStatsSummary stats;
  final List<MerchantReview> reviews;

  const MerchantReviewsPage({
    required this.stats,
    required this.reviews,
  });

  factory MerchantReviewsPage.fromJson(Map<String, dynamic> json) {
    final statsRaw = (json['stats'] as Map?)?.cast<String, dynamic>() ?? {};
    final list = (json['reviews'] as List? ?? const []);
    return MerchantReviewsPage(
      stats: MerchantHygieneStatsSummary.fromJson(statsRaw),
      reviews: list
          .map((e) =>
              MerchantReview.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class MerchantHygieneStatsSummary {
  final String hygieneGrade;
  final double? hygieneScore;
  final int reviewCount;
  final double? overallRating;
  final String gradeLabel;

  const MerchantHygieneStatsSummary({
    required this.hygieneGrade,
    this.hygieneScore,
    required this.reviewCount,
    this.overallRating,
    required this.gradeLabel,
  });

  factory MerchantHygieneStatsSummary.fromJson(Map<String, dynamic> json) =>
      MerchantHygieneStatsSummary(
        hygieneGrade: (json['hygieneGrade'] as String?) ?? '—',
        hygieneScore: (json['hygieneScore'] as num?)?.toDouble(),
        reviewCount: ((json['reviewCount'] as num?) ?? 0).toInt(),
        overallRating: (json['overallRating'] as num?)?.toDouble(),
        gradeLabel: (json['gradeLabel'] as String?) ?? '暂无足够评价',
      );

  bool get hasEnoughReviews => reviewCount >= 5;
}
