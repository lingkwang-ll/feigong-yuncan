enum SupportMessageType { text, emoji, image, system }

enum SupportSenderType { user, admin, system }

SupportMessageType _parseType(String? raw) {
  switch (raw) {
    case 'emoji':
      return SupportMessageType.emoji;
    case 'image':
      return SupportMessageType.image;
    case 'system':
      return SupportMessageType.system;
    default:
      return SupportMessageType.text;
  }
}

SupportSenderType _parseSender(String? raw) {
  switch (raw) {
    case 'user':
      return SupportSenderType.user;
    case 'admin':
      return SupportSenderType.admin;
    default:
      return SupportSenderType.system;
  }
}

class SupportMessage {
  final String id;
  final String conversationId;
  final SupportSenderType senderType;
  final String? senderId;
  final SupportMessageType messageType;
  final String? content;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? readAt;

  const SupportMessage({
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

  bool get isSystem => messageType == SupportMessageType.system;

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic v) {
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }

    return SupportMessage(
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

class SupportConversation {
  final String id;
  final String userId;
  final String userRole;
  final String? merchantId;
  final String title;
  final String status;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final int userUnreadCount;
  final int adminUnreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SupportConversation({
    required this.id,
    required this.userId,
    required this.userRole,
    required this.title,
    required this.status,
    required this.userUnreadCount,
    required this.adminUnreadCount,
    required this.createdAt,
    required this.updatedAt,
    this.merchantId,
    this.lastMessageText,
    this.lastMessageAt,
  });

  factory SupportConversation.fromJson(Map<String, dynamic> json) {
    DateTime? parseOpt(dynamic v) {
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v)?.toLocal();
      }
      return null;
    }

    return SupportConversation(
      id: json['id'] as String,
      userId: json['userId'] as String,
      userRole: json['userRole'] as String? ?? 'employee',
      merchantId: json['merchantId'] as String?,
      title: json['title'] as String? ?? '平台客服',
      status: json['status'] as String? ?? 'open',
      lastMessageText: json['lastMessageText'] as String?,
      lastMessageAt: parseOpt(json['lastMessageAt']),
      userUnreadCount: (json['userUnreadCount'] as num?)?.toInt() ?? 0,
      adminUnreadCount: (json['adminUnreadCount'] as num?)?.toInt() ?? 0,
      createdAt: parseOpt(json['createdAt']) ?? DateTime.now(),
      updatedAt: parseOpt(json['updatedAt']) ?? DateTime.now(),
    );
  }
}
