import 'dart:convert';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/order_api.dart';
import '../mock/mock_seed_orders.dart';
import '../models/order_model.dart';
import '../models/user_model.dart';
import 'local_storage.dart';

/// 订单持久化
///
/// 支持 [DataSourceMode.local] / [DataSourceMode.api] 两种模式。
/// - api 模式：从后端读写，写成功后也会同步到本地缓存作为离线备份
/// - local 模式：纯本地 SharedPreferences + seed
class OrderRepository {
  OrderRepository(this._storage, {OrderApi? orderApi}) : _api = orderApi;

  final LocalStorage _storage;
  final OrderApi? _api;

  static const _keyOrders = 'order.list';

  bool get _useApi =>
      AppConfig.dataSourceMode == DataSourceMode.api && _api != null;

  /// 启动时使用：本地缓存恢复（如果没有则用 seed）
  Future<List<Order>> loadOrders() async {
    final raw = _storage.getString(_keyOrders);
    if (raw == null || raw.isEmpty) {
      final seed = _useApi ? <Order>[] : seedOrders();
      await _saveLocal(seed);
      return seed;
    }
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      final seed = _useApi ? <Order>[] : seedOrders();
      await _saveLocal(seed);
      return seed;
    }
  }

  /// 根据用户身份从后端拉订单（成功时覆盖本地缓存，不使用陈旧列表）
  Future<List<Order>?> fetchRemoteOrders({
    required UserRole role,
    String? userId,
    String? merchantId,
    bool forceReplace = true,
  }) async {
    if (!_useApi) return null;
    try {
      List<Order> list;
      if (role == UserRole.merchant) {
        list = await _api!.getMerchantOrders(merchantId: merchantId);
      } else {
        if (userId == null || userId.isEmpty) return <Order>[];
        list = await _api!.getEmployeeOrders(userId: userId);
      }
      await _saveLocal(list);
      return list;
    } on ApiException {
      return null; // 让上层决定是否降级
    }
  }

  /// 保存整份订单列表（local 模式核心入口）
  Future<void> saveOrders(List<Order> orders) async {
    await _saveLocal(orders);
  }

  /// 创建单条订单
  ///
  /// api 模式下后端会返回新的订单（包含真实 id / createdAt）。
  Future<Order> createOrder(
    Order order,
    List<Order> currentAll, {
    String? userId,
  }) async {
    if (_useApi) {
      try {
        final created = await _api!.createOrder(order, userId: userId);
        currentAll.add(created);
        await _saveLocal(currentAll);
        return created;
      } on ApiException {
        // 降级走本地
      }
    }
    currentAll.add(order);
    await _saveLocal(currentAll);
    return order;
  }

  /// 更新订单状态
  Future<void> updateOrderStatus(
    String orderId,
    OrderStatus status,
    List<Order> currentAll, {
    String? rejectReason,
  }) async {
    final idx = currentAll.indexWhere((o) => o.id == orderId);
    if (idx >= 0 && rejectReason != null) {
      currentAll[idx].rejectReason = rejectReason;
    }
    if (_useApi) {
      try {
        await _api!.updateOrderStatus(orderId, status,
            rejectReason: rejectReason);
      } on ApiException {
        // 降级到本地
      }
    }
    await _saveLocal(currentAll);
  }

  Future<void> _saveLocal(List<Order> orders) async {
    final list = orders.map((o) => o.toJson()).toList();
    await _storage.setString(_keyOrders, jsonEncode(list));
  }

  /// 仅用于调试/重置
  Future<void> reset() => _storage.remove(_keyOrders);
}
