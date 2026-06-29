import 'dish_model.dart';

enum CouponType { fixed, threshold, newcomer }

extension CouponTypeLabel on CouponType {
  String get label {
    switch (this) {
      case CouponType.fixed:
        return '立减券';
      case CouponType.threshold:
        return '满减券';
      case CouponType.newcomer:
        return '新人券';
    }
  }

  static CouponType fromApi(String? raw) {
    switch (raw) {
      case 'threshold':
        return CouponType.threshold;
      case 'newcomer':
        return CouponType.newcomer;
      default:
        return CouponType.fixed;
    }
  }

  String get apiValue {
    switch (this) {
      case CouponType.fixed:
        return 'fixed';
      case CouponType.threshold:
        return 'threshold';
      case CouponType.newcomer:
        return 'newcomer';
    }
  }
}

class CouponTemplate {
  final String id;
  final String merchantId;
  final String name;
  final CouponType couponType;
  final double discountAmount;
  final double minOrderAmount;
  final List<MealType> mealTypes;
  final int totalQuantity;
  final int perUserLimit;
  final int claimedCount;
  final int usedCount;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final int userClaimedCount;
  final bool canClaim;

  const CouponTemplate({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.couponType,
    required this.discountAmount,
    required this.minOrderAmount,
    required this.mealTypes,
    required this.totalQuantity,
    required this.perUserLimit,
    required this.claimedCount,
    required this.usedCount,
    required this.startAt,
    required this.endAt,
    required this.status,
    this.userClaimedCount = 0,
    this.canClaim = false,
  });

  bool get isEnabled => status == 'enabled';

  String get summary {
    switch (couponType) {
      case CouponType.fixed:
        return '无门槛减 ¥${discountAmount.toStringAsFixed(0)}';
      case CouponType.threshold:
        return '满 ¥${minOrderAmount.toStringAsFixed(0)} 减 ¥${discountAmount.toStringAsFixed(0)}';
      case CouponType.newcomer:
        return '新人减 ¥${discountAmount.toStringAsFixed(0)}';
    }
  }

  factory CouponTemplate.fromJson(Map<String, dynamic> json) {
    final mealRaw = (json['mealTypes'] as List?) ?? const [];
    return CouponTemplate(
      id: json['id'] as String,
      merchantId: json['merchantId'] as String,
      name: json['name'] as String,
      couponType: CouponTypeLabel.fromApi(json['couponType'] as String?),
      discountAmount: ((json['discountAmount'] as num?) ?? 0).toDouble(),
      minOrderAmount: ((json['minOrderAmount'] as num?) ?? 0).toDouble(),
      mealTypes: mealRaw
          .map((e) => MealType.values.firstWhere(
                (m) => m.name == e,
                orElse: () => MealType.lunch,
              ))
          .toList(),
      totalQuantity: (json['totalQuantity'] as num?)?.toInt() ?? 0,
      perUserLimit: (json['perUserLimit'] as num?)?.toInt() ?? 1,
      claimedCount: (json['claimedCount'] as num?)?.toInt() ?? 0,
      usedCount: (json['usedCount'] as num?)?.toInt() ?? 0,
      startAt: DateTime.parse(json['startAt'] as String),
      endAt: DateTime.parse(json['endAt'] as String),
      status: (json['status'] as String?) ?? 'enabled',
      userClaimedCount: (json['userClaimedCount'] as num?)?.toInt() ?? 0,
      canClaim: json['canClaim'] == true,
    );
  }
}

class CouponClaim {
  final String id;
  final String templateId;
  final String merchantId;
  final String status;
  final DateTime claimedAt;
  final CouponTemplate? template;

  const CouponClaim({
    required this.id,
    required this.templateId,
    required this.merchantId,
    required this.status,
    required this.claimedAt,
    this.template,
  });

  bool get isUsable => status == 'claimed';

  factory CouponClaim.fromJson(Map<String, dynamic> json) {
    final tpl = json['template'];
    return CouponClaim(
      id: json['id'] as String,
      templateId: json['templateId'] as String,
      merchantId: json['merchantId'] as String,
      status: (json['status'] as String?) ?? 'claimed',
      claimedAt: DateTime.parse(json['claimedAt'] as String),
      template: tpl is Map
          ? CouponTemplate.fromJson(tpl.cast<String, dynamic>())
          : null,
    );
  }
}

class BestCouponResult {
  final CouponClaim claim;
  final double discountAmount;
  final double employeePayBeforeCoupon;
  final double employeePayAmount;

  const BestCouponResult({
    required this.claim,
    required this.discountAmount,
    required this.employeePayBeforeCoupon,
    required this.employeePayAmount,
  });

  factory BestCouponResult.fromJson(Map<String, dynamic> json) {
    return BestCouponResult(
      claim: CouponClaim.fromJson(
        (json['claim'] as Map).cast<String, dynamic>(),
      ),
      discountAmount: ((json['discountAmount'] as num?) ?? 0).toDouble(),
      employeePayBeforeCoupon:
          ((json['employeePayBeforeCoupon'] as num?) ?? 0).toDouble(),
      employeePayAmount: ((json['employeePayAmount'] as num?) ?? 0).toDouble(),
    );
  }
}
