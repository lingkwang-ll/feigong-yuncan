import 'api_client.dart';

class PaymentApi {
  PaymentApi(this._client);
  final ApiClient _client;

  Future<PaymentCreateResult> create({
    required String orderId,
    required String channel,
  }) async {
    final data = await _client.post(
      '/payments/create',
      body: {'orderId': orderId, 'channel': channel},
    );
    return PaymentCreateResult.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<void> mockPaid({required String paymentId, double? amount}) async {
    await _client.post(
      '/payments/mock-paid',
      body: {
        'paymentId': paymentId,
        if (amount != null) 'amount': amount,
      },
    );
  }
}

class PaymentCreateResult {
  final String paymentId;
  final String paymentNo;
  final String channel;
  final double amount;
  final String status;
  final Map<String, dynamic> payParams;

  const PaymentCreateResult({
    required this.paymentId,
    required this.paymentNo,
    required this.channel,
    required this.amount,
    required this.status,
    required this.payParams,
  });

  factory PaymentCreateResult.fromJson(Map<String, dynamic> json) =>
      PaymentCreateResult(
        paymentId: (json['paymentId'] as String?) ?? '',
        paymentNo: (json['paymentNo'] as String?) ?? '',
        channel: (json['channel'] as String?) ?? '',
        amount: ((json['amount'] as num?) ?? 0).toDouble(),
        status: (json['status'] as String?) ?? '',
        payParams: ((json['payParams'] as Map?) ?? const {})
            .cast<String, dynamic>(),
      );
}

class MerchantWalletSummary {
  final double withdrawableAmount;
  final double pendingSettlementAmount;
  final double withdrawingAmount;
  final double withdrawnAmount;
  final String settlementRuleText;

  const MerchantWalletSummary({
    required this.withdrawableAmount,
    required this.pendingSettlementAmount,
    required this.withdrawingAmount,
    required this.withdrawnAmount,
    required this.settlementRuleText,
  });

  factory MerchantWalletSummary.fromJson(Map<String, dynamic> json) =>
      MerchantWalletSummary(
        withdrawableAmount:
            ((json['withdrawableAmount'] as num?) ?? 0).toDouble(),
        pendingSettlementAmount:
            ((json['pendingSettlementAmount'] as num?) ?? 0).toDouble(),
        withdrawingAmount:
            ((json['withdrawingAmount'] as num?) ?? 0).toDouble(),
        withdrawnAmount: ((json['withdrawnAmount'] as num?) ?? 0).toDouble(),
        settlementRuleText:
            (json['settlementRuleText'] as String?) ?? '订单完成满7天后可提现',
      );
}

class MerchantWithdrawalRecord {
  final String id;
  final double amount;
  final String status;
  final String accountName;
  final String accountType;
  final String accountNo;
  final String? remark;
  final String createdAt;
  final String? reviewedAt;

  const MerchantWithdrawalRecord({
    required this.id,
    required this.amount,
    required this.status,
    required this.accountName,
    required this.accountType,
    required this.accountNo,
    this.remark,
    required this.createdAt,
    this.reviewedAt,
  });

  factory MerchantWithdrawalRecord.fromJson(Map<String, dynamic> json) =>
      MerchantWithdrawalRecord(
        id: (json['id'] as String?) ?? '',
        amount: ((json['amount'] as num?) ?? 0).toDouble(),
        status: (json['status'] as String?) ?? 'pending',
        accountName: (json['accountName'] as String?) ?? '',
        accountType: (json['accountType'] as String?) ?? '',
        accountNo: (json['accountNo'] as String?) ?? '',
        remark: json['remark'] as String?,
        createdAt: (json['createdAt'] as String?) ?? '',
        reviewedAt: json['reviewedAt'] as String?,
      );

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '待审核';
      case 'approved':
        return '已通过';
      case 'paid':
        return '已打款';
      case 'rejected':
        return '已驳回';
      default:
        return status;
    }
  }
}

class MerchantSettlementDetail {
  final String orderId;
  final String orderNo;
  final String? completedAt;
  final String status;
  final String? settlementEligibleAt;
  final double orderAmount;
  final double merchantReceivableAmount;

  const MerchantSettlementDetail({
    required this.orderId,
    required this.orderNo,
    this.completedAt,
    required this.status,
    this.settlementEligibleAt,
    required this.orderAmount,
    required this.merchantReceivableAmount,
  });

  factory MerchantSettlementDetail.fromJson(Map<String, dynamic> json) =>
      MerchantSettlementDetail(
        orderId: (json['orderId'] as String?) ?? '',
        orderNo: (json['orderNo'] as String?) ?? '',
        completedAt: json['completedAt'] as String?,
        status: (json['status'] as String?) ?? '',
        settlementEligibleAt: json['settlementEligibleAt'] as String?,
        orderAmount: ((json['orderAmount'] as num?) ?? 0).toDouble(),
        merchantReceivableAmount:
            ((json['merchantReceivableAmount'] as num?) ?? 0).toDouble(),
      );

  String get statusLabel {
    switch (status) {
      case 'pending':
        return '结算期内';
      case 'eligible':
        return '待平台结算';
      case 'settled':
        return '已结算';
      case 'blocked':
        return '冻结';
      default:
        return status;
    }
  }
}

class MerchantHygieneStats {
  final String hygieneGrade;
  final double? hygieneScore;
  final double? hygieneScore30d;
  final int reviewCount;
  final double? overallRating;
  final String riskStatus;
  final bool needsRemediation;
  final String gradeLabel;

  const MerchantHygieneStats({
    required this.hygieneGrade,
    this.hygieneScore,
    this.hygieneScore30d,
    required this.reviewCount,
    this.overallRating,
    required this.riskStatus,
    required this.needsRemediation,
    required this.gradeLabel,
  });

  bool get hasEnoughReviews => reviewCount >= 5;

  factory MerchantHygieneStats.fromJson(Map<String, dynamic> json) =>
      MerchantHygieneStats(
        hygieneGrade: (json['hygieneGrade'] as String?) ?? '—',
        hygieneScore: (json['hygieneScore'] as num?)?.toDouble(),
        hygieneScore30d: (json['hygieneScore30d'] as num?)?.toDouble(),
        reviewCount: ((json['reviewCount'] as num?) ?? 0).toInt(),
        overallRating: (json['overallRating'] as num?)?.toDouble(),
        riskStatus: (json['riskStatus'] as String?) ?? 'normal',
        needsRemediation: json['needsRemediation'] == true,
        gradeLabel: (json['gradeLabel'] as String?) ?? '',
      );
}
