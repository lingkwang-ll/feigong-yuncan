import 'dart:typed_data';

import '../models/merchant_model.dart';
import 'api_client.dart';
import 'payment_api.dart';

/// 商家 API（与 `server/` 后端对齐）
class MerchantApi {
  MerchantApi(this._client);

  final ApiClient _client;

  Future<List<Merchant>> getNearbyMerchants() async {
    final data = await _client.get('/merchants');
    final list = (data as List? ?? const []);
    return list
        .map((e) => merchantFromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<Merchant> getMerchantProfile({required String userId}) async {
    final data = await _client.get(
      '/merchant/profile',
      query: {'userId': userId},
    );
    return merchantFromJson((data as Map).cast<String, dynamic>());
  }

  Future<Merchant> updateProfile({
    required String merchantId,
    String? name,
    String? logo,
    String? contactName,
    String? contactPhone,
    String? address,
    String? description,
  }) async {
    final data = await _client.put(
      '/merchant/profile',
      body: {
        'merchantId': merchantId,
        if (name != null) 'name': name,
        if (logo != null) 'logo': logo,
        if (contactName != null) 'contactName': contactName,
        if (contactPhone != null) 'contactPhone': contactPhone,
        if (address != null) 'address': address,
        if (description != null) 'description': description,
      },
    );
    return merchantFromJson((data as Map).cast<String, dynamic>());
  }

  Future<Merchant> updateDeliverySettings({
    required String merchantId,
    List<String>? deliveryModes,
    double? deliveryFee,
    String? deliveryScope,
    String? estimatedDeliveryTime,
  }) async {
    final data = await _client.put(
      '/merchant/delivery-settings',
      body: {
        'merchantId': merchantId,
        if (deliveryModes != null) 'deliveryModes': deliveryModes,
        if (deliveryFee != null) 'deliveryFee': deliveryFee,
        if (deliveryScope != null) 'deliveryScope': deliveryScope,
        if (estimatedDeliveryTime != null)
          'estimatedDeliveryTime': estimatedDeliveryTime,
      },
    );
    return merchantFromJson((data as Map).cast<String, dynamic>());
  }

  Future<Merchant> updateBusinessHours({
    required String merchantId,
    List<String>? supportedMealTypes,
    Map<String, MealHoursSetting>? mealOpeningHours,
  }) async {
    final data = await _client.put(
      '/merchant/business-hours',
      body: {
        'merchantId': merchantId,
        if (supportedMealTypes != null)
          'supportedMealTypes': supportedMealTypes,
        if (mealOpeningHours != null)
          'mealOpeningHours': mealOpeningHours.map(
            (k, v) => MapEntry(k, v.toJson()),
          ),
      },
    );
    return merchantFromJson((data as Map).cast<String, dynamic>());
  }

  Future<String> uploadMerchantQrCodeBytes(
    List<int> bytes,
    String filename, {
    String? merchantId,
    String? channel,
  }) async {
    final data = await _client.uploadBytes(
      '/uploads/merchant-qr-code',
      fieldName: 'file',
      bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      filename: filename,
      extraFields: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
        if (channel != null && channel.isNotEmpty) 'channel': channel,
      },
    );
    return (data as Map)['url'].toString();
  }

  Future<String> uploadMerchantLogoBytes(
    List<int> bytes,
    String filename, {
    String? merchantId,
  }) async {
    final data = await _client.uploadBytes(
      '/uploads/merchant-logo',
      fieldName: 'file',
      bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      filename: filename,
      extraFields: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    return (data as Map)['url'].toString();
  }

  Future<String> uploadMerchantQrCode(
    String filePathOrBase64, {
    String? merchantId,
  }) async {
    final data = await _client.uploadFile(
      '/uploads/merchant-qr-code',
      fieldName: 'file',
      filePathOrBase64: filePathOrBase64,
      filename: 'qrcode.png',
      extraFields: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    return (data as Map)['url'].toString();
  }

  Future<void> updatePaymentQrCode({
    required String merchantId,
    required String qrCodeUrl,
    String? channel,
  }) async {
    await _client.put(
      '/merchant/payment-qr-code',
      body: {
        'merchantId': merchantId,
        'paymentQrCode': qrCodeUrl,
        if (channel != null && channel.isNotEmpty) 'channel': channel,
      },
    );
  }

  Future<void> updateIsOpen({
    required String merchantId,
    required bool isOpen,
  }) async {
    await _client.put(
      '/merchant/is-open',
      body: {'merchantId': merchantId, 'isOpen': isOpen},
    );
  }

  /// 记录商家协议签署（法律合规留存）
  Future<void> signAgreement({
    required String merchantId,
    required String agreementVersion,
    String? clientTime,
    String? deviceInfo,
  }) async {
    await _client.post(
      '/merchant/agreement/sign',
      body: {
        'merchantId': merchantId,
        'agreementVersion': agreementVersion,
        'clientTime': clientTime,
        'deviceInfo': deviceInfo,
      },
    );
  }

  Future<MerchantWalletSummary> getWallet({String? merchantId}) async {
    final data = await _client.get(
      '/merchant/wallet',
      query: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    return MerchantWalletSummary.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }

  Future<List<MerchantWithdrawalRecord>> listWithdrawals({
    String? merchantId,
  }) async {
    final data = await _client.get(
      '/merchant/withdrawals',
      query: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    final list = (data as List? ?? const []);
    return list
        .map((e) => MerchantWithdrawalRecord.fromJson(
            (e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<MerchantWithdrawalRecord> createWithdrawal({
    required String merchantId,
    required double amount,
    required String accountName,
    required String accountType,
    required String accountNo,
  }) async {
    final data = await _client.post(
      '/merchant/withdrawals',
      body: {
        'merchantId': merchantId,
        'amount': amount,
        'accountName': accountName,
        'accountType': accountType,
        'accountNo': accountNo,
      },
    );
    return MerchantWithdrawalRecord.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }

  Future<List<MerchantSettlementDetail>> listSettlementDetails({
    String? merchantId,
  }) async {
    final data = await _client.get(
      '/merchant/wallet/settlements',
      query: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    final list = (data as List? ?? const []);
    return list
        .map((e) => MerchantSettlementDetail.fromJson(
            (e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<MerchantHygieneStats> getHygieneStats({String? merchantId}) async {
    final data = await _client.get(
      '/merchant/hygiene-stats',
      query: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    return MerchantHygieneStats.fromJson(
      (data as Map).cast<String, dynamic>(),
    );
  }

  Future<List<dynamic>> getMealLabelPrintStatus({
    required String businessDate,
    required String mealType,
    String? merchantId,
  }) async {
    final data = await _client.get(
      '/merchant/meal-labels/print-status',
      query: {
        'businessDate': businessDate,
        'mealType': mealType,
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    final map = (data as Map?)?.cast<String, dynamic>() ?? {};
    return (map['items'] as List?) ?? const [];
  }

  Future<void> markMealLabelsPrinted({
    required String businessDate,
    required String mealType,
    required List<Map<String, String>> labels,
    String? merchantId,
  }) async {
    await _client.post(
      '/merchant/meal-labels/mark-printed',
      body: {
        'businessDate': businessDate,
        'mealType': mealType,
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
        'labels': labels,
      },
    );
  }
}

Merchant merchantFromJson(Map<String, dynamic> j) {
  final mealHoursRaw = j['mealOpeningHours'];
  final mealHours = <String, MealHoursSetting>{};
  if (mealHoursRaw is Map) {
    mealHoursRaw.forEach((key, value) {
      mealHours[key.toString()] = MealHoursSetting.fromJson(value);
    });
  }
  // 商家自定义订餐截止时间；老接口缺省时为空对象，由前端在使用时回退到全局默认。
  final deadlinesRaw = j['mealOrderDeadlines'];
  final mealOrderDeadlines = <String, String>{};
  if (deadlinesRaw is Map) {
    deadlinesRaw.forEach((key, value) {
      if (value is String && value.trim().isNotEmpty) {
        mealOrderDeadlines[key.toString()] = value.trim();
      }
    });
  }
  return Merchant(
    id: j['id'].toString(),
    name: j['name'].toString(),
    logo: (j['logo'] ?? 'logo').toString(),
    coverImage: (j['coverImage'] ?? 'cover').toString(),
    distance: (j['distance'] as num?)?.toInt() ?? 0,
    rating: (j['rating'] as num?)?.toDouble() ?? 0,
    monthSold: (j['monthSold'] as num?)?.toInt() ?? 0,
    hygieneGrade: (j['hygieneGrade'] ?? 'A').toString(),
    isOpen: (j['isOpen'] as bool?) ?? true,
    address: (j['address'] ?? '').toString(),
    paymentQrCode: (j['paymentQrCode'] ?? 'qr').toString(),
    wechatPaymentQrUrl: (j['wechatPaymentQrUrl'] ?? '').toString(),
    alipayPaymentQrUrl: (j['alipayPaymentQrUrl'] ?? '').toString(),
    deliveryFee: (j['deliveryFee'] as num?)?.toDouble() ?? 0,
    contactName: (j['contactName'] ?? '').toString(),
    contactPhone: (j['contactPhone'] ?? '').toString(),
    description: (j['description'] ?? '').toString(),
    deliveryModes: (j['deliveryModes'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    deliveryScope: (j['deliveryScope'] ?? '').toString(),
    estimatedDeliveryTime: (j['estimatedDeliveryTime'] ?? '').toString(),
    supportedMealTypes: (j['supportedMealTypes'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    mealOpeningHours: mealHours,
    mealOrderDeadlines: mealOrderDeadlines,
  );
}

Map<String, dynamic> merchantToJsonMap(Merchant m) => {
      'id': m.id,
      'name': m.name,
      'logo': m.logo,
      'coverImage': m.coverImage,
      'distance': m.distance,
      'rating': m.rating,
      'monthSold': m.monthSold,
      'hygieneGrade': m.hygieneGrade,
      'isOpen': m.isOpen,
      'address': m.address,
      'paymentQrCode': m.paymentQrCode,
      'deliveryFee': m.deliveryFee,
      'contactName': m.contactName,
      'contactPhone': m.contactPhone,
      'description': m.description,
      'deliveryModes': m.deliveryModes,
      'deliveryScope': m.deliveryScope,
      'estimatedDeliveryTime': m.estimatedDeliveryTime,
      'supportedMealTypes': m.supportedMealTypes,
      'mealOpeningHours':
          m.mealOpeningHours.map((k, v) => MapEntry(k, v.toJson())),
      'mealOrderDeadlines': m.mealOrderDeadlines,
    };
