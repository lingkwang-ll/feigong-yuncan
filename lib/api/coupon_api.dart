import '../models/coupon_model.dart';
import '../models/dish_model.dart';
import 'api_client.dart';

class CouponApi {
  CouponApi(this._client);

  final ApiClient _client;

  Future<List<CouponTemplate>> listMerchantCoupons() async {
    final data = await _client.get('/merchant/coupons');
    return (data as List? ?? const [])
        .map((e) => CouponTemplate.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<CouponTemplate> createCoupon({
    required String name,
    required CouponType couponType,
    required double discountAmount,
    double minOrderAmount = 0,
    List<MealType> mealTypes = const [
      MealType.breakfast,
      MealType.lunch,
      MealType.dinner,
    ],
    required int totalQuantity,
    int perUserLimit = 1,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    final data = await _client.post(
      '/merchant/coupons',
      body: {
        'name': name,
        'couponType': couponType.apiValue,
        'discountAmount': discountAmount,
        'minOrderAmount': minOrderAmount,
        'mealTypes': mealTypes.map((m) => m.name).toList(),
        'totalQuantity': totalQuantity,
        'perUserLimit': perUserLimit,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt.toIso8601String(),
      },
    );
    return CouponTemplate.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<CouponTemplate> setCouponStatus({
    required String couponId,
    required bool enabled,
  }) async {
    final data = await _client.patch(
      '/merchant/coupons/$couponId/status',
      body: {'enabled': enabled},
    );
    return CouponTemplate.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<List<CouponTemplate>> listClaimableForMerchant(
    String merchantId,
  ) async {
    final data = await _client.get('/coupons/merchant/$merchantId');
    return (data as List? ?? const [])
        .map((e) => CouponTemplate.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<CouponClaim> claim(String templateId) async {
    final data = await _client.post('/coupons/$templateId/claim', body: {});
    return CouponClaim.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<List<CouponClaim>> listMy({String? merchantId}) async {
    final data = await _client.get(
      '/coupons/my',
      query: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    return (data as List? ?? const [])
        .map((e) => CouponClaim.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<BestCouponResult?> findBest({
    required String merchantId,
    required MealType mealType,
    required double amount,
  }) async {
    final data = await _client.get(
      '/coupons/best',
      query: {
        'merchantId': merchantId,
        'mealType': mealType.name,
        'amount': amount.toString(),
      },
    );
    if (data == null) return null;
    return BestCouponResult.fromJson((data as Map).cast<String, dynamic>());
  }
}
