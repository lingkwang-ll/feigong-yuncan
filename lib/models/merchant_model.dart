class Merchant {
  final String id;
  final String name;
  final String logo;
  final String coverImage;
  final int distance;
  final double rating;
  final int monthSold;
  final String hygieneGrade;
  final bool isOpen;
  final String address;
  final String paymentQrCode;
  final String wechatPaymentQrUrl;
  final String alipayPaymentQrUrl;
  final double deliveryFee;
  final String contactName;
  final String contactPhone;
  final String description;
  final List<String> deliveryModes;
  final String deliveryScope;
  final String estimatedDeliveryTime;
  final List<String> supportedMealTypes;
  final Map<String, MealHoursSetting> mealOpeningHours;

  /// 由营业时间结束时间自动同步；员工端优先读 `mealOpeningHours` 的 end。
  final Map<String, String> mealOrderDeadlines;

  const Merchant({
    required this.id,
    required this.name,
    required this.logo,
    required this.coverImage,
    required this.distance,
    required this.rating,
    required this.monthSold,
    required this.hygieneGrade,
    required this.isOpen,
    required this.address,
    required this.paymentQrCode,
    this.wechatPaymentQrUrl = '',
    this.alipayPaymentQrUrl = '',
    required this.deliveryFee,
    this.contactName = '',
    this.contactPhone = '',
    this.description = '',
    this.deliveryModes = const [],
    this.deliveryScope = '',
    this.estimatedDeliveryTime = '',
    this.supportedMealTypes = const [],
    this.mealOpeningHours = const {},
    this.mealOrderDeadlines = const {},
  });

  bool get hasCustomLogo =>
      logo.startsWith('/uploads/') ||
      logo.startsWith('http://') ||
      logo.startsWith('https://');

  static bool _isRealQr(String url) {
    if (url.isEmpty || url == 'qr') return false;
    return url.startsWith('/uploads/') ||
        url.startsWith('http://') ||
        url.startsWith('https://');
  }

  /// 微信收款码（优先专用字段，兼容旧 paymentQrCode）
  String get effectiveWechatPaymentQr {
    if (_isRealQr(wechatPaymentQrUrl)) return wechatPaymentQrUrl;
    if (_isRealQr(paymentQrCode)) return paymentQrCode;
    return '';
  }

  /// 支付宝收款码
  String get effectiveAlipayPaymentQr {
    if (_isRealQr(alipayPaymentQrUrl)) return alipayPaymentQrUrl;
    return '';
  }

  bool get hasAnyPaymentQr =>
      effectiveWechatPaymentQr.isNotEmpty ||
      effectiveAlipayPaymentQr.isNotEmpty;

  Merchant copyWith({
    String? id,
    String? name,
    String? logo,
    String? coverImage,
    int? distance,
    double? rating,
    int? monthSold,
    String? hygieneGrade,
    bool? isOpen,
    String? address,
    String? paymentQrCode,
    String? wechatPaymentQrUrl,
    String? alipayPaymentQrUrl,
    double? deliveryFee,
    String? contactName,
    String? contactPhone,
    String? description,
    List<String>? deliveryModes,
    String? deliveryScope,
    String? estimatedDeliveryTime,
    List<String>? supportedMealTypes,
    Map<String, MealHoursSetting>? mealOpeningHours,
    Map<String, String>? mealOrderDeadlines,
  }) {
    return Merchant(
      id: id ?? this.id,
      name: name ?? this.name,
      logo: logo ?? this.logo,
      coverImage: coverImage ?? this.coverImage,
      distance: distance ?? this.distance,
      rating: rating ?? this.rating,
      monthSold: monthSold ?? this.monthSold,
      hygieneGrade: hygieneGrade ?? this.hygieneGrade,
      isOpen: isOpen ?? this.isOpen,
      address: address ?? this.address,
      paymentQrCode: paymentQrCode ?? this.paymentQrCode,
      wechatPaymentQrUrl: wechatPaymentQrUrl ?? this.wechatPaymentQrUrl,
      alipayPaymentQrUrl: alipayPaymentQrUrl ?? this.alipayPaymentQrUrl,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      contactName: contactName ?? this.contactName,
      contactPhone: contactPhone ?? this.contactPhone,
      description: description ?? this.description,
      deliveryModes: deliveryModes ?? this.deliveryModes,
      deliveryScope: deliveryScope ?? this.deliveryScope,
      estimatedDeliveryTime:
          estimatedDeliveryTime ?? this.estimatedDeliveryTime,
      supportedMealTypes: supportedMealTypes ?? this.supportedMealTypes,
      mealOpeningHours: mealOpeningHours ?? this.mealOpeningHours,
      mealOrderDeadlines: mealOrderDeadlines ?? this.mealOrderDeadlines,
    );
  }
}

class MealHoursSetting {
  final bool enabled;
  /// 兼容旧数据：`07:00-09:00`
  final String hours;
  final String start;
  final String end;

  const MealHoursSetting({
    this.enabled = true,
    this.hours = '',
    this.start = '',
    this.end = '',
  });

  String get effectiveStart {
    if (start.trim().isNotEmpty) return start.trim();
    return _fromHours().$1;
  }

  String get effectiveEnd {
    if (end.trim().isNotEmpty) return end.trim();
    return _fromHours().$2;
  }

  (String, String) _fromHours() {
    final parts = hours.split('-');
    if (parts.length != 2) return ('', '');
    return (parts[0].trim(), parts[1].trim());
  }

  Map<String, dynamic> toJson() {
    final s = effectiveStart;
    final e = effectiveEnd;
    final map = <String, dynamic>{
      'enabled': enabled,
      if (s.isNotEmpty) 'start': s,
      if (e.isNotEmpty) 'end': e,
    };
    if (s.isNotEmpty && e.isNotEmpty) {
      map['hours'] = '$s-$e';
    } else if (hours.isNotEmpty) {
      map['hours'] = hours;
    }
    return map;
  }

  factory MealHoursSetting.fromJson(dynamic json) {
    if (json is! Map) {
      return const MealHoursSetting();
    }
    final start = (json['start'] ?? '').toString();
    final end = (json['end'] ?? '').toString();
    final hours = (json['hours'] ?? '').toString();
    return MealHoursSetting(
      enabled: json['enabled'] as bool? ?? true,
      hours: hours,
      start: start,
      end: end,
    );
  }
}
