import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/merchant_api.dart';
import '../../models/dish_model.dart';
import '../../models/order_model.dart';
import '../../state/merchant_conversation_state.dart';
import '../../state/merchant_state.dart';
import '../../state/order_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/meal_batch_aggregator.dart';
import '../../utils/meal_label_print_status.dart';
import '../../utils/trial_run_policy.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/merchant_order_chat_action.dart';
import '../../widgets/merchant_order_status_chip.dart';
import 'merchant_meal_label_sheet.dart';
import 'merchant_order_detail_helper.dart';

/// 商家端今日订餐汇总（企业餐段汇总单）
class MerchantOrderProcessPage extends StatefulWidget {
  const MerchantOrderProcessPage({super.key});

  @override
  State<MerchantOrderProcessPage> createState() =>
      _MerchantOrderProcessPageState();
}

class _MerchantOrderProcessPageState extends State<MerchantOrderProcessPage>
    with WidgetsBindingObserver {
  late DateTime _selectedDate;
  late MealType _mealType;
  Timer? _pollTimer;
  Map<String, MealLabelPrintStatusItem> _printStatusMap = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _mealType = MealBatchAggregator.merchantCurrentMealPeriod();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshConversations();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refreshConversations() async {
    if (!mounted) return;
    final merchant = context.read<MerchantState>().currentMerchant;
    await context.read<MerchantConversationState>().refresh(
          merchantId: merchant.id,
        );
  }

  Future<void> _refresh() async {
    final merchant = context.read<MerchantState>().currentMerchant;
    await Future.wait([
      context.read<OrderState>().refreshMerchantDashboard(
            merchantId: merchant.id,
            merchantName: merchant.name,
            summaryDate: _selectedDate,
            mealType: _mealType,
          ),
      _refreshConversations(),
    ]);
    await _loadLabelPrintStatus(merchant.id);
  }

  Future<void> _loadLabelPrintStatus(String merchantId) async {
    if (AppConfig.dataSourceMode != DataSourceMode.api) return;
    try {
      final api = MerchantApi(context.read<ApiClient>());
      final items = await api.getMealLabelPrintStatus(
        businessDate: formatBusinessDate(_selectedDate),
        mealType: _mealType.name,
        merchantId: merchantId,
      );
      if (!mounted) return;
      setState(() {
        _printStatusMap = parseMealLabelPrintStatusMap(items);
      });
    } catch (_) {}
  }

  void _shiftDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _refresh();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
      _refresh();
    }
  }

  Future<void> _batchAction(
    MealBatchSummary batch,
    OrderStatus status, {
    bool Function(OrderStatus current)? includeStatus,
  }) async {
    final ids = batch.sourceOrders
        .where((o) => includeStatus?.call(o.status) ?? true)
        .map((o) => o.id)
        .toList();
    if (ids.isEmpty) return;
    await context.read<OrderState>().updateBatchStatus(ids, status);
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已更新 ${ids.length} 单为${status.label}')),
      );
    }
  }

  Future<void> _confirmPending(MealBatchSummary batch) => _batchAction(
        batch,
        OrderStatus.accepted,
        includeStatus: MerchantOrderStatusRules.canMerchantAccept,
      );

  Future<void> _startDelivery(MealBatchSummary batch) => _batchAction(
        batch,
        OrderStatus.delivering,
        includeStatus: (s) => s == OrderStatus.accepted,
      );

  Future<void> _completeOrders(MealBatchSummary batch) => _batchAction(
        batch,
        OrderStatus.completed,
        includeStatus: (s) => s == OrderStatus.delivering,
      );

  @override
  Widget build(BuildContext context) {
    final orderState = context.watch<OrderState>();
    final merchant = context.watch<MerchantState>().currentMerchant;
    final batch = MealBatchAggregator.build(
      orders: orderState.merchantOrders(merchant.id),
      date: _selectedDate,
      mealType: _mealType,
      merchantId: merchant.id,
      merchantName: merchant.name,
    );
    final detailGroups = applyMealLabelPrintStatus(
      batch.labelGroups,
      _printStatusMap,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '今日订餐汇总',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _DateFilterBar(
              selectedDate: _selectedDate,
              onPrev: () => _shiftDate(-1),
              onNext: () => _shiftDate(1),
              onPick: _pickDate,
            ),
            const SizedBox(height: 8),
            _MealTypeTabs(
              selected: _mealType,
              pendingCounts: {
                for (final t in MealBatchAggregator.merchantSummaryMealTypes)
                  t: MealBatchAggregator.pendingCountFor(
                    orders: orderState.merchantOrders(merchant.id),
                    date: _selectedDate,
                    mealType: t,
                    merchantId: merchant.id,
                  ),
              },
              onChanged: (t) {
                setState(() => _mealType = t);
                _refresh();
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _SummaryCard(batch: batch),
                    if (batch.collectorInfo.hasCollector) ...[
                      const SizedBox(height: 12),
                      _CollectorInfoCard(collector: batch.collectorInfo),
                    ],
                    const SizedBox(height: 12),
                    _DishSummarySection(dishTotals: batch.dishTotals),
                    const SizedBox(height: 12),
                    _EmployeeDetailSection(
                      groups: detailGroups,
                      orders: batch.sourceOrders,
                      onOrderTap: (order) => MerchantOrderDetailHelper.show(
                        context,
                        order: order,
                        onStatusChanged: _refresh,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _BatchActions(
                      batch: batch,
                      onConfirm: () => _confirmPending(batch),
                      onStartDelivery: () => _startDelivery(batch),
                      onComplete: () => _completeOrders(batch),
                      onPrintLabels: () => MerchantMealLabelSheet.show(
                        context,
                        batch: batch,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          const AppLogo(size: 40, radius: 10),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '非攻云餐 · 商家端',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '企业订餐汇总',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateFilterBar extends StatelessWidget {
  final DateTime selectedDate;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;

  const _DateFilterBar({
    required this.selectedDate,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final isToday =
        OrderDateFilter.isSameDay(selectedDate, DateTime.now());
    final label =
        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left,
                  color: AppColors.textSecondary),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onPick,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      isToday ? '今天 $label' : label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealTypeTabs extends StatelessWidget {
  final MealType selected;
  final Map<MealType, int> pendingCounts;
  final ValueChanged<MealType> onChanged;

  const _MealTypeTabs({
    required this.selected,
    required this.pendingCounts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: MealBatchAggregator.merchantSummaryMealTypes.map((t) {
            final active = t == selected;
            final pending = pendingCounts[t] ?? 0;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(t),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          t.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                            color: active
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                        if (pending > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              pending > 9 ? '9+' : '$pending',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 2.5,
                      width: 24,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final MealBatchSummary batch;
  const _SummaryCard({required this.batch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                batch.merchantName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  batch.phase.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${batch.mealType.label} · 订餐截止 ${batch.mealType.deadlineAt}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('总人数', '${batch.totalPeople}'),
              _stat('总份数', '${batch.totalPortions}'),
              _stat(
                '总金额',
                '¥${batch.totalAmount.toStringAsFixed(0)}',
                color: AppColors.accent,
              ),
              _stat(
                '待处理',
                '${batch.pendingPeople}人',
                color: batch.pendingPeople > 0 ? AppColors.accent : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String k, String v, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          Text(
            v,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectorInfoCard extends StatelessWidget {
  final MealBatchCollectorInfo collector;
  const _CollectorInfoCard({required this.collector});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '统一收餐信息',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (!collector.hasCollector)
            const SizedBox.shrink()
          else ...[
            if (collector.multipleCollectors)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '存在多个拿饭人，请确认',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            _collectorRow('拿饭人', collector.name),
            const SizedBox(height: 6),
            _collectorRow('联系电话', collector.phone),
            if (collector.poiName.isNotEmpty) ...[
              const SizedBox(height: 6),
              _collectorRow('取餐地点', collector.poiName),
            ],
            const SizedBox(height: 6),
            _collectorRow(
              '详细地址',
              collector.addressText.isNotEmpty
                  ? collector.addressText
                  : collector.addressShort,
            ),
          ],
        ],
      ),
    );
  }

  Widget _collectorRow(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v.isEmpty ? '—' : v,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _DishSummarySection extends StatelessWidget {
  final List<DishAggregate> dishTotals;
  const _DishSummarySection({required this.dishTotals});

  @override
  Widget build(BuildContext context) {
    return _section(
      title: '菜品汇总',
      child: dishTotals.isEmpty
          ? const Text('暂无菜品',
              style: TextStyle(color: AppColors.textSecondary))
          : Column(
              children: dishTotals
                  .map(
                    (d) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(d.dishName,
                                style: const TextStyle(fontSize: 14)),
                          ),
                          Text(
                            '×${d.quantity}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _EmployeeDetailSection extends StatelessWidget {
  final List<MealLabelGroup> groups;
  final List<Order> orders;
  final ValueChanged<Order>? onOrderTap;

  const _EmployeeDetailSection({
    required this.groups,
    required this.orders,
    this.onOrderTap,
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

    return _section(
      title: '员工订餐明细',
      child: groups.isEmpty
          ? const Text('暂无员工订餐',
              style: TextStyle(color: AppColors.textSecondary))
          : Column(
              children: groups
                  .map(
                    (group) {
                      final order = _orderFor(group);
                      final unread = unreadState.unreadForOrder(group.orderId);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: order == null || onOrderTap == null
                                ? null
                                : () => onOrderTap!(order),
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(10),
                                    border: unread > 0
                                        ? Border.all(
                                            color: const Color(0xFFEF4444)
                                                .withValues(alpha: 0.35),
                                          )
                                        : null,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${group.labelCode}  ${group.employeeName}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          MerchantOrderStatusChip(
                                            status: group.status,
                                            compact: true,
                                          ),
                                          const SizedBox(width: 6),
                                          _LabelPrintBadge(group: group),
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
                                      const SizedBox(height: 4),
                                      ...group.displayLines.map(
                                        (line) => Text(
                                          line,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textPrimary,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '备注：${group.remark.isEmpty ? '无' : group.remark}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                MerchantOrderUnreadDot(unreadCount: unread),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  )
                  .toList(),
            ),
    );
  }
}

Widget _section({required String title, required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class _BatchActions extends StatelessWidget {
  final MealBatchSummary batch;
  final VoidCallback onConfirm;
  final VoidCallback onStartDelivery;
  final VoidCallback onComplete;
  final VoidCallback onPrintLabels;

  const _BatchActions({
    required this.batch,
    required this.onConfirm,
    required this.onStartDelivery,
    required this.onComplete,
    required this.onPrintLabels,
  });

  Widget _disabledMainButton(String label) {
    return Container(
      height: 48,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.divider.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (batch.isEmpty) {
      return Column(
        children: [
          _disabledMainButton('暂无可处理订单'),
          const SizedBox(height: 10),
          _printButton(),
        ],
      );
    }

    final hasConfirmable = batch.hasConfirmableOrders;
    final hasDelivering = batch.ordersDelivering.isNotEmpty;
    final hasAccepted = batch.ordersAccepted.isNotEmpty;
    final allDone = batch.allActiveCompleted;

    Widget mainButton;
    if (hasConfirmable) {
      mainButton = PrimaryActionButton(
        label: '确认接单',
        height: 48,
        onPressed: onConfirm,
      );
    } else if (hasDelivering) {
      mainButton = PrimaryActionButton(
        label: '完成配送',
        height: 48,
        onPressed: onComplete,
      );
    } else if (hasAccepted) {
      mainButton = PrimaryActionButton(
        label: '开始配送',
        height: 48,
        onPressed: onStartDelivery,
      );
    } else if (allDone) {
      mainButton = _disabledMainButton('今日订单已完成');
    } else if (batch.ordersPendingPayment.isNotEmpty) {
      mainButton = _disabledMainButton('等待顾客支付');
    } else {
      mainButton = _disabledMainButton('暂无可处理订单');
    }

    return Column(
      children: [
        mainButton,
        const SizedBox(height: 10),
        _printButton(),
      ],
    );
  }

  Widget _printButton() {
    final printable = batch.printableLabelGroups;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: printable.isEmpty ? null : onPrintLabels,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          printable.isEmpty ? '暂无可打印标签' : '打印标签',
        ),
      ),
    );
  }
}

class _LabelPrintBadge extends StatelessWidget {
  final MealLabelGroup group;

  const _LabelPrintBadge({required this.group});

  @override
  Widget build(BuildContext context) {
    final printed = group.isLabelPrinted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: printed ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        printed ? '已打印' : '未打印',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: printed ? const Color(0xFF2E7D32) : AppColors.accent,
        ),
      ),
    );
  }
}
