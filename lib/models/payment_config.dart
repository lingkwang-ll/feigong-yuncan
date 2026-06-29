class OnlinePaymentEnabled {
  final bool wechat;
  final bool alipay;
  final bool manualQr;

  const OnlinePaymentEnabled({
    required this.wechat,
    required this.alipay,
    required this.manualQr,
  });

  factory OnlinePaymentEnabled.fromJson(Map<String, dynamic>? json) {
    final m = json ?? const {};
    return OnlinePaymentEnabled(
      wechat: m['wechat'] == true,
      alipay: m['alipay'] == true,
      manualQr: m['manualQr'] != false,
    );
  }

  static const defaults = OnlinePaymentEnabled(
    wechat: false,
    alipay: false,
    manualQr: true,
  );
}

class PaymentConfig {
  final OnlinePaymentEnabled onlinePaymentEnabled;
  final bool wechatAvailable;
  final bool alipayAvailable;
  final bool manualQrAvailable;
  final String wechatHint;
  final String alipayHint;
  final String manualQrHint;

  const PaymentConfig({
    required this.onlinePaymentEnabled,
    required this.wechatAvailable,
    required this.alipayAvailable,
    required this.manualQrAvailable,
    required this.wechatHint,
    required this.alipayHint,
    required this.manualQrHint,
  });

  factory PaymentConfig.fromJson(Map<String, dynamic> json) {
    final hints = (json['hints'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PaymentConfig(
      onlinePaymentEnabled: OnlinePaymentEnabled.fromJson(
        (json['onlinePaymentEnabled'] as Map?)?.cast<String, dynamic>(),
      ),
      wechatAvailable: json['wechatAvailable'] == true,
      alipayAvailable: json['alipayAvailable'] == true,
      manualQrAvailable: json['manualQrAvailable'] != false,
      wechatHint: (hints['wechat'] as String?) ?? '暂未开通，请使用付款截图',
      alipayHint: (hints['alipay'] as String?) ?? '暂未开通，请使用付款截图',
      manualQrHint: (hints['manualQr'] as String?) ?? '上传付款截图，商家确认后订单生效',
    );
  }

  static const defaults = PaymentConfig(
    onlinePaymentEnabled: OnlinePaymentEnabled.defaults,
    wechatAvailable: false,
    alipayAvailable: false,
    manualQrAvailable: true,
    wechatHint: '暂未开通，请使用付款截图',
    alipayHint: '暂未开通，请使用付款截图',
    manualQrHint: '上传付款截图，商家确认后订单生效',
  );
}
