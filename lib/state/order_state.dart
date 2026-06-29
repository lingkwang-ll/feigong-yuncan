import 'package:flutter/foundation.dart';

import '../models/dish_model.dart';
import '../models/order_model.dart';
import '../models/user_model.dart';
import '../state/merchant_notification_service.dart';
import '../repositories/order_repository.dart';
import '../utils/meal_batch_aggregator.dart';

/// 订单状态：员工端和商家端共享同一份订单列表，以便联动
class OrderState extends ChangeNotifier {
  OrderState({required OrderRepository orderRepository})
      : _repo = orderRepository;

  final OrderRepository _repo;

  List<Order> _orders = [];
  bool _initialized = false;
  bool _isRefreshing = false;
  String? _lastMerchantRefreshId;

  bool get isInitialized => _initialized;
  bool get isRefreshing => _isRefreshing;

  List<Order> get orders => List.unmodifiable(
        List.of(_orders)..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  List<Order> employeeOrders() => orders;

  List<Order> merchantOrders(String merchantId) =>
      orders.where((o) => o.merchantId == merchantId).toList();

  List<Order> byStatus(List<Order> source, OrderStatus? status) {
    if (status == null) return source;
    return source.where((o) => o.status == status).toList();
  }

  int get merchantPendingCount => _orders
      .where((o) =>
          o.status == OrderStatus.pendingMerchantConfirm ||
          o.status == OrderStatus.paymentSubmitted)
      .length;

  bool canEmployeeCancel(Order order) =>
      order.status == OrderStatus.pendingMerchantConfirm ||
      order.status == OrderStatus.pendingPayment ||
      order.status == OrderStatus.paymentSubmitted;

  Future<void> initialize() async {
    if (_initialized) return;
    _orders = await _repo.loadOrders();
    _initialized = true;
    notifyListeners();
  }

  Future<void> refreshForRole({
    required UserRole role,
    String? userId,
    String? merchantId,
  }) async {
    _isRefreshing = true;
    notifyListeners();
    try {
      final remote = await _repo.fetchRemoteOrders(
        role: role,
        userId: userId,
        merchantId: merchantId,
      );
      if (remote != null) {
        if (role == UserRole.merchant && merchantId != null) {
          _lastMerchantRefreshId = merchantId;
          debugPrint(
            '[merchant-orders-refresh] timestamp=${DateTime.now().toIso8601String()}, count=${remote.length}',
          );
        } else if (role == UserRole.employee && userId != null) {
          debugPrint(
            '[employee-orders-refresh] timestamp=${DateTime.now().toIso8601String()}, count=${remote.length}',
          );
        }
        _orders = remote;
        if (role == UserRole.merchant && merchantId != null) {
          MerchantNotificationService.instance.onMerchantOrdersUpdated(
            merchantOrders(merchantId),
          );
        }
        notifyListeners();
      } else if (role == UserRole.merchant) {
        debugPrint(
          '[merchant-orders-refresh] FAILED timestamp=${DateTime.now().toIso8601String()}',
        );
      }
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> refreshEmployeeOrders(String userId) async {
    await refreshForRole(
      role: UserRole.employee,
      userId: userId,
    );
  }

  Future<void> refreshMerchantDashboard({
    required String merchantId,
    required String merchantName,
    DateTime? summaryDate,
    MealType? mealType,
  }) async {
    await refreshForRole(
      role: UserRole.merchant,
      merchantId: merchantId,
    );
    final orders = merchantOrders(merchantId);
    final anchor = summaryDate ?? DateTime.now();
    final day = DateTime(anchor.year, anchor.month, anchor.day);
    final meal = mealType ?? MealBatchAggregator.currentMealPeriod();
    final batch = MealBatchAggregator.build(
      orders: orders,
      date: day,
      mealType: meal,
      merchantId: merchantId,
      merchantName: merchantName,
    );
    debugPrint(
      '[merchant-summary-refresh] timestamp=${DateTime.now().toIso8601String()}, '
      'today_people=${batch.totalPeople}, today_amount=${batch.totalAmount}, '
      'employee_rows=${batch.labelGroups.length}, meal=${meal.name}',
    );
  }

  Future<void> addOrder(Order order, {String? userId}) async {
    final saved = await _repo.createOrder(order, _orders, userId: userId);
    if (!_orders.contains(saved)) _orders.add(saved);
    notifyListeners();
  }

  Future<void> updateStatus(String orderId, OrderStatus status,
      {String? rejectReason}) async {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx < 0) return;
    _orders[idx].status = status;
    if (rejectReason != null) {
      _orders[idx].rejectReason = rejectReason;
    }
    await _repo.updateOrderStatus(orderId, status, _orders,
        rejectReason: rejectReason);
    final merchantId = _orders[idx].merchantId;
    if (_lastMerchantRefreshId == merchantId ||
        merchantId.isNotEmpty) {
      await refreshMerchantDashboard(
        merchantId: merchantId,
        merchantName: _orders[idx].merchantName,
      );
    } else {
      notifyListeners();
    }
  }

  Future<bool> cancelOrderByEmployee(String orderId) async {
    final idx = _orders.indexWhere((o) => o.id == orderId);
    if (idx < 0) return false;
    if (!canEmployeeCancel(_orders[idx])) return false;
    await updateStatus(orderId, OrderStatus.cancelled);
    return true;
  }

  Future<void> rejectOrderByMerchant(String orderId, String reason) async {
    await updateStatus(orderId, OrderStatus.cancelled, rejectReason: reason);
  }

  Future<void> updateBatchStatus(
    Iterable<String> orderIds,
    OrderStatus status,
  ) async {
    String? merchantId;
    for (final id in orderIds) {
      final idx = _orders.indexWhere((o) => o.id == id);
      if (idx < 0) continue;
      merchantId ??= _orders[idx].merchantId;
      _orders[idx].status = status;
      await _repo.updateOrderStatus(id, status, _orders);
    }
    if (merchantId != null) {
      final name = _orders
          .firstWhere(
            (o) => o.merchantId == merchantId,
            orElse: () => _orders.first,
          )
          .merchantName;
      await refreshMerchantDashboard(
        merchantId: merchantId,
        merchantName: name,
      );
    } else {
      notifyListeners();
    }
  }
}
