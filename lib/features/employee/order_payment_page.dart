import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/merchant_api.dart';
import '../../api/order_api.dart';
import '../../api/payment_api.dart';
import '../../api/runtime_config_api.dart';
import '../../models/merchant_model.dart';
import '../../models/order_model.dart';
import '../../models/payment_config.dart';
import '../../models/user_model.dart';
import '../../state/app_state.dart';
import '../../state/merchant_state.dart';
import '../../state/order_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/payment_screenshot_pick.dart';
import '../../widgets/app_button.dart';
import '../../widgets/qr_placeholder.dart';
import '../../widgets/section_card.dart';
import 'employee_shell.dart';

/// 个人支付 / 混合支付：上传付款截图并提交商家确认
class OrderPaymentPage extends StatefulWidget {
  final Order order;

  const OrderPaymentPage({super.key, required this.order});

  @override
  State<OrderPaymentPage> createState() => _OrderPaymentPageState();
}

class _OrderPaymentPageState extends State<OrderPaymentPage> {
  Uint8List? _imageBytes;
  String? _imageFilename;
  bool _submitting = false;
  bool _uploaded = false;
  bool _loadingConfig = true;
  String _channel = 'manual_qr';
  String _manualQrPayChannel = 'wechat';
  PaymentConfig _paymentConfig = PaymentConfig.defaults;
  Merchant? _merchant;
  bool _loadingMerchant = true;

  Order get order => widget.order;

  bool get _zeroEmployeePay => order.employeePayAmount <= 0;

  @override
  void initState() {
    super.initState();
    _loadPaymentConfig();
    _loadMerchant();
  }

  Future<void> _loadMerchant() async {
    try {
      final merchantState = context.read<MerchantState>();
      Merchant? found;
      for (final m in merchantState.nearbyMerchants) {
        if (m.id == order.merchantId) {
          found = m;
          break;
        }
      }
      found ??= await MerchantApi(context.read<ApiClient>())
          .getNearbyMerchants()
          .then((list) {
        for (final m in list) {
          if (m.id == order.merchantId) return m;
        }
        return null;
      });
      if (!mounted) return;
      setState(() {
        _merchant = found;
        _loadingMerchant = false;
        if (found != null) {
          if (found.effectiveWechatPaymentQr.isNotEmpty) {
            _manualQrPayChannel = 'wechat';
          } else if (found.effectiveAlipayPaymentQr.isNotEmpty) {
            _manualQrPayChannel = 'alipay';
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMerchant = false);
    }
  }

  Future<void> _loadPaymentConfig() async {
    try {
      final api = RuntimeConfigApi(context.read<ApiClient>());
      final cfg = await api.fetchPaymentConfig();
      if (!mounted) return;
      setState(() {
        _paymentConfig = cfg;
        _channel = _defaultChannel(cfg);
        _loadingConfig = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  String _defaultChannel(PaymentConfig cfg) {
    if (cfg.manualQrAvailable) return 'manual_qr';
    if (cfg.wechatAvailable) return 'wechat_pay';
    if (cfg.alipayAvailable) return 'alipay';
    return 'manual_qr';
  }

  Future<void> _onPickScreenshot() async {
    if (_submitting || _uploaded) return;
    final picked = await pickPaymentScreenshot(context);
    if (picked == null || !mounted) return;
    setState(() {
      _imageBytes = picked.bytes;
      _imageFilename = picked.filename;
    });
  }

  String _uploadErrorMessage(Object e) {
    if (e is ApiException) {
      debugPrint(
        '[OrderPaymentPage] upload failed '
        'statusCode=${e.code} errorCode=${e.errorCode} message=${e.message}',
      );
      switch (e.errorCode) {
        case 'PAYMENT_UPLOAD_NOT_ALLOWED':
          return '当前订单状态不允许上传付款截图';
        case 'COMPANY_PAY_NO_SCREENSHOT':
          return '企业代付订单无需上传付款截图';
        case 'MANUAL_PAY_CHANNEL_REQUIRED':
          return '请选择微信或支付宝收款码';
        case 'ORDER_ID_REQUIRED':
          return '订单信息异常，请返回重新下单';
        case 'UPLOAD_TYPE_FORBIDDEN':
        case 'UPLOAD_FAILED':
          return e.message.contains('MIME') || e.message.contains('类型')
              ? '图片格式不支持，请使用 jpg / png / webp'
              : (e.message.contains('10MB') || e.message.contains('过大')
                  ? '图片超过大小限制（最大 10MB）'
                  : e.message);
        case 'UPLOAD_FILE_REQUIRED':
          return '请先选择付款截图';
      }
      if (e.code == 401) return '登录已失效，请重新登录';
      if (e.code == 403) return '仅下单人可上传付款截图';
      if (e.code == 404) return '订单不存在';
      if (e.message.isNotEmpty) return e.message;
    } else {
      debugPrint('[OrderPaymentPage] upload failed: $e');
    }
    return '上传失败，请重新选择或稍后再试';
  }

  Future<void> _onSubmit() async {
    if (_zeroEmployeePay) {
      setState(() => _submitting = true);
      try {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('订单已提交，等待商家确认')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const EmployeeShell(initialIndex: 1)),
          (route) => route.isFirst,
        );
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
      return;
    }

    if (_channel == 'manual_qr') {
      if (_manualQrQrUrl.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('商家暂未上传该收款码，请选择其他方式或联系商家'),
          ),
        );
        return;
      }
      if (_imageBytes == null || _imageFilename == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择付款截图')),
        );
        return;
      }
      if (order.id.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('订单信息异常，请返回重新下单')),
        );
        return;
      }
      if (_manualQrPayChannel != 'wechat' && _manualQrPayChannel != 'alipay') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择微信或支付宝收款码')),
        );
        return;
      }
      if (_uploaded) return;
    }

