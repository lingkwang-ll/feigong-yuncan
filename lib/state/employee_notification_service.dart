import 'package:flutter/foundation.dart';

import '../utils/notification_sound.dart';

/// 员工端新消息提醒协调器（避免轮询重复播放）。
class EmployeeNotificationService {
  EmployeeNotificationService._();

  static final EmployeeNotificationService instance =
      EmployeeNotificationService._();

  String? _employeeId;
  bool _unreadBaselineReady = false;

  Map<String, int> _knownUnreadByOrder = {};

  /// 员工正在查看的订单聊天页（该订单新消息不播放提示音）
  String? activeChatOrderId;

  void resetForEmployee(String employeeId) {
    if (_employeeId == employeeId && _unreadBaselineReady) return;
    _employeeId = employeeId;
    _unreadBaselineReady = false;
    _knownUnreadByOrder = {};
    activeChatOrderId = null;
    debugPrint('[employee-notify] reset employeeId=$employeeId');
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

  void onUnreadSnapshot(Map<String, int> unreadByOrderId) {
    if (!_unreadBaselineReady) {
      _knownUnreadByOrder = Map<String, int>.from(unreadByOrderId);
      _unreadBaselineReady = true;
      debugPrint(
        '[employee-notify] unread baseline orders=${unreadByOrderId.length}',
      );
      return;
    }

    for (final entry in unreadByOrderId.entries) {
      final orderId = entry.key;
      final next = entry.value;
      final prev = _knownUnreadByOrder[orderId] ?? 0;

      if (prev == 0 && next > 0 && orderId != activeChatOrderId) {
        debugPrint(
          '[employee-notify] message sound orderId=$orderId unread=$next',
        );
        NotificationSound.playEmployeeMessage();
      }
    }
    _knownUnreadByOrder = Map<String, int>.from(unreadByOrderId);
  }
}
