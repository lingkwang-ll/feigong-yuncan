import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order_model.dart';
import '../../state/merchant_conversation_state.dart';
import '../../state/merchant_state.dart';
import '../../state/order_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/order_detail_sheet.dart';
import 'merchant_dish_review_sheet.dart';

/// 商家端订单详情入口（在通用详情页上挂载评价查看与状态操作）
class MerchantOrderDetailHelper {
  MerchantOrderDetailHelper._();

  static Future<void> show(
    BuildContext context, {
    required Order order,
    VoidCallback? onStatusChanged,
  }) async {
    final merchantId = order.merchantId;
    if (merchantId.isNotEmpty) {
      final merchant = context.read<MerchantState>().currentMerchant;
      await context.read<OrderState>().refreshMerchantDashboard(
            merchantId: merchantId,
            merchantName: merchant.name.isNotEmpty
                ? merchant.name
                : order.merchantName,
          );
    }
    if (!context.mounted) return;
    final fresh = _freshOrder(context, order);

    return OrderDetailSheet.show(
      context,
      order: fresh,
      showCustomerInfo: true,
      actions: _actionsFor(context, fresh, onStatusChanged: onStatusChanged),
      showMerchantReviewButton: fresh.status == OrderStatus.completed,
      onViewDishReviews: fresh.status == OrderStatus.completed
          ? (dishId, dishName) {
              MerchantDishReviewSheet.show(
                context,
                dishId: dishId,
                dishName: dishName,
                merchantId: order.merchantId,
              );
            }
          : null,
    );
  }

  static Order _freshOrder(BuildContext context, Order order) {
    final orderState = context.read<OrderState>();
    for (final o in orderState.merchantOrders(order.merchantId)) {
      if (o.id == order.id) return o;
    }
    return order;
  }

  static List<Widget> _actionsFor(
    BuildContext context,
    Order order, {
    VoidCallback? onStatusChanged,
  }) {
    Future<void> applyStatus(OrderStatus status) async {
      await context.read<OrderState>().updateStatus(order.id, status);
      if (!context.mounted) return;
      try {
        await context.read<MerchantConversationState>().refresh(
              merchantId: order.merchantId,
            );
      } catch (_) {}
      onStatusChanged?.call();
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已更新为${status.label}')),
      );
    }

    switch (order.status) {
      case OrderStatus.pendingPayment:
        return [
          PrimaryActionButton(
            label: '等待顾客支付',
            height: 44,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('顾客尚未完成支付，暂不能接单')),
              );
            },
          ),
        ];
      case OrderStatus.paymentSubmitted:
      case OrderStatus.pendingMerchantConfirm:
        return [
          PrimaryActionButton(
            label: '确认接单',
            height: 44,
            onPressed: () => applyStatus(OrderStatus.accepted),
          ),
        ];
      case OrderStatus.accepted:
        return [
          PrimaryActionButton(
            label: '开始配送',
            height: 44,
            onPressed: () => applyStatus(OrderStatus.delivering),
          ),
        ];
      case OrderStatus.delivering:
        return [
          PrimaryActionButton(
            label: '完成订单',
            height: 44,
            onPressed: () => applyStatus(OrderStatus.completed),
          ),
        ];
      case OrderStatus.completed:
        return [
          PrimaryActionButton(
            label: '已完成',
            height: 44,
            onPressed: null,
          ),
        ];
      case OrderStatus.cancelled:
        return const [];
    }
  }

  static Widget reviewButton({
    required BuildContext context,
    required Order order,
    required String dishId,
    required String dishName,
  }) {
    return OutlineAccentButton(
      label: '查看评价',
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onPressed: () {
        MerchantDishReviewSheet.show(
          context,
          dishId: dishId,
          dishName: dishName,
          merchantId: order.merchantId,
        );
      },
    );
  }
}
