import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/api_config.dart';
import '../../api/review_api.dart';
import '../../api/runtime_config_api.dart';
import '../../models/order_model.dart';
import '../../state/app_state.dart';
import '../../state/employee_conversation_state.dart';
import '../../state/order_state.dart';
import '../../state/review_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/reorder_helper.dart';
import '../../widgets/app_button.dart';
import '../../widgets/dish_review_history_sheet.dart';
import '../../widgets/order_card.dart';
import '../../widgets/order_review_sheet.dart';
import '../../widgets/merchant_review_sheet.dart';
import '../../widgets/order_detail_sheet.dart';

/// 员工端"我的订单" - 参考 05_employee_orders.png
class EmployeeOrdersPage extends StatefulWidget {
  const EmployeeOrdersPage({super.key});

  @override
  State<EmployeeOrdersPage> createState() => _EmployeeOrdersPageState();
}

enum _CompletedReviewFilter { all, pending, reviewed }

class _EmployeeOrdersPageState extends State<EmployeeOrdersPage> {
  final Set<String> _reviewedOrderIds = {};
  Timer? _pollTimer;
  bool? _enableReview;
  _CompletedReviewFilter _completedReviewFilter = _CompletedReviewFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _loadReviewedFlags();
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshConversations();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshConversations() async {
    if (!mounted) return;
    final user = context.read<AppState>().currentUser;
    if (user == null) return;
    await context.read<EmployeeConversationState>().refresh(
          employeeId: user.id,
        );
  }

  int _tab = 0;

  final _tabs = const <(String, OrderStatus?)>[
    ('全部', null),
    ('待确认', OrderStatus.pendingMerchantConfirm),
    ('已接单', OrderStatus.accepted),
    ('配送中', OrderStatus.delivering),
    ('已完成', OrderStatus.completed),
  ];

  Future<void> _loadReviewedFlags() async {
    if (AppConfig.dataSourceMode != DataSourceMode.api) return;
    final orders = context.read<OrderState>().orders;
    final api = ReviewApi(context.read<ApiClient>());
    for (final o in orders) {
      if (o.status != OrderStatus.completed) continue;
      try {
        final r = await api.getByOrder(o.id);
        if (r != null && mounted) {
          setState(() => _reviewedOrderIds.add(o.id));
        }
      } catch (_) {
        // ignore
      }
    }
  }

  bool _isReviewed(Order order) {
    if (_reviewedOrderIds.contains(order.id)) return true;
    if (AppConfig.dataSourceMode != DataSourceMode.api) {
      return context.read<ReviewState>().isOrderReviewed(order.id);
    }
    return false;
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();
    final user = app.currentUser;
    if (user == null) return;
    if (AppConfig.dataSourceMode == DataSourceMode.api) {
      try {
        _enableReview = (await RuntimeConfigApi(context.read<ApiClient>())
                .fetchAppSettings())
            .enableReview;
      } catch (_) {
        _enableReview ??= true;
      }
    }
    await Future.wait([
      context.read<OrderState>().refreshEmployeeOrders(user.id),
      context.read<ReviewState>().initialize(),
      context.read<EmployeeConversationState>().refresh(employeeId: user.id),
    ]);
    await _loadReviewedFlags();
  }

  @override
  Widget build(BuildContext context) {
    final orderState = context.watch<OrderState>();
    final source = orderState.employeeOrders();
    var filtered = orderState.byStatus(source, _tabs[_tab].$2);
    if (_tabs[_tab].$2 == OrderStatus.completed &&
        _completedReviewFilter != _CompletedReviewFilter.all) {
      filtered = filtered.where((o) {
        final reviewed = _isReviewed(o);
        if (_completedReviewFilter == _CompletedReviewFilter.pending) {
          return !reviewed;
        }
        return reviewed;
      }).toList();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '我的订单',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.background,
            child: SizedBox(
              height: 44,
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final active = i == _tab;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => _tab = i);
                        _refresh();
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _tabs[i].$1,
                            style: TextStyle(
                              fontSize: 14,
                              color: active
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 5),
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
                }),
              ),
            ),
          ),
          if (_tabs[_tab].$2 == OrderStatus.completed)
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _CompletedFilterChip(
                      label: '全部完成',
                      selected:
                          _completedReviewFilter == _CompletedReviewFilter.all,
                      onTap: () => setState(
                        () => _completedReviewFilter =
                            _CompletedReviewFilter.all,
                      ),
                    ),
                    _CompletedFilterChip(
                      label: '待评价',
                      selected: _completedReviewFilter ==
                          _CompletedReviewFilter.pending,
                      onTap: () => setState(
                        () => _completedReviewFilter =
                            _CompletedReviewFilter.pending,
                      ),
                    ),
                    _CompletedFilterChip(
                      label: '已评价',
                      selected: _completedReviewFilter ==
                          _CompletedReviewFilter.reviewed,
                      onTap: () => setState(
                        () => _completedReviewFilter =
                            _CompletedReviewFilter.reviewed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _refresh,
              child: filtered.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 80),
                        Center(
                          child: Text('暂无订单',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final order = filtered[i];
                        final reviewed = _isReviewed(order);
                        return OrderCard(
                          order: order,
                          isReviewed: reviewed,
                          showEmployeeChat: true,
                          onViewDetail: () => _showOrderDetail(order),
                          onReview: order.status == OrderStatus.completed &&
                                  !reviewed
                              ? () => _openReview(order)
                              : null,
                          onReorder: () => ReorderHelper.start(context, order),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderDetail(Order order) {
    final reviewState = context.read<ReviewState>();
    final orderState = context.read<OrderState>();
    final orderReviews = reviewState.reviewsForOrder(order.id);
    OrderDetailSheet.show(
      context,
      order: order,
      showCustomerInfo: false,
      showReviewFeatures: true,
      orderReviews:
          orderReviews.isEmpty ? null : orderReviews,
      onDishTapForHistory: (dishId, dishName) {
        final history = reviewState.reviewsForDish(dishId);
        DishReviewHistorySheet.show(
          context,
          dishName: dishName,
          reviews: history,
        );
      },
      actions: orderState.canEmployeeCancel(order)
          ? [
              OutlineAccentButton(
                label: '取消订单',
                onPressed: () => _confirmCancel(order),
              ),
            ]
          : const [],
    );
  }

  Future<void> _confirmCancel(Order order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消订单？'),
        content: const Text('取消后订单将无法恢复，请确认'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认取消'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final success =
        await context.read<OrderState>().cancelOrderByEmployee(order.id);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '订单已取消' : '当前状态不可取消'),
      ),
    );
  }

  Future<void> _openReview(Order order) async {
    if (order.status != OrderStatus.completed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('订单完成后才可评价')),
      );
      return;
    }
    if (_enableReview == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评价功能未开启，请联系企业管理员在后台开启')),
      );
      return;
    }
    final bool? submitted;
    if (AppConfig.dataSourceMode == DataSourceMode.api) {
      submitted = await MerchantReviewSheet.show(context, order: order);
    } else {
      submitted = await OrderReviewSheet.show(context, order: order);
    }
    if (submitted == true && mounted) {
      setState(() => _reviewedOrderIds.add(order.id));
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评价已提交')),
      );
    }
  }
}

class _CompletedFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CompletedFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primaryLight,
        labelStyle: TextStyle(
          fontSize: 13,
          color: selected ? AppColors.primary : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
