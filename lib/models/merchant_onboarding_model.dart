enum MerchantOnboardingPhoneStatus { none, pending, approved, rejected }

class MerchantOnboardingStatusInfo {
  final MerchantOnboardingPhoneStatus status;
  final String? merchantId;
  final String rejectReason;
  final String message;

  const MerchantOnboardingStatusInfo({
    required this.status,
    this.merchantId,
    this.rejectReason = '',
    this.message = '',
  });

  factory MerchantOnboardingStatusInfo.fromJson(Map<String, dynamic> j) {
    final raw = (j['status'] ?? 'none').toString();
    MerchantOnboardingPhoneStatus st;
    switch (raw) {
      case 'pending':
        st = MerchantOnboardingPhoneStatus.pending;
        break;
      case 'approved':
        st = MerchantOnboardingPhoneStatus.approved;
        break;
      case 'rejected':
        st = MerchantOnboardingPhoneStatus.rejected;
        break;
      default:
        st = MerchantOnboardingPhoneStatus.none;
    }
    return MerchantOnboardingStatusInfo(
      status: st,
      merchantId: j['merchantId']?.toString(),
      rejectReason: (j['rejectReason'] ?? '').toString(),
      message: (j['message'] ?? '').toString(),
    );
  }
}

/// 商家入驻申请实体
///
/// 旧字段 [deliveryScope] / [estimatedDeliveryTime] / [deliveryFee] 仅为
/// 兼容历史数据保留，入驻页已不再展示、不再校验、不再提交（toJson 中不输出）。
class MerchantOnboardingApplication {
  final String? id;
  final String merchantName;
  final String shortName;
  final String contactName;
  final String contactPhone;
  final String address;
  final String companyId;
  final List<String> supportedMealTypes;
  final List<String> deliveryModes;

  /// @deprecated 入驻页不再提交，仅为兼容旧数据保留
  final String deliveryScope;

  /// @deprecated 入驻页不再提交，仅为兼容旧数据保留
  final String estimatedDeliveryTime;

  /// @deprecated 入驻页不再提交，仅为兼容旧数据保留
  final double deliveryFee;

  final String paymentMethod;
  final String paymentQr;
  final String paymentReceiverName;
  final String businessLicenseUrl;
  final String foodLicenseUrl;
  final String storePhotoUrl;
  final String remark;
  final String rejectReason;

  // === 企业级商家审核扩展字段 ===
  /// 店铺显示名称（用户端列表展示用）
  final String storeDisplayName;

  /// 客服电话
  final String customerServicePhone;

  /// 所属企业 / 服务企业（文本占位，后续可改下拉）
  final String servedCompanyText;

  /// 营业日（mon/tue/wed/thu/fri/sat/sun）
  final List<String> businessDays;

  /// 营业开始时间，HH:MM
  final String businessHoursStart;

  /// 营业结束时间，HH:MM
  final String businessHoursEnd;

  /// 各餐段营业时间（enabled / start / end）
  final Map<String, dynamic> mealOpeningHours;

  /// 各餐段接单截止时间（由营业时间结束时间同步，兼容旧接口）
  final Map<String, String> mealOrderDeadlines;

  /// 收款主体类型 individual / company
  final String paymentSubjectType;

  /// 收款主体名称
  final String paymentSubjectName;

  /// 对公开户名
  final String bankAccountName;

  /// 开户行
  final String bankName;

  /// 对公账号
  final String bankAccountNumber;

  /// 营业执照主体名称
  final String businessLicenseSubject;

  /// 营业执照有效期，'YYYY-MM-DD' 或 'permanent'
  final String businessLicenseValidUntil;

  /// 统一社会信用代码（18 位字母数字）
  final String unifiedSocialCreditCode;

  /// 食品经营许可证编号
  final String foodLicenseNumber;

  /// 食品经营许可证有效期
  final String foodLicenseValidUntil;

  /// 许可经营项目
  final String licensedBusinessScope;

  /// 后厨 / 操作间照片
  final String kitchenPhotoUrl;

  /// 健康证
  final String healthCertificateUrl;

  // === 多图 / 多选向后兼容字段（旧单图 / 单值字段仍保留，作为兼容字段） ===
  /// 收款方式多选（wechat / alipay）
  final List<String> paymentMethods;

