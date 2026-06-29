/// 与后端 `conversation_messages` 表对齐的消息模型。
///
/// - `text`：纯文本
/// - `emoji`：纯 emoji 字符串（前端可单独展示放大字号）
/// - `image`：图片消息，`imageUrl` 必填
/// - `system`：系统消息（订单已提交、商家已接单等），居中灰色展示
enum ChatMessageType { text, emoji, image, system }

enum ChatSenderType { employee, merchant, system, admin }

ChatMessageType _parseType(String? raw) {
  switch (raw) {
    case 'text':
      return ChatMessageType.text;
    case 'emoji':
      return ChatMessageType.emoji;
    case 'image':
      return ChatMessageType.image;
    case 'system':
      return ChatMessageType.system;
    default:
      return ChatMessageType.text;
  }
}

ChatSenderType _parseSender(String? raw) {
  switch (raw) {
    case 'employee':
      return ChatSenderType.employee;
    case 'merchant':
      return ChatSenderType.merchant;
    case 'admin':
      return ChatSenderType.admin;
    case 'system':
    default:
      return ChatSenderType.system;
  }
}

class ConversationMessage {
  final String id;
  final String conversationId;
  final ChatSenderType senderType;
  final String? senderId;
  final ChatMessageType messageType;
  final String? content;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? readAt;

  const ConversationMessage({
    required this.id,
    required this.conversationId,
    required this.senderType,
    required this.messageType,
    required this.createdAt,
    this.senderId,
    this.content,
    this.imageUrl,
    this.readAt,
  });

  bool get isSystem => messageType == ChatMessageType.system;
  bool get isImage => messageType == ChatMessageType.image;

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic v) {
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }

    return ConversationMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderType: _parseSender(json['senderType'] as String?),
      senderId: json['senderId'] as String?,
      messageType: _parseType(json['messageType'] as String?),
      content: json['content'] as String?,
      imageUrl: json['imageUrl'] as String?,
      createdAt: parseTime(json['createdAt']),
      readAt: json['readAt'] != null && (json['readAt'] as String).isNotEmpty
          ? DateTime.tryParse(json['readAt'] as String)?.toLocal()
          : null,
    );
  }
}
