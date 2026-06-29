import 'dart:convert';

/// JWT 工具（仅解析 exp，不校验签名；完整校验由服务端完成）
class JwtUtil {
  JwtUtil._();

  static bool isExpired(String token, {Duration leeway = Duration.zero}) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (payload is! Map) return true;
      final exp = payload['exp'];
      if (exp is! num) return true;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return DateTime.now().isAfter(expiresAt.subtract(leeway));
    } catch (_) {
      return true;
    }
  }
}
