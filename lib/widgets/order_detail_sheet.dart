import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/display_text_util.dart';
import '../utils/order_time_util.dart';

import '../models/dish_review_model.dart';
import '../models/order_model.dart';
import '../state/merchant_state.dart';
import '../theme/app_theme.dart';
import '../utils/delivery_location_helper.dart';
import '../utils/employee_info_helper.dart';
import '../api/api_client.dart';
import '../api/api_config.dart';
import '../features/chat/order_conversation_page.dart';
import '../widgets/merchant_order_chat_action.dart';
import '../features/map/delivery_tracking_page.dart';
import 'app_button.dart';
import 'app_logo.dart';
import 'delivery_location_card.dart';
import 'order_detail_helpers.dart';
import 'dish_card.dart';
import 'star_rating_bar.dart';

/// 通用订单详情 BottomSheet 内容
///
/// 员工端"我的订单"和商家端"订单管理"都可复用。
class OrderDetailSheet extends StatelessWidget {
  final Order order;
  final bool showCustomerInfo;
  final List<Widget> actions;
  final bool showReviewFeatures;
  final List<DishReview>? orderReviews;
  final void Function(String dishId, String dishName)? onDishTapForHistory;
  final bool showMerchantReviewButton;
  final void Function(String dishId, String dishName)? onViewDishReviews;

  const OrderDetailSheet({
    super.key,
    required this.order,
    this.showCustomerInfo = false,
    this.actions = const [],
    this.showReviewFeatures = false,
    this.orderReviews,
    this.onDishTapForHistory,
    this.showMerchantReviewButton = false,
    this.onViewDishReviews,
  });

