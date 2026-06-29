import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/support_api.dart';

/// 平台客服未读数（员工/商家「联系客服」角标）
class SupportConversationState extends ChangeNotifier {
  SupportConversationState({SupportApi? api}) : _api = api;

  SupportApi? _api;
  int _unreadCount = 0;
  bool _loading = false;

  int get unreadCount => _unreadCount;

  void bindApi(ApiClient client) {
    _api = SupportApi(client);
  }

  Future<void> refreshUnread() async {
    if (_api == null) return;
    if (_loading) return;
    _loading = true;
    try {
      _unreadCount = await _api!.fetchUnreadCount();
      notifyListeners();
    } catch (_) {
      // 静默失败
    } finally {
      _loading = false;
    }
  }

  void setUnreadCount(int count) {
    if (_unreadCount == count) return;
    _unreadCount = count;
    notifyListeners();
  }

  void clearUnread() => setUnreadCount(0);
}