    if ((_channel == 'wechat_pay' || _channel == 'alipay') &&
        !_isChannelAvailable(_channel)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_hintForChannel(_channel))),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final orderApi = OrderApi(context.read<ApiClient>());
      final paymentApi = PaymentApi(context.read<ApiClient>());

      if (_channel == 'wechat_pay' || _channel == 'alipay') {
        final created = await paymentApi.create(
          orderId: order.id,
          channel: _channel,
        );
        final mode = created.payParams['mode'] as String? ?? '';
        if (mode == 'disabled') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                created.payParams['hint'] as String? ?? '暂未开通，请使用付款截图',
              ),
            ),
          );
          return;
        }
        if (mode == 'mock' && !AppConfig.isProduction) {
          await paymentApi.mockPaid(paymentId: created.paymentId);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('支付成功，平台已收款，等待商家确认'),
            ),
          );
        } else if (mode == 'wechat' || mode == 'alipay') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请在微信/支付宝中完成支付（SDK 待接入）')),
          );
          return;
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('在线支付暂未开通，请使用付款截图')),
          );
          return;
        }
      } else {
        await orderApi.uploadPaymentScreenshot(
          orderId: order.id,
          imageBytes: _imageBytes!,
          filename: _imageFilename!,
          manualPayChannel: _manualQrPayChannel,
        );
        final user = context.read<AppState>().currentUser;
        if (user != null) {
          await context.read<OrderState>().refreshForRole(
                role: UserRole.employee,
                userId: user.id,
              );
        }
        if (!mounted) return;
        setState(() => _uploaded = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('付款凭证已上传，等待商家确认')),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const EmployeeShell(initialIndex: 1)),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _channel == 'manual_qr'
                ? _uploadErrorMessage(e)
                : '提交失败：${_uploadErrorMessage(e)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _isChannelAvailable(String channel) {
    if (channel == 'wechat_pay') return _paymentConfig.wechatAvailable;
    if (channel == 'alipay') return _paymentConfig.alipayAvailable;
    return _paymentConfig.manualQrAvailable;
  }

  String _hintForChannel(String channel) {
    if (channel == 'wechat_pay') return _paymentConfig.wechatHint;
    if (channel == 'alipay') return _paymentConfig.alipayHint;
    return _paymentConfig.manualQrHint;
  }

  String get _manualQrQrUrl {
    final m = _merchant;
    if (m == null) return '';
    if (_manualQrPayChannel == 'wechat') return m.effectiveWechatPaymentQr;
    return m.effectiveAlipayPaymentQr;
  }

  Widget _buildManualQrPaySelector() {
    final m = _merchant;
    final wechatOk = m != null && m.effectiveWechatPaymentQr.isNotEmpty;
    final alipayOk = m != null && m.effectiveAlipayPaymentQr.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('扫码付款方式', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(wechatOk ? '微信' : '微信（未上传）'),
              selected: _manualQrPayChannel == 'wechat',
              onSelected: wechatOk && !_submitting
                  ? (_) => setState(() => _manualQrPayChannel = 'wechat')
                  : null,
            ),
            ChoiceChip(
              label: Text(alipayOk ? '支付宝' : '支付宝（未上传）'),
              selected: _manualQrPayChannel == 'alipay',
              onSelected: alipayOk && !_submitting
                  ? (_) => setState(() => _manualQrPayChannel = 'alipay')
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('商家收款码', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_loadingMerchant)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else if (_manualQrQrUrl.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Text(
              '商家暂未上传该收款码，请选择其他付款方式或联系商家',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          )
        else
          Center(child: QrPlaceholder(seed: _manualQrQrUrl, size: 180)),
      ],
    );
  }

  Widget _buildChannelChip({
    required String label,
    required String channel,
    required bool available,
    required String disabledHint,
  }) {
    if (available) {
      return ChoiceChip(
        label: Text(label),
        selected: _channel == channel,
        onSelected: _submitting
            ? null
            : (_) => setState(() => _channel = channel),
      );
    }
    return InputChip(
      label: Text('$label（暂未开通）'),
      avatar: Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
      onPressed: _submitting
          ? null
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(disabledHint)),
              );
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final payAmount = order.employeePayAmount > 0
        ? order.employeePayAmount
        : order.displayAmount;
    final orderTotal = order.finalAmount > 0 ? order.finalAmount : order.totalAmount;

    return Scaffold(
      appBar: AppBar(
        title: Text(_zeroEmployeePay ? '确认提交订单' : '上传付款凭证'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.merchantName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '订单总额：¥${orderTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_zeroEmployeePay) ...[
                  const SizedBox(height: 8),
                  Text(
                    order.couponDiscountAmount > 0
                        ? '优惠券已抵扣，无需付款'
                        : '本单由企业代付，无需付款',
                    style: const TextStyle(
                      fontSize: 18,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (order.companyPayAmount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '企业代付：¥${order.companyPayAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (order.couponDiscountAmount > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '优惠券抵扣：-¥${order.couponDiscountAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  const Text(
                    '您需支付：¥0.00',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '无需付款，提交后等待商家确认',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primary.withValues(alpha: 0.85),
                    ),
                  ),
                ] else ...[
                  if (order.companyPayAmount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '企业代付：¥${order.companyPayAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                  if (order.couponDiscountAmount > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '优惠券抵扣：-¥${order.couponDiscountAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '您需支付：¥${order.employeePayAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_zeroEmployeePay) ...[
            const SizedBox(height: 16),
            const Text(
              '支付方式',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (_loadingConfig) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ] else ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChannelChip(
                    label: '微信支付',
                    channel: 'wechat_pay',
                    available: _paymentConfig.wechatAvailable,
                    disabledHint: _paymentConfig.wechatHint,
                  ),
                  _buildChannelChip(
                    label: '支付宝',
                    channel: 'alipay',
                    available: _paymentConfig.alipayAvailable,
                    disabledHint: _paymentConfig.alipayHint,
                  ),
                  if (_paymentConfig.manualQrAvailable)
                    ChoiceChip(
                      label: const Text('付款截图'),
                      selected: _channel == 'manual_qr',
                      onSelected: _submitting
                          ? null
                          : (_) => setState(() => _channel = 'manual_qr'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _paymentConfig.wechatAvailable || _paymentConfig.alipayAvailable
                    ? '支持在线支付；如无法在线支付，可使用付款截图备用。'
                    : '当前暂未开通微信/支付宝线上支付，请使用付款截图完成支付。',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            if (_channel == 'manual_qr') ...[
              const SizedBox(height: 16),
              _buildManualQrPaySelector(),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: (_submitting || _uploaded) ? null : _onPickScreenshot,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _uploaded
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.check_circle,
                                  color: AppColors.primary, size: 32),
                              SizedBox(height: 8),
                              Text(
                                '付款凭证已上传，等待商家确认',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _imageBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  _imageBytes!,
                                  fit: BoxFit.cover,
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    color: Colors.black54,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 12),
                                    child: const Text(
                                      '已选择付款截图，点击提交上传',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.cloud_upload_outlined,
                                      color: AppColors.primary, size: 32),
                                  SizedBox(height: 8),
                                  Text(
                                    '点击上传付款截图',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          PrimaryActionButton(
            label: _submitting
                ? '提交中…'
                : (_zeroEmployeePay
                    ? '提交订单'
                    : (_uploaded
                        ? '已提交'
                        : (_channel == 'manual_qr'
                            ? '提交支付凭证'
                            : '立即支付'))),
            onPressed: (_submitting || _loadingConfig || _uploaded)
                ? null
                : _onSubmit,
          ),
        ],
      ),
    );
  }
}
