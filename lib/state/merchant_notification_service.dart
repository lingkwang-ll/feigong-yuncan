import 'package:flutter/foundation.dart';

import '../models/order_model.dart';
import '../utils/notification_sound.dart';

/// 商家端新订单 / 新消息提醒协调器（避免轮询重复播放）。
class MerchantNotificationService {
  MerchantNotificationService._();

  static final MerchantNotificationService instance =
      MerchantNotificationService._();

  String? _merchantId;
  bool _orderBaselineReady = false;
  bool _unreadBaselineReady = false;

  Set<String> _newOrderSoundPlayed = {};
  Map<String, OrderStatus> _knownOrderStatus = {};

  Map<String, int> _knownUnreadByOrder = {};

  /// 商家正在查看的订单聊天页（该订单新消息不播放提示音）
  String? activeChatOrderId;

  void resetForMerchant(String merchantId) {
    if (_merchantId == merchantId && _orderBaselineReady) return;
    _merchantId = merchantId;
    _orderBaselineReady = false;
    _unreadBaselineReady = false;
    _knownOrderStatus = {};
    _newOrderSoundPlayed = {};
    _knownUnreadByOrder = {};
    activeChatOrderId = null;
    debugPrint('[merchant-notify] reset merchantId=$merchantId');
  }

  void setActiveChatOrder(String? orderId) {
    activeChatOrderId = orderId;
    if (orderId != null) {
      _knownUnreadByOrder[orderId] = 0;
    }
  }

  void onLocalRead(String orderId) {
    _knownUnreadByOrder[orderId] = 0;
  }

  void onMerchantOrdersUpdated(List<Order> orders) {
    if (!_orderBaselineReady) {
      _knownOrderStatus = {for (final o in orders) o.id: o.status};
      _orderBaselineReady = true;
      debugPrint(
        '[merchant-notify] orders baseline count=${orders.length}',
      );
      return;
    }

    for (final order in orders) {
      final prev = _knownOrderStatus[order.id];
      if (prev == null) {
        if (_shouldPlayNewOrderSound(order.status)) {
          _playNewOrderOnce(order.id, order.status);
        }
      } else if (prev == OrderStatus.pendingPayment &&
          _shouldPlayNewOrderSound(order.status)) {
        _playNewOrderOnce(order.id, order.status);
      }
      _knownOrderStatus[order.id] = order.status;
    }
  }

  void _playNewOrderOnce(String orderId, OrderStatus status) {
    if (_newOrderSoundPlayed.contains(orderId)) return;
    _newOrderSoundPlayed.add(orderId);
    debugPrint(
      '[merchant-notify] new order sound orderId=$orderId '
      'status=${status.name}',
    );
    NotificationSound.playMerchantNewOrder();
  }

  void onUnreadSnapshot(Map<String, int> unreadByOrderId) {
    if (!_orderBaselineReady) {
      _knownUnreadByOrder = Map<String, int>.from(unreadByOrderId);
      return;
    }
    if (!_unreadBaselineReady) {
      _knownUnreadByOrder = Map<String, int>.from(unreadByOrderId);
      _unreadBaselineReady = true;
      debugPrint(
        '[merchant-notify] unread baseline orders=${unreadByOrderId.length}',
      );
      return;
    }

    for (final entry in unreadByOrderId.entries) {
      final orderId = entry.key;
      final next = entry.value;
      final prev = _knownUnreadByOrder[orderId] ?? 0;

      if (prev == 0 && next > 0 && orderId != activeChatOrderId) {
        debugPrint(
          '[merchant-notify] message sound orderId=$orderId unread=$next',
        );
        NotificationSound.playMerchantMessage();
      }
    }
    _knownUnreadByOrder = Map<String, int>.from(unreadByOrderId);
  }

  /// 仅顾客完成支付后可接单的状态才播放新订单提示音
  static bool _shouldPlayNewOrderSound(OrderStatus status) =>
      status == OrderStatus.paymentSubmitted ||
      status == OrderStatus.pendingMerchantConfirm;
}
