import 'package:flutter/material.dart';
import '../../utils/order_time_util.dart';
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../state/merchant_state.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';
import 'app_logo.dart';
import 'employee_order_chat_action.dart';
import 'merchant_order_chat_action.dart';

/// 员工端订单列表卡片
class OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback? onViewDetail;
  final VoidCallback? onReorder;
  final VoidCallback? onReview;
  final bool isReviewed;
  final bool showEmployeeChat;

  const OrderCard({
    super.key,
    required this.order,
    this.onViewDetail,
    this.onReorder,
    this.onReview,
    this.isReviewed = false,
    this.showEmployeeChat = false,
  });

  Color _statusColor() {
    switch (order.status) {
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

  Color _statusBg() {
    switch (order.status) {
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

  @override
  Widget build(BuildContext context) {
    final logoSeed =
        context.watch<MerchantState>().logoForMerchant(order.merchantId);
    final merchantLabel = order.displayMerchantName(
      merchantProfileName:
          context.watch<MerchantState>().merchantNameFor(order.merchantId),
    );
    final chatUnread = showEmployeeChat
        ? EmployeeOrderChatAction.unreadOf(context, order.id)
        : 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MerchantBadgeLogo(seed: logoSeed, size: 34, radius: 9),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  merchantLabel,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusBg(),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  order.status.label,
                  style: TextStyle(
                      fontSize: 12,
                      color: _statusColor(),
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (showEmployeeChat && chatUnread > 0) ...[
                const SizedBox(width: 6),
                MerchantUnreadBadge(count: chatUnread, size: 14),
              ],
            ],
          ),
          if (showEmployeeChat) ...[
            const SizedBox(height: 8),
            EmployeeOrderChatAction(
              order: order,
              unreadCount: chatUnread,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            order.itemsSummary,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '下单时间：${OrderTimeUtil.formatDisplay(order.createdAt)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textTertiary),
                ),
              ),
              Text(
                '共${order.totalQuantity}件  ',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              Text(
                '¥${order.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 0.5, color: AppColors.divider),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (order.status == OrderStatus.completed && onReorder != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: OutlinePrimaryButton(
                    label: '再次下单',
                    onPressed: onReorder,
                  ),
                ),
              if (order.status == OrderStatus.completed && isReviewed)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Text(
                      '已评价',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              if (order.status == OrderStatus.completed &&
                  !isReviewed &&
                  onReview != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: OutlineAccentButton(
                    label: '评价',
                    onPressed: onReview,
                  ),
                ),
              OutlineAccentButton(
                label: '查看订单',
                onPressed: onViewDetail,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
