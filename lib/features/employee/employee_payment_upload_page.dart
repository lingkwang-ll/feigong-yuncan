// 已废弃，主流程使用 OrderPaymentPage（lib/features/employee/order_payment_page.dart）。
// 本文件保留仅供 UI 参考，无任何路由 / import / 按钮入口会进入此页。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order_model.dart';
import '../../state/app_state.dart';
import '../../state/cart_state.dart';
import '../../state/merchant_state.dart';
import '../../state/order_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/employee_info_helper.dart';
import '../../utils/trial_run_policy.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/qr_placeholder.dart';
import '../../widgets/section_card.dart';
import 'employee_shell.dart';

/// 员工端付款截图上传页（已废弃）
///
/// 主流程请使用 [OrderPaymentPage]。
/// 参考 UI：04_employee_payment_upload.png
class EmployeePaymentUploadPage extends StatefulWidget {
  final DeliveryType deliveryType;
  final String address;
  final String phone;
  final String remark;
  final bool isMealCollector;
  final String collectorPhone;
  final String collectorAddress;
  final double? collectorLatitude;
  final double? collectorLongitude;
  final String collectorPoiName;
  final String collectorAddressText;
  final double goodsAmount;
  final double deliveryFee;
  final double totalAmount;

  const EmployeePaymentUploadPage({
    super.key,
    required this.deliveryType,
    required this.address,
    required this.phone,
    required this.remark,
    this.isMealCollector = false,
    this.collectorPhone = '',
    this.collectorAddress = '',
    this.collectorLatitude,
    this.collectorLongitude,
    this.collectorPoiName = '',
    this.collectorAddressText = '',
    required this.goodsAmount,
    required this.deliveryFee,
    required this.totalAmount,
  });

  @override
  State<EmployeePaymentUploadPage> createState() =>
      _EmployeePaymentUploadPageState();
}

class _EmployeePaymentUploadPageState
    extends State<EmployeePaymentUploadPage> {
  /// 已选截图的本地占位标识（路径或 base64）
  String? _screenshotKey;
  bool get _uploaded => _screenshotKey != null;

  void _onPickScreenshot() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('此页面已废弃，付款截图请使用 OrderPaymentPage'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onSubmit() async {
    final cart = context.read<CartState>();
    final orderState = context.read<OrderState>();
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (cart.isEmpty || cart.merchant == null) return;

    // 按购物车归属商家的截止时间判断；商家未配置时回退全局默认。
    final hasClosedMeal = cart.items.any(
      (i) => MealOrderDeadline.isClosedFor(
        i.dish.mealType,
        merchant: cart.merchant,
      ),
    );
    if (hasClosedMeal) {
      messenger.showSnackBar(
        const SnackBar(content: Text(MealOrderDeadline.deadlineHint)),
      );
      return;
    }

    final user = appState.currentUser;
    final info = EmployeeInfoHelper.resolve(
      user: user,
      phone: user?.phone,
      address: widget.collectorAddress,
    );
    final customerName = info.name;
    final customerCompany = info.department;
    final collectorName =
        widget.isMealCollector ? customerName : '';

    // 本地占位订单 id；api 模式下会被后端返回的真实 id 覆盖
    final localOrderId =
        'O${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';

    final order = Order(
      id: localOrderId,
      merchantId: cart.merchant!.id,
      merchantName: cart.merchant!.name,
      customerName: customerName,
      customerCompany: customerCompany,
      items: List.of(cart.items),
      deliveryType: widget.deliveryType,
      address: widget.address,
      phone: widget.phone,
      remark: widget.remark,
      goodsAmount: widget.goodsAmount,
      deliveryFee: widget.deliveryFee,
      totalAmount: widget.totalAmount,
      status: OrderStatus.pendingMerchantConfirm,
      paymentScreenshot: null,
      createdAt: DateTime.now(),
      isMealCollector: widget.isMealCollector,
      collectorName: collectorName,
      collectorPhone: widget.collectorPhone,
      collectorAddress: widget.collectorAddress,
      collectorLatitude: widget.collectorLatitude,
      collectorLongitude: widget.collectorLongitude,
      collectorPoiName: widget.collectorPoiName,
      collectorAddressText: widget.collectorAddressText,
    );

    // 先创建订单，拿到真实 id；再用真实 id 上传付款截图。
    await orderState.addOrder(order, userId: user?.id);

    // 已废弃：付款截图上传已迁移至 OrderPaymentPage，此处不再上传。
    cart.clear();

    if (!mounted) return;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const EmployeeShell(initialIndex: 1),
      ),
      (route) => false,
    );

    messenger.showSnackBar(
      const SnackBar(
        content: Text('订单已提交，等待商家确认收款'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();
    final merchantState = context.watch<MerchantState>();
    final merchant = cart.merchant;
    final merchantName = merchant?.name ?? '商家';
    // 当前 Mock 环境下只有一个商家账户（绿健食堂），
    // 因此员工付款页统一展示该商家持久化的收款码 seed。
    // 如果未来扩展到多商家，可以改成根据 merchant.id 查询对应收款码。
    final qrSeed = merchantState.currentQrSeed;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '付款给商家',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    MerchantBadgeLogo(
                        seed: merchant?.logo ?? '',
                        size: 44,
                        radius: 12),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            merchantName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('请使用微信或支付宝扫码付款',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('订单金额',
                        style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    Text(
                      '¥${widget.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.accent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前暂未开通微信/支付宝线上支付，采用商家收款码转账 + '
                    '上传付款截图的方式，商家确认后订单生效。'
                    '如需退款，请联系商家或平台管理员处理。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: Column(
              children: [
                const Text(
                  '请扫码付款后上传截图',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                QrPlaceholder(seed: qrSeed),
                const SizedBox(height: 14),
                const Text('支持微信 / 支付宝扫码付款',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '上传付款截图',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _onPickScreenshot,
                  child: DottedBox(
                    height: 110,
                    child: _uploaded
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.check_circle,
                                  color: AppColors.primary, size: 28),
                              SizedBox(width: 8),
                              Text(
                                '已选择截图，点击可重新选择',
                                style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 14),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cloud_upload_outlined,
                                      color: AppColors.primary, size: 28),
                                  SizedBox(width: 8),
                                  Text(
                                    '点击上传付款截图',
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '请确保截图包含付款金额和支付成功信息',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: PrimaryActionButton(
            label: '提交订单',
            onPressed: _onSubmit,
          ),
        ),
      ),
    );
  }
}

/// 虚线边框容器（参考 04_employee_payment_upload.png 的"点击上传付款截图"区域）
class DottedBox extends StatelessWidget {
  final double height;
  final Widget child;
  const DottedBox({super.key, required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: AppColors.primary.withValues(alpha: 0.55),
        radius: AppRadius.md,
        dash: 6,
        gap: 4,
        strokeWidth: 1.2,
      ),
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      double distance = 0;
      while (distance < m.length) {
        final next = distance + dash;
        canvas.drawPath(
          m.extractPath(distance, next.clamp(0, m.length).toDouble()),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap ||
      oldDelegate.strokeWidth != strokeWidth;
}
