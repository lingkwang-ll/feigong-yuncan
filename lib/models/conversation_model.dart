/// 订单会话模型（与后端 conversations 表对齐）。
///
/// 每个订单一个会话；商家、员工各自维护未读数。
class Conversation {
  final String id;
  final String type; // 当前只有 'order'
  final String orderId;
  final String merchantId;
  final String? employeeId;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final int employeeUnreadCount;
  final int merchantUnreadCount;
  final String status; // 'open' | 'closed'
  final DateTime createdAt;
  final DateTime updatedAt;

  // 后端列表接口顺带返回的上下文，便于商家列表直接展示
  final String? orderNo;
  final String? orderStatus;
  final String? employeeName;
  final String? merchantName;

  const Conversation({
    required this.id,
    required this.type,
    required this.orderId,
    required this.merchantId,
    required this.employeeUnreadCount,
    required this.merchantUnreadCount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.employeeId,
    this.lastMessageText,
    this.lastMessageAt,
    this.orderNo,
    this.orderStatus,
    this.employeeName,
    this.merchantName,
  });

  bool get isOpen => status == 'open';

  int unreadFor({required bool asEmployee}) =>
      asEmployee ? employeeUnreadCount : merchantUnreadCount;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(dynamic v, {DateTime? fallback}) {
      if (v is String && v.isNotEmpty) {
        return DateTime.tryParse(v)?.toLocal() ?? (fallback ?? DateTime.now());
      }
      return fallback ?? DateTime.now();
    }

    return Conversation(
      id: json['id'] as String,
      type: (json['type'] as String?) ?? 'order',
      orderId: json['orderId'] as String,
      merchantId: json['merchantId'] as String,
      employeeId: json['employeeId'] as String?,
      lastMessageText: json['lastMessageText'] as String?,
      lastMessageAt: json['lastMessageAt'] is String &&
              (json['lastMessageAt'] as String).isNotEmpty
          ? DateTime.tryParse(json['lastMessageAt'] as String)?.toLocal()
          : null,
      employeeUnreadCount: (json['employeeUnreadCount'] as num?)?.toInt() ?? 0,
      merchantUnreadCount: (json['merchantUnreadCount'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? 'open',
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      orderNo: json['orderNo'] as String?,
      orderStatus: json['orderStatus'] as String?,
      employeeName: json['employeeName'] as String?,
      merchantName: json['merchantName'] as String?,
    );
  }
}
