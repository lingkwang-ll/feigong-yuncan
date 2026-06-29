import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/conversation_api.dart';
import '../models/conversation_model.dart';
import '../state/merchant_notification_service.dart';

/// 商家端订单会话未读状态（按 orderId 索引，供汇总页 / 列表展示红点）
class MerchantConversationState extends ChangeNotifier {
  MerchantConversationState({required ApiClient apiClient})
      : _api = ConversationApi(apiClient);

  final ConversationApi _api;

  Map<String, Conversation> _byOrderId = const {};
  bool _refreshing = false;
  String? _lastMerchantId;

  bool get isRefreshing => _refreshing;

  int get totalUnread =>
      _byOrderId.values.fold(0, (sum, c) => sum + c.merchantUnreadCount);

  int unreadForOrder(String orderId) =>
      _byOrderId[orderId]?.merchantUnreadCount ?? 0;

  Conversation? conversationForOrder(String orderId) => _byOrderId[orderId];

  Future<void> refresh({required String merchantId}) async {
    if (merchantId.isEmpty) return;
    _refreshing = true;
    notifyListeners();
    try {
      final list = await _api.listForMerchant(merchantId: merchantId);
      final next = <String, Conversation>{
        for (final c in list) c.orderId: c,
      };
      _byOrderId = next;
      _lastMerchantId = merchantId;
      final unreadMap = {
        for (final c in list) c.orderId: c.merchantUnreadCount,
      };
      MerchantNotificationService.instance.onUnreadSnapshot(unreadMap);
      debugPrint(
        '[merchant-conversations-refresh] merchantId=$merchantId '
        'conversations=${list.length} totalUnread=$totalUnread',
      );
    } catch (e) {
      debugPrint('[merchant-conversations-refresh] error=$e');
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// 聊天页 markRead 成功后本地同步，避免等下一轮轮询
  void applyLocalRead(String orderId) {
    final conv = _byOrderId[orderId];
    if (conv == null || conv.merchantUnreadCount == 0) return;
    _byOrderId = Map<String, Conversation>.from(_byOrderId)
      ..[orderId] = Conversation(
        id: conv.id,
        type: conv.type,
        orderId: conv.orderId,
        merchantId: conv.merchantId,
        employeeId: conv.employeeId,
        lastMessageText: conv.lastMessageText,
        lastMessageAt: conv.lastMessageAt,
        employeeUnreadCount: conv.employeeUnreadCount,
        merchantUnreadCount: 0,
        status: conv.status,
        createdAt: conv.createdAt,
        updatedAt: conv.updatedAt,
        orderNo: conv.orderNo,
        orderStatus: conv.orderStatus,
        employeeName: conv.employeeName,
        merchantName: conv.merchantName,
      );
    notifyListeners();
    MerchantNotificationService.instance.onLocalRead(orderId);
  }

  void clear() {
    _byOrderId = const {};
    _lastMerchantId = null;
    notifyListeners();
  }

  String? get lastMerchantId => _lastMerchantId;
}