  static Future<void> show(
    BuildContext context, {
    required Order order,
    bool showCustomerInfo = false,
    List<Widget> actions = const [],
    bool showReviewFeatures = false,
    List<DishReview>? orderReviews,
    void Function(String dishId, String dishName)? onDishTapForHistory,
    bool showMerchantReviewButton = false,
    void Function(String dishId, String dishName)? onViewDishReviews,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scroll) => OrderDetailSheet(
          order: order,
          showCustomerInfo: showCustomerInfo,
          actions: actions,
          showReviewFeatures: showReviewFeatures,
          orderReviews: orderReviews,
          onDishTapForHistory: onDishTapForHistory,
          showMerchantReviewButton: showMerchantReviewButton,
          onViewDishReviews: onViewDishReviews,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Text(
                '订单详情',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _StatusChip(status: order.status),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _MerchantHeader(order: order),
              const SizedBox(height: 14),
              DeliveryLocationCard(order: order),
              if (canTrackDelivery(order)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlineAccentButton(
                    label: '查看配送位置',
                    onPressed: () =>
                        DeliveryTrackingPage.open(context, order),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (showCustomerInfo)
                MerchantOrderChatAction(
                  order: order,
                  unreadCount: MerchantOrderChatAction.unreadOf(context, order.id),
                )
              else
                _ContactButton(
                  order: order,
                  asMerchant: false,
                ),
              const SizedBox(height: 14),
              _SectionTitle(title: '订单号'),
              _kv('订单号', order.displayOrderNo),
              _kv('下单时间', OrderTimeUtil.formatDisplay(order.createdAt)),
              if (order.status == OrderStatus.cancelled &&
                  order.rejectReason != null &&
                  order.rejectReason!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionTitle(title: '拒单原因'),
                _kv('原因', order.rejectReason!),
              ],
              if (showCustomerInfo) ...[
                const SizedBox(height: 12),
                _SectionTitle(title: '客户信息'),
                _kv('客户公司', order.customerCompany),
                _kv('联系人', order.customerName),
                _kv('手机号', order.phone),
              ],
              if (order.isPackageOrder) ...[
                const SizedBox(height: 12),
                _SectionTitle(title: '套餐信息'),
                _PackageInfoBlock(order: order),
              ],
              if (!order.isPackageOrder) ...[
                const SizedBox(height: 12),
                _SectionTitle(title: '点餐明细'),
                const SizedBox(height: 4),
                ...order.items.map(
                  (item) {
                    DishReview? review;
                    if (showReviewFeatures && orderReviews != null) {
                      for (final r in orderReviews!) {
                        if (r.dishId == item.dish.id) {
                          review = r;
                          break;
                        }
                      }
                    }
                    final row = Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        DishImagePlaceholder(
                          seed: item.dish.id,
                          size: 50,
                          imageUrl: item.dish.image,
                          dishName: item.dish.name,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                resolveDisplayDishName(item.dish.name),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '¥${item.dish.price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (review != null) ...[
                                const SizedBox(height: 4),
                                StarRatingBar(
                                  rating: review.rating,
                                  readOnly: true,
                                  size: 16,
                                ),
                                if (review.comment.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      review.comment,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          'x${item.quantity}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (showMerchantReviewButton &&
                            order.status == OrderStatus.completed &&
                            onViewDishReviews != null) ...[
                          const SizedBox(width: 6),
                          OutlineAccentButton(
                            label: '查看评价',
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            onPressed: () => onViewDishReviews!(
                              item.dish.id,
                              item.dish.name,
                            ),
                          ),
                        ],
                        if (showReviewFeatures &&
                            onDishTapForHistory != null) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ],
                    );
                    if (showReviewFeatures && onDishTapForHistory != null) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => onDishTapForHistory!(
                              item.dish.id,
                              item.dish.name,
                            ),
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 2),
                              child: row,
                            ),
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: row,
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              _SectionTitle(title: '配送信息'),
              _kv('配送方式', order.deliveryType.label),
              if (order.deliveryType == DeliveryType.delivery) ...[
                ...DeliveryLocationHelper.merchantAddressLines(order)
                    .asMap()
                    .entries
                    .map(
                      (e) => e.key == 0
                          ? _kv('收货地址', e.value)
                          : Padding(
                              padding: const EdgeInsets.only(left: 70, bottom: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                    ),
              ],
              _kv('联系电话', order.phone),
              _kv('备注', order.remark.isEmpty ? '无' : order.remark),
              const SizedBox(height: 12),
              const SizedBox(height: 12),
              _SectionTitle(title: '付款信息'),
              _kv('订单总额', '¥${order.totalAmount.toStringAsFixed(2)}'),
              if (order.companyPayAmount > 0)
                _kv('企业支付', '¥${order.companyPayAmount.toStringAsFixed(2)}'),
              if (order.employeePayAmount > 0)
                _kv('员工支付', '¥${order.employeePayAmount.toStringAsFixed(2)}'),
              _kv('支付方式', order.paymentType.label),
              if (order.employeePayAmount > 0 &&
                  (order.manualPayChannel ?? '').isNotEmpty)
                _kv(
                  '付款方式',
                  manualPayChannelLabel(order.manualPayChannel),
                ),
              _kv(
                '付款截图',
                order.employeePayAmount <= 0
                    ? '无需上传'
                    : (order.paymentScreenshot != null &&
                            order.paymentScreenshot!.isNotEmpty)
                        ? '已上传'
                        : '未上传',
              ),
              if (order.needsPaymentScreenshot) ...[
                const SizedBox(height: 8),
                _PaymentScreenshotCard(order: order),
              ] else if (order.isCompanyPay || order.employeePayAmount <= 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.business,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.employeePayAmount <= 0
                              ? '本单由企业代付，无需上传付款截图'
                              : '企业代付部分无需截图',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (orderHasSettlementInfo(order)) ...[
                const SizedBox(height: 12),
                _SectionTitle(title: '资金与结算'),
                _kv('资金状态', settlementStatusLabel(order.settlementStatus)),
                if (order.paymentChannel.isNotEmpty)
                  _kv('支付渠道', paymentChannelLabel(order.paymentChannel)),
                if (order.settlementEligibleAt != null)
                  _kv(
                    '预计结算日期',
                    '${order.settlementEligibleAt!.year}-'
                        '${order.settlementEligibleAt!.month.toString().padLeft(2, '0')}-'
                        '${order.settlementEligibleAt!.day.toString().padLeft(2, '0')}',
                  ),
                if (order.settlementStatus == 'settlement_blocked')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_clock,
                              color: AppColors.accent, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '结算冻结：存在投诉/退款/风险，暂不可结算',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              if (showCustomerInfo) ...[
                const SizedBox(height: 8),
                _kv('员工姓名', order.customerName),
                _kv(
                  '员工部门',
                  EmployeeInfoHelper.departmentDisplay(
                    customerCompany: order.customerCompany,
                    address: order.address,
                  ),
                ),
                _kv('员工电话', order.phone.isEmpty ? '—' : order.phone),
              ],
              const SizedBox(height: 12),
              _SectionTitle(title: '金额'),
              if (order.isPackageOrder) ...[
                _kv('套餐基础价',
                    '¥${order.packageBasePrice.toStringAsFixed(2)}'),
                _kv('加菜金额', '¥${order.extraAmount.toStringAsFixed(2)}'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('订单总额',
                        style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(
                      '¥${order.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                _kv('商品金额', '¥${order.goodsAmount.toStringAsFixed(2)}'),
                _kv('配送费', '¥${order.deliveryFee.toStringAsFixed(2)}'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('合计',
                        style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(
                      '¥${order.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              if (order.needsPaymentScreenshot) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: AppColors.accent, size: 16),
                      SizedBox(width: 6),
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
              ],
              const SizedBox(height: 12),
              if (actions.isNotEmpty) ...[
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      Expanded(child: actions[i]),
                      if (i != actions.length - 1) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _PackageInfoBlock extends StatelessWidget {
  final Order order;
  const _PackageInfoBlock({required this.order});

  String _catLabel(String code) {
    switch (code) {
      case 'meat':
        return '荤菜';
      case 'vegetable':
        return '素菜';
      case 'staple':
        return '主食';
      case 'soup':
        return '汤品';
      case 'drink':
        return '饮品';
      default:
        return '其它';
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<OrderSelectedItem>>{};
    for (final s in order.selectedItems) {
      grouped.putIfAbsent(s.category, () => []).add(s);
    }
    final groupOrder = ['meat', 'vegetable', 'staple', 'soup', 'drink'];

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.local_dining,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  order.displayPackageName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '套餐基础价 ¥${order.packageBasePrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (order.selectedItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...groupOrder
                .where((g) => grouped[g] != null && grouped[g]!.isNotEmpty)
                .map((g) {
              final names =
                  grouped[g]!.map((i) => resolveDisplayDishName(i.name)).join('、');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${_catLabel(g)}：$names',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              );
            }),
          ],
          if (order.extraItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              '加菜',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            ...order.extraItems.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${resolveDisplayDishName(e.name)} ×${e.quantity}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '+¥${e.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('加菜合计',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    )),
                const Spacer(),
                Text(
                  '¥${order.extraAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MerchantHeader extends StatelessWidget {
  final Order order;
  const _MerchantHeader({required this.order});

  @override
  Widget build(BuildContext context) {
    final logoSeed =
        context.watch<MerchantState>().logoForMerchant(order.merchantId);
    return Row(
      children: [
        MerchantBadgeLogo(seed: logoSeed, size: 40, radius: 10),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            order.displayMerchantName(
              merchantProfileName: context
                  .watch<MerchantState>()
                  .merchantNameFor(order.merchantId),
            ),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final OrderStatus status;
  const _StatusChip({required this.status});

  Color get _bg {
    switch (status) {
      case OrderStatus.pendingMerchantConfirm:
      case OrderStatus.pendingPayment:
      case OrderStatus.paymentSubmitted:
        return AppColors.accentLight;
      case OrderStatus.accepted:
        return AppColors.primaryLight;
      case OrderStatus.delivering:
        return const Color(0xFFE0EBFF);
      case OrderStatus.completed:
        return const Color(0xFFF1F3F5);
      case OrderStatus.cancelled:
        return const Color(0xFFF1F3F5);
    }
  }

  Color get _fg {
    switch (status) {
      case OrderStatus.pendingMerchantConfirm:
      case OrderStatus.pendingPayment:
      case OrderStatus.paymentSubmitted:
        return AppColors.accent;
      case OrderStatus.accepted:
        return AppColors.primary;
      case OrderStatus.delivering:
        return AppColors.statusBlue;
      case OrderStatus.completed:
        return AppColors.textSecondary;
      case OrderStatus.cancelled:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: TextStyle(
            color: _fg, fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 付款截图占位卡
class _PaymentScreenshotCard extends StatelessWidget {
  final Order order;
  const _PaymentScreenshotCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final hasScreenshot = order.paymentScreenshot != null &&
        order.paymentScreenshot!.isNotEmpty;
    final imageUrl = resolveAssetUrl(order.paymentScreenshot);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasScreenshot && imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      color: Colors.white,
                      child: const Icon(Icons.broken_image_outlined,
                          color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    hasScreenshot
                        ? Icons.image_outlined
                        : Icons.image_not_supported_outlined,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.primary, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          hasScreenshot ? '已上传付款截图' : '未上传付款截图',
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '订单金额：¥${order.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 订单详情底部「联系商家 / 联系顾客」按钮。
///
/// 同一个聊天页面（[OrderConversationPage]）员工 / 商家两端复用：
/// - [asMerchant] = false：员工端，进入"联系商家"
/// - [asMerchant] = true ：商家端，进入"联系顾客"
class _ContactButton extends StatefulWidget {
  final Order order;
  final bool asMerchant;
  const _ContactButton({required this.order, required this.asMerchant});

  @override
  State<_ContactButton> createState() => _ContactButtonState();
}

class _ContactButtonState extends State<_ContactButton> {
  @override
  Widget build(BuildContext context) {
    final label = widget.asMerchant ? '联系顾客' : '联系商家';
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          elevation: 0,
        ),
        onPressed: () async {
          final order = widget.order;
          final asMerchant = widget.asMerchant;
          ApiClient? apiClient;
          try {
            apiClient = context.read<ApiClient>();
          } catch (_) {
            apiClient = null;
          }
          final rootNav = Navigator.of(context, rootNavigator: true);
          await Navigator.of(context).maybePop();
          rootNav.push(
            MaterialPageRoute(
              fullscreenDialog: false,
              builder: (_) => OrderConversationPage(
                order: order,
                asMerchant: asMerchant,
                apiClient: apiClient,
              ),
            ),
          );
        },
        icon: const Icon(Icons.chat_bubble_outline, size: 18),
        label: Text(label),
      ),
    );
  }
}
