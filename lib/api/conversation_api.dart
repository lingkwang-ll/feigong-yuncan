// ignore_for_file: use_null_aware_elements

import 'dart:typed_data';

import '../models/conversation_message_model.dart';
import '../models/conversation_model.dart';
import 'api_client.dart';

/// 订单沟通会话 API（与 `server/src/routes/conversation.routes.ts` 对齐）
///
/// 员工/管理员侧基础路径：`/api/conversations`
/// 商家/管理员侧基础路径：`/api/merchant/conversations`
///
/// 注意：客户端始终通过 [asMerchant] 显式声明走哪一侧，
/// 避免误用接口而引发 403。
class ConversationApi {
  ConversationApi(this._client);

  final ApiClient _client;

  // ---------- 员工 / 平台管理员侧 ----------

  /// GET /api/conversations/order/:orderId
  ///
  /// 若该订单还没有会话会自动创建。
  Future<Conversation> getOrCreateForOrder(String orderId) async {
    final data = await _client.get('/conversations/order/$orderId');
    return Conversation.fromJson((data as Map).cast<String, dynamic>());
  }

  /// GET /api/merchant/conversations/order/:orderId
  Future<Conversation> getOrCreateForOrderAsMerchant(String orderId) async {
    final data = await _client.get('/merchant/conversations/order/$orderId');
    return Conversation.fromJson((data as Map).cast<String, dynamic>());
  }

  /// 拉取消息列表
  ///
  /// [asMerchant] 必须与登录用户一致，否则后端会 403。
  Future<List<ConversationMessage>> listMessages(
    String conversationId, {
    required bool asMerchant,
  }) async {
    final prefix = asMerchant ? '/merchant/conversations' : '/conversations';
    final data = await _client.get('$prefix/$conversationId/messages');
    final list = (data as List? ?? const []);
    return list
        .map((e) =>
            ConversationMessage.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 发送文字消息（messageType=text）
  Future<ConversationMessage> sendText(
    String conversationId, {
    required String content,
    required bool asMerchant,
  }) {
    return _sendMessage(
      conversationId,
      asMerchant: asMerchant,
      messageType: 'text',
      content: content,
    );
  }

  /// 发送 emoji 消息（messageType=emoji，content 为纯 emoji）
  Future<ConversationMessage> sendEmoji(
    String conversationId, {
    required String emoji,
    required bool asMerchant,
  }) {
    return _sendMessage(
      conversationId,
      asMerchant: asMerchant,
      messageType: 'emoji',
      content: emoji,
    );
  }

  /// 上传并发送一条图片消息。
  ///
  /// 后端 `conversationImage` 会：上传 → 鉴权 → 写一条 image 消息并返回 DTO。
  Future<ConversationMessage> uploadAndSendImage(
    String conversationId, {
    required Uint8List bytes,
    required String filename,
    required bool asMerchant,
  }) async {
    final prefix = asMerchant ? '/merchant/conversations' : '/conversations';
    final data = await _client.uploadBytes(
      '$prefix/$conversationId/images',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return ConversationMessage.fromJson((data as Map).cast<String, dynamic>());
  }

  /// 标记会话已读，后端会清零对应角色的 unreadCount。
  Future<Conversation> markRead(
    String conversationId, {
    required bool asMerchant,
  }) async {
    final prefix = asMerchant ? '/merchant/conversations' : '/conversations';
    final data = await _client.post('$prefix/$conversationId/read');
    return Conversation.fromJson((data as Map).cast<String, dynamic>());
  }

  /// 商家获取自己的会话列表（按更新时间倒序，附 orderNo/orderStatus/employeeName）
  Future<List<Conversation>> listForMerchant({String? merchantId}) async {
    final data = await _client.get(
      '/merchant/conversations',
      query: {
        if (merchantId != null && merchantId.isNotEmpty)
          'merchantId': merchantId,
      },
    );
    final list = (data as List? ?? const []);
    return list
        .map((e) => Conversation.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 员工获取自己的会话列表
  Future<List<Conversation>> listForEmployee() async {
    final data = await _client.get('/conversations');
    final list = (data as List? ?? const []);
    return list
        .map((e) => Conversation.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<ConversationMessage> _sendMessage(
    String conversationId, {
    required bool asMerchant,
    required String messageType,
    String? content,
    String? imageUrl,
  }) async {
    final prefix = asMerchant ? '/merchant/conversations' : '/conversations';
    final data = await _client.post(
      '$prefix/$conversationId/messages',
      body: {
        'messageType': messageType,
        if (content != null) 'content': content,
        if (imageUrl != null) 'imageUrl': imageUrl,
      },
    );
    return ConversationMessage.fromJson((data as Map).cast<String, dynamic>());
  }
}