  /// 微信收款码图片列表（多张）
  final List<String> wechatPaymentQrUrls;

  /// 支付宝收款码图片列表（多张）
  final List<String> alipayPaymentQrUrls;

  /// 营业执照图片列表（多张）
  final List<String> businessLicenseUrls;

  /// 食品经营许可证图片列表（多张）
  final List<String> foodLicenseUrls;

  /// 后厨 / 操作间照片列表（多张）
  final List<String> kitchenPhotoUrls;

  /// 健康证图片列表（多张）
  final List<String> healthCertificateUrls;

  /// 门店照片列表（多张）
  final List<String> storePhotoUrls;

  /// 协议版本（签署留存）
  final String? agreementVersion;

  /// 客户端签署时间 ISO
  final String? clientTime;

  /// 设备信息
  final String? deviceInfo;

  const MerchantOnboardingApplication({
    this.id,
    required this.merchantName,
    this.shortName = '',
    required this.contactName,
    required this.contactPhone,
    required this.address,
    this.companyId = 'comp_default',
    this.supportedMealTypes = const [],
    this.deliveryModes = const [],
    this.deliveryScope = '',
    this.estimatedDeliveryTime = '',
    this.deliveryFee = 0,
    this.paymentMethod = 'wechat',
    this.paymentQr = '',
    this.paymentReceiverName = '',
    this.businessLicenseUrl = '',
    this.foodLicenseUrl = '',
    this.storePhotoUrl = '',
    this.remark = '',
    this.rejectReason = '',
    this.storeDisplayName = '',
    this.customerServicePhone = '',
    this.servedCompanyText = '',
    this.businessDays = const [],
    this.businessHoursStart = '',
    this.businessHoursEnd = '',
    this.mealOpeningHours = const {},
    this.mealOrderDeadlines = const {},
    this.paymentSubjectType = '',
    this.paymentSubjectName = '',
    this.bankAccountName = '',
    this.bankName = '',
    this.bankAccountNumber = '',
    this.businessLicenseSubject = '',
    this.businessLicenseValidUntil = '',
    this.unifiedSocialCreditCode = '',
    this.foodLicenseNumber = '',
    this.foodLicenseValidUntil = '',
    this.licensedBusinessScope = '',
    this.kitchenPhotoUrl = '',
    this.healthCertificateUrl = '',
    this.paymentMethods = const [],
    this.wechatPaymentQrUrls = const [],
    this.alipayPaymentQrUrls = const [],
    this.businessLicenseUrls = const [],
    this.foodLicenseUrls = const [],
    this.kitchenPhotoUrls = const [],
    this.healthCertificateUrls = const [],
    this.storePhotoUrls = const [],
    this.agreementVersion,
    this.clientTime,
    this.deviceInfo,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      if (id != null) 'id': id,
      'merchantName': merchantName,
      if (shortName.isNotEmpty) 'shortName': shortName,
      'contactName': contactName,
      'contactPhone': contactPhone,
      'address': address,
      'supportedMealTypes': supportedMealTypes,
      'deliveryModes': deliveryModes,
      'paymentMethod': paymentMethod,
      'paymentQr': paymentQr,
      'paymentReceiverName': paymentReceiverName,
      'businessLicenseUrl': businessLicenseUrl,
      'foodLicenseUrl': foodLicenseUrl,
      if (storePhotoUrl.isNotEmpty) 'storePhotoUrl': storePhotoUrl,
      if (remark.isNotEmpty) 'remark': remark,
      // 企业级商家审核扩展字段
      if (storeDisplayName.isNotEmpty) 'storeDisplayName': storeDisplayName,
      if (customerServicePhone.isNotEmpty)
        'customerServicePhone': customerServicePhone,
      if (servedCompanyText.isNotEmpty) 'servedCompanyText': servedCompanyText,
      if (businessDays.isNotEmpty) 'businessDays': businessDays,
      if (businessHoursStart.isNotEmpty)
        'businessHoursStart': businessHoursStart,
      if (businessHoursEnd.isNotEmpty) 'businessHoursEnd': businessHoursEnd,
      if (mealOpeningHours.isNotEmpty) 'mealOpeningHours': mealOpeningHours,
      if (mealOrderDeadlines.isNotEmpty)
        'mealOrderDeadlines': mealOrderDeadlines,
      if (paymentSubjectType.isNotEmpty)
        'paymentSubjectType': paymentSubjectType,
      if (paymentSubjectName.isNotEmpty)
        'paymentSubjectName': paymentSubjectName,
      if (bankAccountName.isNotEmpty) 'bankAccountName': bankAccountName,
      if (bankName.isNotEmpty) 'bankName': bankName,
      if (bankAccountNumber.isNotEmpty) 'bankAccountNumber': bankAccountNumber,
      if (businessLicenseSubject.isNotEmpty)
        'businessLicenseSubject': businessLicenseSubject,
      if (businessLicenseValidUntil.isNotEmpty)
        'businessLicenseValidUntil': businessLicenseValidUntil,
      if (unifiedSocialCreditCode.isNotEmpty)
        'unifiedSocialCreditCode': unifiedSocialCreditCode,
      if (foodLicenseNumber.isNotEmpty) 'foodLicenseNumber': foodLicenseNumber,
      if (foodLicenseValidUntil.isNotEmpty)
        'foodLicenseValidUntil': foodLicenseValidUntil,
      if (licensedBusinessScope.isNotEmpty)
        'licensedBusinessScope': licensedBusinessScope,
      if (kitchenPhotoUrl.isNotEmpty) 'kitchenPhotoUrl': kitchenPhotoUrl,
      if (healthCertificateUrl.isNotEmpty)
        'healthCertificateUrl': healthCertificateUrl,
      // 多图 / 多选字段（始终输出空数组也无害，后端会做 sanitize）
      if (paymentMethods.isNotEmpty) 'paymentMethods': paymentMethods,
      if (wechatPaymentQrUrls.isNotEmpty)
        'wechatPaymentQrUrls': wechatPaymentQrUrls,
      if (alipayPaymentQrUrls.isNotEmpty)
        'alipayPaymentQrUrls': alipayPaymentQrUrls,
      if (businessLicenseUrls.isNotEmpty)
        'businessLicenseUrls': businessLicenseUrls,
      if (foodLicenseUrls.isNotEmpty) 'foodLicenseUrls': foodLicenseUrls,
      if (kitchenPhotoUrls.isNotEmpty) 'kitchenPhotoUrls': kitchenPhotoUrls,
      if (healthCertificateUrls.isNotEmpty)
        'healthCertificateUrls': healthCertificateUrls,
      if (storePhotoUrls.isNotEmpty) 'storePhotoUrls': storePhotoUrls,
      if (agreementVersion != null && agreementVersion!.isNotEmpty)
        'agreementVersion': agreementVersion,
      if (clientTime != null && clientTime!.isNotEmpty) 'clientTime': clientTime,
      if (deviceInfo != null && deviceInfo!.isNotEmpty) 'deviceInfo': deviceInfo,
    };
    return map;
  }

