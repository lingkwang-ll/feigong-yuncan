// ignore_for_file: use_null_aware_elements

import 'dart:typed_data';

import '../models/dish_model.dart';
import '../models/order_model.dart';
import 'api_client.dart';

/// 订单 API（与 `server/` 后端对齐）
///
/// 后端约定：
/// - POST /api/orders：items 兼容嵌套结构 `{ dish, quantity }`，
///   后端会回写 `id` / `order_no` / `createdAt`
/// - GET /api/orders/my?userId=xxx：员工"我的订单"
/// - GET /api/merchant/orders?merchantId=xxx：商家订单列表
/// - PUT /api/orders/:id/status：更新状态
/// - POST /api/uploads/payment-screenshot：上传付款截图，
///   可携带 orderId，后端会自动把 URL 写回订单的 payment_screenshot_url
class OrderApi {
  OrderApi(this._client);

  final ApiClient _client;

  /// GET /api/orders/my
  Future<List<Order>> getEmployeeOrders({required String userId}) async {
    final data = await _client.get(
      '/orders/my',
      query: {'userId': userId},
    );
    final list = (data as List? ?? const []);
    return list
        .map((e) => Order.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// GET /api/merchant/orders
  ///
  /// [merchantId] 留空时后端会返回全部订单（演示用单商家场景）。
  Future<List<Order>> getMerchantOrders({String? merchantId}) async {
    final data = await _client.get(
      '/merchant/orders',
      query: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    final list = (data as List? ?? const []);
    return list
        .map((e) => Order.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// POST /api/orders
  Future<Order> createOrder(
    Order order, {
    String? userId,
    String? couponClaimId,
  }) async {
    final body = order.toJson();
    body.remove('createdAt');
    if (userId != null && userId.isNotEmpty) body['userId'] = userId;
    if (couponClaimId != null && couponClaimId.isNotEmpty) {
      body['couponClaimId'] = couponClaimId;
    }
    final data = await _client.post('/orders', body: body);
    return Order.fromJson((data as Map).cast<String, dynamic>());
  }

  /// POST /api/orders（套餐下单专用：服务端权威重算价格）
  ///
  /// 与普通下单的差异：body 多带 `packageOrder = { packageId, selectedDishIds, extras }`，
  /// 后端会忽略前端 items / goodsAmount / totalAmount，按套餐基础价 + 加菜重算并校验规则。
  Future<Order> createPackageOrder({
    required String merchantId,
    required String merchantName,
    required String packageId,
    required List<String> selectedDishIds,
    List<Map<String, dynamic>> extras = const [],
    required DeliveryType deliveryType,
    String? mealType,
    PaymentType? paymentType,
    String address = '',
    String phone = '',
    String remark = '',
    bool isMealCollector = false,
    String collectorName = '',
    String collectorPhone = '',
    String collectorAddress = '',
    double? collectorLatitude,
    double? collectorLongitude,
    String collectorPoiName = '',
    String collectorAddressText = '',
    String? couponClaimId,
  }) async {
    final body = <String, dynamic>{
      'merchantId': merchantId,
      'merchantName': merchantName,
      'deliveryType': deliveryType.name,
      'address': address,
      'phone': phone,
      'remark': remark,
      // 套餐订单的金额由后端重算，这里传 0 占位即可
      'goodsAmount': 0,
      'deliveryFee': 0,
      'totalAmount': 0,
      if (mealType != null && mealType.isNotEmpty) 'mealType': mealType,
      if (paymentType != null) 'paymentType': paymentType.apiValue,
      'isMealCollector': isMealCollector,
      'collectorName': collectorName,
      'collectorPhone': collectorPhone,
      'collectorAddress': collectorAddress,
      if (collectorLatitude != null) 'collectorLatitude': collectorLatitude,
      if (collectorLongitude != null) 'collectorLongitude': collectorLongitude,
      'collectorPoiName': collectorPoiName,
      'collectorAddressText': collectorAddressText,
      'items': const [], // 套餐下单时 items 由后端从 packageOrder 推导
      'packageOrder': {
        'packageId': packageId,
        'selectedDishIds': selectedDishIds,
        'extras': extras,
      },
      if (couponClaimId != null && couponClaimId.isNotEmpty)
        'couponClaimId': couponClaimId,
    };
    final data = await _client.post('/orders', body: body);
    return Order.fromJson((data as Map).cast<String, dynamic>());
  }

  /// PUT /api/orders/:orderId/status
  Future<Order> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String? rejectReason,
  }) async {
    final data = await _client.put(
      '/orders/$orderId/status',
      body: {
        'status': status.name,
        if (rejectReason != null && rejectReason.isNotEmpty)
          'rejectReason': rejectReason,
      },
    );
    return Order.fromJson((data as Map).cast<String, dynamic>());
  }

  /// POST /api/uploads/payment-screenshot
  Future<String> uploadPaymentScreenshot({
    required String orderId,
    required Uint8List imageBytes,
    required String filename,
    required String manualPayChannel,
  }) async {
    final data = await _client.uploadFileBytes(
      '/uploads/payment-screenshot',
      fieldName: 'file',
      bytes: imageBytes,
      filename: filename,
      extraFields: {
        'orderId': orderId,
        'manualPayChannel': manualPayChannel,
      },
    );
    return (data as Map)['url'].toString();
  }

  Future<CompanyPayEligibility> getCompanyPayEligibility(MealType mealType) async {
    final data = await _client.get(
      '/orders/company-pay-eligibility',
      query: {'mealType': mealType.name},
    );
    return CompanyPayEligibility.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }

  Future<OvertimeEligibility> getOvertimeEligibility() async {
    final data = await _client.get('/orders/overtime-eligibility');
    return OvertimeEligibility.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }
}

class CompanyPayEligibility {
  final MealType mealType;
  final bool eligible;
  final bool onRoster;
  final bool companyPayUsed;
  final bool mealClosed;
  final String reason;
  final String hint;

  const CompanyPayEligibility({
    required this.mealType,
    required this.eligible,
    required this.onRoster,
    required this.companyPayUsed,
    required this.mealClosed,
    required this.reason,
    required this.hint,
  });

  factory CompanyPayEligibility.fromJson(Map<String, dynamic> json) {
    final mt = (json['mealType'] as String?) ?? 'lunch';
    return CompanyPayEligibility(
      mealType: MealType.values.firstWhere(
        (e) => e.name == mt,
        orElse: () => MealType.lunch,
      ),
      eligible: json['eligible'] == true,
      onRoster: json['onRoster'] == true,
      companyPayUsed: json['companyPayUsed'] == true,
      mealClosed: json['mealClosed'] == true,
      reason: (json['reason'] as String?) ?? '',
      hint: (json['hint'] as String?) ?? '',
    );
  }
}

class OvertimeEligibility {
  final bool showOvertimeTab;
  final bool onRoster;
  final bool companyPayUsed;
  final bool mealClosed;
  final String reason;
  final String hint;

  const OvertimeEligibility({
    required this.showOvertimeTab,
    required this.onRoster,
    required this.companyPayUsed,
    required this.mealClosed,
    required this.reason,
    required this.hint,
  });

  factory OvertimeEligibility.fromJson(Map<String, dynamic> json) {
    return OvertimeEligibility(
      showOvertimeTab: json['showOvertimeTab'] == true,
      onRoster: json['onRoster'] == true,
      companyPayUsed: json['companyPayUsed'] == true,
      mealClosed: json['mealClosed'] == true,
      reason: (json['reason'] as String?) ?? '',
      hint: (json['hint'] as String?) ?? '',
    );
  }

  static const hidden = OvertimeEligibility(
    showOvertimeTab: false,
    onRoster: false,
    companyPayUsed: false,
    mealClosed: false,
    reason: 'not_on_roster',
    hint: '未在名单中',
  );
}
