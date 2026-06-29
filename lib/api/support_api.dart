import 'dart:typed_data';

import '../models/support_conversation_model.dart';
import 'api_client.dart';

class SupportApi {
  SupportApi(this._client);

  final ApiClient _client;

  Future<SupportConversation> getOrCreateConversation() async {
    final data = await _client.get('/support/conversation');
    return SupportConversation.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<List<SupportMessage>> listMessages() async {
    final data = await _client.get('/support/conversation/messages');
    final list = data as List? ?? const [];
    return list
        .map((e) =>
            SupportMessage.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<SupportMessage> sendText(String content) async {
    final data = await _client.post(
      '/support/conversation/messages',
      body: {'messageType': 'text', 'content': content},
    );
    return SupportMessage.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<SupportMessage> sendEmoji(String emoji) async {
    final data = await _client.post(
      '/support/conversation/messages',
      body: {'messageType': 'emoji', 'content': emoji},
    );
    return SupportMessage.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<SupportMessage> uploadAndSendImage(
    Uint8List bytes,
    String filename,
  ) async {
    final data = await _client.uploadBytes(
      '/support/conversation/images',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return SupportMessage.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<SupportConversation> markRead() async {
    final data = await _client.post('/support/conversation/read');
    return SupportConversation.fromJson((data as Map).cast<String, dynamic>());
  }

  Future<int> fetchUnreadCount() async {
    final data = await _client.get('/support/unread-count');
    final map = (data as Map).cast<String, dynamic>();
    return (map['count'] as num?)?.toInt() ?? 0;
  }
}
