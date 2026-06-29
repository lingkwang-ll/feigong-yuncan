import 'display_text_util.dart';

export 'display_text_util.dart';

/// 聊天页展示名解析：避免显示 `????` 等乱码占位。
String resolveChatDisplayName(String? raw, {required String fallback}) {
  final n = (raw ?? '').trim();
  if (n.isEmpty || looksLikeGarbledDisplayText(n)) return fallback;
  return n;
}

bool looksLikeGarbledChatName(String s) => looksLikeGarbledDisplayText(s);
