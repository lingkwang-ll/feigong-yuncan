import 'cart_item_model.dart';
import '../utils/display_text_util.dart';
import '../utils/order_time_util.dart';

enum DeliveryType { delivery, selfPickup }

extension DeliveryTypeLabel on DeliveryType {
  String get label =>
      this == DeliveryType.delivery ? '配送' : '自取';
}

enum OrderStatus {
  pendingPayment, // 待支付
  paymentSubmitted, // 已上传支付凭证
  pendingMerchantConfirm, // 商家待确认
  accepted, // 已接单
  delivering, // 配送中
  completed, // 已完成
  cancelled, // 已取消
}

enum PaymentType {
  selfPay,
  companyPay,
  mixedPay,
  ;

  static PaymentType fromApi(String? raw) {
    if (raw == 'company_pay') return PaymentType.companyPay;
    if (raw == 'mixed_pay') return PaymentType.mixedPay;
    return PaymentType.selfPay;
  }
}

extension PaymentTypeLabel on PaymentType {
  String get label {
    switch (this) {
      case PaymentType.companyPay:
        return '企业支付';
      case PaymentType.mixedPay:
        return '企业代付 + 个人支付';
      case PaymentType.selfPay:
        return '个人支付';
    }
  }

  String get apiValue {
    switch (this) {
      case PaymentType.companyPay:
        return 'company_pay';
      case PaymentType.mixedPay:
        return 'mixed_pay';
      case PaymentType.selfPay:
        return 'self_pay';
    }
  }
}

extension OrderStatusLabel on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.pendingPayment:
        return '待支付';
      case OrderStatus.paymentSubmitted:
        return '已上传凭证';
      case OrderStatus.pendingMerchantConfirm:
        return '商家待确认';
      case OrderStatus.accepted:
        return '已接单';
      case OrderStatus.delivering:
        return '配送中';
      case OrderStatus.completed:
        return '已完成';
      case OrderStatus.cancelled:
        return '已取消';
    }
  }
}

