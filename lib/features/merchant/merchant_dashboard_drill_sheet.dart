import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order_model.dart';
import '../../state/merchant_conversation_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/meal_batch_aggregator.dart';
import '../../widgets/merchant_order_chat_action.dart';
import '../../widgets/merchant_order_status_chip.dart';
import 'merchant_order_detail_helper.dart';

enum MerchantStatDrill {
  totalPortions('今日订单列表'),
  totalPeople('员工订餐明细'),
  totalAmount('今日成交订单'),
  pending('待处理订单');

  final String title;
  const MerchantStatDrill(this.title);
}

class MerchantDashboardDrillSheet {
  MerchantDashboardDrillSheet._();

  static Future<void> show(
    BuildContext context, {
    required MerchantStatDrill drill,
    required MealBatchSummary batch,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DrillSheet(drill: drill, batch: batch),
    );
  }
}

class _DrillSheet extends StatelessWidget {
  final MerchantStatDrill drill;
  final MealBatchSummary batch;

  const _DrillSheet({required this.drill, required this.batch});

  List<Order> _orders() {
    switch (drill) {
      case MerchantStatDrill.totalPortions:
        return batch.sourceOrders;
      case MerchantStatDrill.totalAmount:
        return batch.sourceOrders
            .where((o) =>
                o.status == OrderStatus.accepted ||
                o.status == OrderStatus.delivering ||
                o.status == OrderStatus.completed)
            .toList();
      case MerchantStatDrill.pending:
        return batch.sourceOrders
        .where((o) =>
            o.status == OrderStatus.pendingMerchantConfirm ||
            o.status == OrderStatus.paymentSubmitted)
            .toList();
      case MerchantStatDrill.totalPeople:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    drill.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Flexible(
            child: drill == MerchantStatDrill.totalPeople
                ? _EmployeeGroupList(
                    groups: batch.labelGroups,
                    orders: batch.sourceOrders,
                  )
                : _OrderList(
                    orders: _orders(),
                    onTap: (order) {
                      Navigator.pop(context);
                      MerchantOrderDetailHelper.show(context, order: order);
                    },
                  ),
          ),
          SizedBox(height: bottom + 8),
        ],
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<Order> orders;
  final ValueChanged<Order> onTap;

  const _OrderList({required this.orders, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unreadState = context.watch<MerchantConversationState>();
    if (orders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            '暂无相关订单',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final order = orders[i];
        final unread = unreadState.unreadForOrder(order.id);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  order.displayOrderNo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (unread > 0) MerchantUnreadBadge(count: unread),
            ],
          ),
          subtitle: Text(
            '${order.customerName} · ${MerchantOrderStatusChip.summaryLabel(order.status)}',
            style: const TextStyle(fontSize: 13),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '¥${order.displayAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 4),
              MerchantOrderChatAction(
                order: order,
                unreadCount: unread,
                iconOnly: true,
              ),
            ],
          ),
          onTap: () => onTap(order),
        );
      },
    );
  }
}

class _EmployeeGroupList extends StatelessWidget {
  final List<MealLabelGroup> groups;
  final List<Order> orders;

  const _EmployeeGroupList({
    required this.groups,
    required this.orders,
  });

  Order? _orderFor(MealLabelGroup group) {
    if (group.orderId.isEmpty) return null;
    for (final o in orders) {
      if (o.id == group.orderId) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final unreadState = context.watch<MerchantConversationState>();
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            '暂无员工订餐',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final group = groups[i];
        final order = _orderFor(group);
        final unread = unreadState.unreadForOrder(group.orderId);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${group.employeeName} · ${group.department}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  MerchantOrderStatusChip(status: group.status, compact: true),
                  const SizedBox(width: 6),
                  if (order != null)
                    MerchantOrderChatAction(
                      order: order,
                      unreadCount: unread,
                      compact: true,
                    )
                  else if (unread > 0)
                    MerchantUnreadBadge(count: unread),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                group.displayLines.skip(1).join('\n'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              if (group.remark.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '备注：${group.remark}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
