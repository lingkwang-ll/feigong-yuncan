import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../theme/app_theme.dart';

/// 商家端订单状态展示（汇总页卡片 / 列表）
class MerchantOrderStatusChip extends StatelessWidget {
  final OrderStatus status;
  final bool compact;

  const MerchantOrderStatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  static String summaryLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.pendingPayment:
        return '待支付';
      case OrderStatus.paymentSubmitted:
      case OrderStatus.pendingMerchantConfirm:
        return '待确认';
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

  static Color foregroundColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pendingPayment:
        return AppColors.statusYellow;
      case OrderStatus.paymentSubmitted:
      case OrderStatus.pendingMerchantConfirm:
        return AppColors.accent;
      case OrderStatus.accepted:
        return AppColors.primary;
      case OrderStatus.delivering:
        return AppColors.statusBlue;
      case OrderStatus.completed:
        return const Color(0xFF6B8F71);
      case OrderStatus.cancelled:
        return AppColors.textSecondary;
    }
  }

  static Color backgroundColor(OrderStatus status) {
    return foregroundColor(status).withValues(alpha: 0.12);
  }

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor(status);
    final bg = backgroundColor(status);
    final label = summaryLabel(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// 商家端批量/详情操作可用的状态判断
class MerchantOrderStatusRules {
  MerchantOrderStatusRules._();

  static bool isAwaitingMerchantConfirm(OrderStatus status) =>
      status == OrderStatus.paymentSubmitted ||
      status == OrderStatus.pendingMerchantConfirm;

  static bool canMerchantAccept(OrderStatus status) =>
      isAwaitingMerchantConfirm(status);

  static bool isPrintableLabelStatus(OrderStatus status) =>
      status != OrderStatus.pendingPayment &&
      status != OrderStatus.cancelled;

  /// 商家端「今日订餐汇总 / 员工订餐明细」可见（不含待支付、已取消）
  static bool isVisibleInMerchantSummary(OrderStatus status) =>
      status != OrderStatus.pendingPayment &&
      status != OrderStatus.cancelled;
}