/// 套餐订单中"按规则选择的菜品"明细
class OrderSelectedItem {
  final String dishId;
  final String name;
  final String category;
  final String? mealType;
  const OrderSelectedItem({
    required this.dishId,
    required this.name,
    required this.category,
    this.mealType,
  });
  factory OrderSelectedItem.fromJson(Map<String, dynamic> json) =>
      OrderSelectedItem(
        dishId: (json['dishId'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        category: (json['category'] as String?) ?? '',
        mealType: json['mealType'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'dishId': dishId,
        'name': name,
        'category': category,
        if (mealType != null) 'mealType': mealType,
      };
}

/// 套餐订单中"加菜"明细
class OrderExtraItem {
  final String dishId;
  final String name;
  final double unitPrice;
  final int quantity;
  final double subtotal;
  const OrderExtraItem({
    required this.dishId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
  });
  factory OrderExtraItem.fromJson(Map<String, dynamic> json) => OrderExtraItem(
        dishId: (json['dishId'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        unitPrice: ((json['unitPrice'] as num?) ?? 0).toDouble(),
        quantity: ((json['quantity'] as num?) ?? 0).toInt(),
        subtotal: ((json['subtotal'] as num?) ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'dishId': dishId,
        'name': name,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'subtotal': subtotal,
      };
}

class Order {
  final String id;
  final String orderNo;
  final String merchantId;
  final String merchantName;
  final String customerName;
  final String customerCompany;
  final List<CartItem> items;
  final DeliveryType deliveryType;
  final String address;
  final String phone;
  final String remark;
  final double goodsAmount;
  final double deliveryFee;
  final double totalAmount;
  OrderStatus status;
  final PaymentType paymentType;
  final String? paymentScreenshot;
  final String? manualPayChannel;
  String? rejectReason;
  final DateTime createdAt;
  final bool isMealCollector;
  final String collectorName;
  final String collectorPhone;
  final String collectorAddress;
  final double? collectorLatitude;
  final double? collectorLongitude;
  final String collectorPoiName;
  final String collectorAddressText;
  // 套餐订单扩展字段（普通菜品订单为 null / 空数组 / 0）
  final String? packageId;
  final String? packageName;
  final double packageBasePrice;
  final List<OrderSelectedItem> selectedItems;
  final List<OrderExtraItem> extraItems;
  final double extraAmount;
  final double finalAmount;
  final double packageAmount;
  final double companyPayAmount;
  final double employeePayAmount;
  final String? couponClaimId;
  final double couponDiscountAmount;
  final double employeePayBeforeCoupon;
  final String settlementStatus;
  final String paymentChannel;
  final DateTime? completedAt;
  final DateTime? settlementEligibleAt;

  final String? itemsSummaryFromApi;

  bool get isCompanyPay => paymentType == PaymentType.companyPay;

  bool get isMixedPay => paymentType == PaymentType.mixedPay;

  bool get needsPayment =>
      employeePayAmount > 0 &&
      (status == OrderStatus.pendingPayment ||
          status == OrderStatus.paymentSubmitted);

  bool get needsPaymentScreenshot => employeePayAmount > 0;

  Order({
    required this.id,
    this.orderNo = '',
    required this.merchantId,
    required this.merchantName,
    required this.customerName,
    required this.customerCompany,
    required this.items,
    required this.deliveryType,
    required this.address,
    required this.phone,
    required this.remark,
    required this.goodsAmount,
    required this.deliveryFee,
    required this.totalAmount,
    required this.status,
    this.paymentType = PaymentType.selfPay,
    required this.createdAt,
    this.paymentScreenshot,
    this.manualPayChannel,
    this.rejectReason,
    this.isMealCollector = false,
    this.collectorName = '',
    this.collectorPhone = '',
    this.collectorAddress = '',
    this.collectorLatitude,
    this.collectorLongitude,
    this.collectorPoiName = '',
    this.collectorAddressText = '',
    this.packageId,
    this.packageName,
    this.packageBasePrice = 0,
    this.selectedItems = const [],
    this.extraItems = const [],
    this.extraAmount = 0,
    this.finalAmount = 0,
    this.packageAmount = 0,
    this.companyPayAmount = 0,
    this.employeePayAmount = 0,
    this.couponClaimId,
    this.couponDiscountAmount = 0,
    this.employeePayBeforeCoupon = 0,
    this.settlementStatus = 'not_paid',
    this.paymentChannel = 'manual_qr',
    this.completedAt,
    this.settlementEligibleAt,
    this.itemsSummaryFromApi,
  });

  /// 是否为套餐订单
  bool get isPackageOrder => (packageId ?? '').isNotEmpty;

  /// 展示用商家名（优先关联 merchants，兜底「未知商家」）
  String displayMerchantName({String? merchantProfileName}) =>
      resolveDisplayMerchantName(
        merchantName,
        fromMerchantProfile: merchantProfileName,
      );

  /// 展示用套餐名
  String get displayPackageName => resolveDisplayPackageName(packageName);

  /// 展示用订单号（后端 order_no 权威；旧数据回退 id）
  String get displayOrderNo =>
      orderNo.isNotEmpty ? orderNo : id;

  double get displayAmount =>
      isPackageOrder && finalAmount > 0 ? finalAmount : totalAmount;

  int get totalQuantity =>
      items.fold(0, (sum, item) => sum + item.quantity);

  String get itemsSummary {
    if (itemsSummaryFromApi != null && itemsSummaryFromApi!.isNotEmpty) {
      return itemsSummaryFromApi!;
    }
    return buildOrderItemsSummary(
      isPackageOrder: isPackageOrder,
      packageName: packageName,
      lineItems: items
          .map((e) => (name: e.dish.name, quantity: e.quantity))
          .toList(),
      selectedItems: selectedItems
          .map((e) => (name: e.name, quantity: 1))
          .toList(),
      extraItems: extraItems
          .map((e) => (name: e.name, quantity: e.quantity))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderNo': orderNo,
        'merchantId': merchantId,
        'merchantName': merchantName,
        'customerName': customerName,
        'customerCompany': customerCompany,
        'items': items.map((e) => e.toJson()).toList(),
        'deliveryType': deliveryType.name,
        'address': address,
        'phone': phone,
        'remark': remark,
        'goodsAmount': goodsAmount,
        'deliveryFee': deliveryFee,
        'totalAmount': totalAmount,
        'status': status.name,
        'paymentType': paymentType.apiValue,
        'paymentScreenshot': paymentScreenshot,
        if (manualPayChannel != null) 'manualPayChannel': manualPayChannel,
        'rejectReason': rejectReason,
        'createdAt': createdAt.toIso8601String(),
        'isMealCollector': isMealCollector,
        'collectorName': collectorName,
        'collectorPhone': collectorPhone,
        'collectorAddress': collectorAddress,
        'collectorLatitude': collectorLatitude,
        'collectorLongitude': collectorLongitude,
        'collectorPoiName': collectorPoiName,
        'collectorAddressText': collectorAddressText,
        if (packageId != null) 'packageId': packageId,
        if (packageName != null) 'packageName': packageName,
        'packageBasePrice': packageBasePrice,
        'selectedItems': selectedItems.map((e) => e.toJson()).toList(),
        'extraItems': extraItems.map((e) => e.toJson()).toList(),
        'extraAmount': extraAmount,
        'finalAmount': finalAmount,
        'packageAmount': packageAmount,
        'companyPayAmount': companyPayAmount,
        'employeePayAmount': employeePayAmount,
        if (couponClaimId != null) 'couponClaimId': couponClaimId,
        'couponDiscountAmount': couponDiscountAmount,
        'employeePayBeforeCoupon': employeePayBeforeCoupon,
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        orderNo: (json['orderNo'] as String?) ?? '',
        merchantId: json['merchantId'] as String,
        merchantName: resolveDisplayMerchantName(
          (json['displayMerchantName'] as String?) ??
              (json['merchantName'] as String?),
        ),
        customerName: (json['customerName'] as String?) ?? '',
        customerCompany: (json['customerCompany'] as String?) ?? '',
        items: ((json['items'] as List?) ?? const [])
            .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        deliveryType: DeliveryType.values.firstWhere(
          (d) => d.name == json['deliveryType'],
          orElse: () => DeliveryType.delivery,
        ),
        address: (json['address'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        remark: (json['remark'] as String?) ?? '',
        goodsAmount: (json['goodsAmount'] as num).toDouble(),
        deliveryFee: (json['deliveryFee'] as num).toDouble(),
        totalAmount: (json['totalAmount'] as num).toDouble(),
        status: OrderStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => OrderStatus.pendingPayment,
        ),
        paymentType: PaymentType.fromApi(json['paymentType'] as String?),
        paymentScreenshot: json['paymentScreenshot'] as String?,
        manualPayChannel: json['manualPayChannel'] as String?,
        rejectReason: json['rejectReason'] as String?,
        createdAt: OrderTimeUtil.parseCreatedAt(json['createdAt'] as String?),
        isMealCollector: json['isMealCollector'] == true,
        collectorName: (json['collectorName'] as String?) ?? '',
        collectorPhone: (json['collectorPhone'] as String?) ?? '',
        collectorAddress: (json['collectorAddress'] as String?) ?? '',
        collectorLatitude: (json['collectorLatitude'] as num?)?.toDouble(),
        collectorLongitude: (json['collectorLongitude'] as num?)?.toDouble(),
        collectorPoiName: (json['collectorPoiName'] as String?) ?? '',
        collectorAddressText: (json['collectorAddressText'] as String?) ?? '',
        packageId: json['packageId'] as String?,
        packageName: json['packageName'] as String?,
        packageBasePrice: ((json['packageBasePrice'] as num?) ?? 0).toDouble(),
        selectedItems: ((json['selectedItems'] as List?) ?? const [])
            .map((e) =>
                OrderSelectedItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        extraItems: ((json['extraItems'] as List?) ?? const [])
            .map((e) =>
                OrderExtraItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        extraAmount: ((json['extraAmount'] as num?) ?? 0).toDouble(),
        finalAmount: ((json['finalAmount'] as num?) ?? 0).toDouble(),
        packageAmount: ((json['packageAmount'] as num?) ?? 0).toDouble(),
        companyPayAmount: ((json['companyPayAmount'] as num?) ?? 0).toDouble(),
        employeePayAmount: ((json['employeePayAmount'] as num?) ?? 0).toDouble(),
        couponClaimId: json['couponClaimId'] as String?,
        couponDiscountAmount:
            ((json['couponDiscountAmount'] as num?) ?? 0).toDouble(),
        employeePayBeforeCoupon:
            ((json['employeePayBeforeCoupon'] as num?) ?? 0).toDouble(),
        settlementStatus: (json['settlementStatus'] as String?) ?? 'not_paid',
        paymentChannel: (json['paymentChannel'] as String?) ?? 'manual_qr',
        completedAt: json['completedAt'] != null
            ? DateTime.tryParse(json['completedAt'] as String)
            : null,
        settlementEligibleAt: json['settlementEligibleAt'] != null
            ? DateTime.tryParse(json['settlementEligibleAt'] as String)
            : null,
        itemsSummaryFromApi: json['itemsSummary'] as String?,
      );
}
