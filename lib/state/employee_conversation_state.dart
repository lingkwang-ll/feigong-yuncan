import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/conversation_api.dart';
import '../models/conversation_model.dart';
import 'employee_notification_service.dart';

/// 员工端订单会话未读状态（按 orderId 索引）
class EmployeeConversationState extends ChangeNotifier {
  EmployeeConversationState({required ApiClient apiClient})
      : _api = ConversationApi(apiClient);

  final ConversationApi _api;

  Map<String, Conversation> _byOrderId = const {};
  bool _refreshing = false;
  String? _lastEmployeeId;

  bool get isRefreshing => _refreshing;

  int get totalUnread =>
      _byOrderId.values.fold(0, (sum, c) => sum + c.employeeUnreadCount);

  int unreadForOrder(String orderId) =>
      _byOrderId[orderId]?.employeeUnreadCount ?? 0;

  Conversation? conversationForOrder(String orderId) => _byOrderId[orderId];

  Future<void> refresh({required String employeeId}) async {
    if (employeeId.isEmpty) return;
    _refreshing = true;
    notifyListeners();
    try {
      final list = await _api.listForEmployee();
      final next = <String, Conversation>{
        for (final c in list) c.orderId: c,
      };
      _byOrderId = next;
      _lastEmployeeId = employeeId;
      final unreadMap = {
        for (final c in list) c.orderId: c.employeeUnreadCount,
      };
      EmployeeNotificationService.instance.onUnreadSnapshot(unreadMap);
      debugPrint(
        '[employee-conversations-refresh] employeeId=$employeeId '
        'conversations=${list.length} totalUnread=$totalUnread',
      );
    } catch (e) {
      debugPrint('[employee-conversations-refresh] error=$e');
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  void applyLocalRead(String orderId) {
    final conv = _byOrderId[orderId];
    if (conv == null || conv.employeeUnreadCount == 0) return;
    _byOrderId = Map<String, Conversation>.from(_byOrderId)
      ..[orderId] = Conversation(
        id: conv.id,
        type: conv.type,
        orderId: conv.orderId,
        merchantId: conv.merchantId,
        employeeId: conv.employeeId,
        lastMessageText: conv.lastMessageText,
        lastMessageAt: conv.lastMessageAt,
        employeeUnreadCount: 0,
        merchantUnreadCount: conv.merchantUnreadCount,
        status: conv.status,
        createdAt: conv.createdAt,
        updatedAt: conv.updatedAt,
        orderNo: conv.orderNo,
        orderStatus: conv.orderStatus,
        employeeName: conv.employeeName,
        merchantName: conv.merchantName,
      );
    notifyListeners();
    EmployeeNotificationService.instance.onLocalRead(orderId);
  }

  void clear() {
    _byOrderId = const {};
    _lastEmployeeId = null;
    notifyListeners();
  }

  String? get lastEmployeeId => _lastEmployeeId;
}