  factory MerchantOnboardingApplication.fromJson(Map<String, dynamic> j) {
    Map<String, String> readMealDeadlines(dynamic v) {
      if (v is Map) {
        return v.map((key, value) => MapEntry(key.toString(), value.toString()));
      }
      return const {};
    }

    /// 多图字段统一解析：优先用数组；若空且旧单图字段非空，则用旧字段兜底
    List<String> readUrlList(dynamic v, String fallback) {
      if (v is List) {
        final list = v
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        if (list.isNotEmpty) return list;
      }
      final f = fallback.trim();
      if (f.isNotEmpty && f != 'qr' && f != 'logo') {
        return [f];
      }
      return const [];
    }

    /// 收款方式数组解析：优先 paymentMethods 数组；若空则用旧单值
    List<String> readPaymentMethods(dynamic v, String legacy) {
      if (v is List) {
        final list = v
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        if (list.isNotEmpty) return list;
      }
      final l = legacy.trim();
      if (l.isEmpty) return const [];
      return l
          .split(RegExp(r'[,，;；\s]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final businessLicenseUrl = (j['businessLicenseUrl'] ?? '').toString();
    final foodLicenseUrl = (j['foodLicenseUrl'] ?? '').toString();
    final storePhotoUrl = (j['storePhotoUrl'] ?? '').toString();
    final kitchenPhotoUrl = (j['kitchenPhotoUrl'] ?? '').toString();
    final healthCertificateUrl = (j['healthCertificateUrl'] ?? '').toString();
    final paymentQr = (j['paymentQr'] ?? '').toString();
    final paymentMethod = (j['paymentMethod'] ?? '').toString();

    return MerchantOnboardingApplication(
      id: j['id']?.toString(),
      merchantName: (j['merchantName'] ?? '').toString(),
      shortName: (j['shortName'] ?? '').toString(),
      contactName: (j['contactName'] ?? '').toString(),
      contactPhone: (j['contactPhone'] ?? j['phone'] ?? '').toString(),
      address: (j['address'] ?? '').toString(),
      companyId: (j['companyId'] ?? 'comp_default').toString(),
      supportedMealTypes: (j['supportedMealTypes'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      deliveryModes: (j['deliveryModes'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      deliveryScope: (j['deliveryScope'] ?? '').toString(),
      estimatedDeliveryTime: (j['estimatedDeliveryTime'] ?? '').toString(),
      deliveryFee: (j['deliveryFee'] as num?)?.toDouble() ?? 0,
      paymentMethod: paymentMethod,
      paymentQr: paymentQr,
      paymentReceiverName: (j['paymentReceiverName'] ?? '').toString(),
      businessLicenseUrl: businessLicenseUrl,
      foodLicenseUrl: foodLicenseUrl,
      storePhotoUrl: storePhotoUrl,
      remark: (j['remark'] ?? '').toString(),
      rejectReason: (j['rejectReason'] ?? '').toString(),
      storeDisplayName: (j['storeDisplayName'] ?? '').toString(),
      customerServicePhone: (j['customerServicePhone'] ?? '').toString(),
      servedCompanyText: (j['servedCompanyText'] ?? '').toString(),
      businessDays: (j['businessDays'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      businessHoursStart: (j['businessHoursStart'] ?? '').toString(),
      businessHoursEnd: (j['businessHoursEnd'] ?? '').toString(),
      mealOrderDeadlines: readMealDeadlines(j['mealOrderDeadlines']),
      paymentSubjectType: (j['paymentSubjectType'] ?? '').toString(),
      paymentSubjectName: (j['paymentSubjectName'] ?? '').toString(),
      bankAccountName: (j['bankAccountName'] ?? '').toString(),
      bankName: (j['bankName'] ?? '').toString(),
      bankAccountNumber: (j['bankAccountNumber'] ?? '').toString(),
      businessLicenseSubject: (j['businessLicenseSubject'] ?? '').toString(),
      businessLicenseValidUntil:
          (j['businessLicenseValidUntil'] ?? '').toString(),
      unifiedSocialCreditCode:
          (j['unifiedSocialCreditCode'] ?? '').toString(),
      foodLicenseNumber: (j['foodLicenseNumber'] ?? '').toString(),
      foodLicenseValidUntil:
          (j['foodLicenseValidUntil'] ?? '').toString(),
      licensedBusinessScope:
          (j['licensedBusinessScope'] ?? '').toString(),
      kitchenPhotoUrl: kitchenPhotoUrl,
      healthCertificateUrl: healthCertificateUrl,
      paymentMethods: readPaymentMethods(j['paymentMethods'], paymentMethod),
      wechatPaymentQrUrls: readUrlList(j['wechatPaymentQrUrls'], ''),
      alipayPaymentQrUrls: readUrlList(j['alipayPaymentQrUrls'], ''),
      businessLicenseUrls:
          readUrlList(j['businessLicenseUrls'], businessLicenseUrl),
      foodLicenseUrls: readUrlList(j['foodLicenseUrls'], foodLicenseUrl),
      kitchenPhotoUrls: readUrlList(j['kitchenPhotoUrls'], kitchenPhotoUrl),
      healthCertificateUrls:
          readUrlList(j['healthCertificateUrls'], healthCertificateUrl),
      storePhotoUrls: readUrlList(j['storePhotoUrls'], storePhotoUrl),
    );
  }
}
