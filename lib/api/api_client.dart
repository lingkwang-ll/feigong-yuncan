import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_config.dart';

/// API 异常
class ApiException implements Exception {
  final int? code;
  final String message;
  final String? errorCode; // 后端 error.code（BAD_REQUEST / NOT_FOUND ...）

  ApiException({this.code, required this.message, this.errorCode});

  @override
  String toString() =>
      'ApiException(httpCode: $code, errorCode: $errorCode, message: $message)';
}

enum HttpMethod { get, post, put, patch, delete }

/// 统一 HTTP 封装
///
/// 实现规则（与后端 `server/` 对齐）：
/// - 成功响应：`{ "data": ... }`，本类返回 `data` 部分
/// - 失败响应：`{ "error": { "code": "...", "message": "..." } }`，本类抛 [ApiException]
/// - 所有请求自动附加 JSON 头；如已通过 [setAuthUser] 设置 userId，
///   会自动带 `X-User-Id` 头
class ApiClient {
  ApiClient({this.baseUrl = apiBaseUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  String? _userId;
  String? authToken;

  /// Token 失效（401）时回调，由外层注入以清理登录态
  Future<void> Function()? onUnauthorized;

  void setAuthToken(String? token) {
    authToken = token;
  }

  /// 设置/清空当前登录用户 id（用于带 X-User-Id 头）
  void setAuthUser(String? userId) {
    _userId = userId;
  }

  Map<String, String> _defaultHeaders([Map<String, String>? extra]) {
    final h = <String, String>{
      'Accept': 'application/json',
      if (authToken != null && authToken!.isNotEmpty)
        'Authorization': 'Bearer $authToken',
      if (_userId != null && _userId!.isNotEmpty) 'X-User-Id': _userId!,
    };
    if (extra != null) h.addAll(extra);
    return h;
  }

  Uri _buildUri(String path, Map<String, dynamic>? query) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$p');
    if (query == null || query.isEmpty) return uri;
    final params = <String, String>{};
    query.forEach((k, v) {
      if (v == null) return;
      params[k] = v.toString();
    });
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      ...params,
    });
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _send(HttpMethod.get, path, query: query, headers: headers);

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _send(HttpMethod.post, path,
          body: body, query: query, headers: headers);

  Future<dynamic> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _send(HttpMethod.put, path,
          body: body, query: query, headers: headers);

  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _send(HttpMethod.patch, path,
          body: body, query: query, headers: headers);

  Future<dynamic> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) =>
      _send(HttpMethod.delete, path,
          body: body, query: query, headers: headers);

  /// 根据文件名推断 multipart 图片 Content-Type（Flutter 默认 octet-stream 会被后端拒绝）
  MediaType? _imageMediaTypeForFilename(String filename) {
    final parts = filename.split('.');
    if (parts.length < 2) return null;
    switch (parts.last.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      default:
        return null;
    }
  }

  Future<dynamic> _sendMultipart(
    String path, {
    required String fieldName,
    required Uint8List bytes,
    required String filename,
    Map<String, String>? extraFields,
    Map<String, String>? headers,
  }) async {
    if (bytes.isEmpty) {
      throw ApiException(message: '上传文件为空');
    }
    final uri = _buildUri(path, null);
    if (AppConfig.enableApiLog) {
      debugPrint(
        '[ApiClient][UPLOAD] POST $uri  field=$fieldName  '
        'filename=$filename  size=${bytes.length}  extraFields=$extraFields',
      );
    }
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(_defaultHeaders(headers));
    if (extraFields != null) req.fields.addAll(extraFields);
    req.files.add(http.MultipartFile.fromBytes(
      fieldName,
      bytes,
      filename: filename,
      contentType: _imageMediaTypeForFilename(filename),
    ));

    http.StreamedResponse streamed;
    try {
      streamed = await req
          .send()
          .timeout(Duration(milliseconds: AppConfig.requestTimeoutMs));
    } catch (e) {
      debugPrint('[ApiClient][UPLOAD][FAIL] POST $uri  network: $e');
      throw ApiException(message: '网络异常，请稍后再试');
    }
    final resp = await http.Response.fromStream(streamed);
    try {
      return _decodeResponse(resp);
    } on ApiException catch (e) {
      debugPrint(
        '[ApiClient][UPLOAD][FAIL] POST $uri  '
        'statusCode=${e.code ?? resp.statusCode}  '
        'errorCode=${e.errorCode}  message=${e.message}  '
        'body=${resp.body}',
      );
      rethrow;
    }
  }

  /// 使用真实文件字节上传（multipart/form-data）
  Future<dynamic> uploadBytes(
    String path, {
    required String fieldName,
    required Uint8List bytes,
    required String filename,
    Map<String, String>? extraFields,
    Map<String, String>? headers,
  }) =>
      _sendMultipart(
        path,
        fieldName: fieldName,
        bytes: bytes,
        filename: filename,
        extraFields: extraFields,
        headers: headers,
      );

  /// 文件上传（multipart/form-data，字节流）
  Future<dynamic> uploadFileBytes(
    String path, {
    required String fieldName,
    required Uint8List bytes,
    required String filename,
    Map<String, String>? extraFields,
    Map<String, String>? headers,
  }) =>
      _sendMultipart(
        path,
        fieldName: fieldName,
        bytes: bytes,
        filename: filename,
        extraFields: extraFields,
        headers: headers,
      );

  /// 文件上传（multipart/form-data）
  ///
  /// [filePathOrBase64] 兼容三种形式：
  /// - 本地真实路径：直接读文件流上传（Android/iOS/桌面适用）
  /// - `data:image/png;base64,xxx` 或纯 base64：解码后作为字节流上传
  /// - 其它字符串（如 `local://...`）：上传时被转成 UTF-8 字节占位上传，
  ///   服务端会把它当做一个文件保存（用于演示，未集成 image_picker 时仍可联调）
  Future<dynamic> uploadFile(
    String path, {
    required String fieldName,
    required String filePathOrBase64,
    String? filename,
    Map<String, String>? extraFields,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path, null);
    if (AppConfig.enableApiLog) {
      // ignore: avoid_print
      print('[ApiClient][UPLOAD] $uri  field=$fieldName  '
          'filePathOrBase64=${_brief(filePathOrBase64)}  '
          'extraFields=$extraFields');
    }
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll(_defaultHeaders(headers));
    if (extraFields != null) req.fields.addAll(extraFields);

    final bytes = await _resolveUploadBytes(filePathOrBase64);
    final inferredName =
        filename ?? _inferUploadFilename(filePathOrBase64);
    req.files.add(http.MultipartFile.fromBytes(
      fieldName,
      bytes,
      filename: inferredName,
    ));

    final streamed = await req
        .send()
        .timeout(Duration(milliseconds: AppConfig.requestTimeoutMs));
    final resp = await http.Response.fromStream(streamed);
    return _decodeResponse(resp);
  }

  Future<dynamic> _send(
    HttpMethod method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path, query);
    if (AppConfig.enableApiLog) {
      // ignore: avoid_print
      print(
          '[ApiClient][${method.name.toUpperCase()}] $uri  body=${_brief(body?.toString())}');
    }

    final mergedHeaders = _defaultHeaders({
      if (body != null) 'Content-Type': 'application/json',
      ...?headers,
    });

    final bodyBytes = body == null ? null : utf8.encode(jsonEncode(body));
    final timeout = Duration(milliseconds: AppConfig.requestTimeoutMs);

    http.Response resp;
    try {
      switch (method) {
        case HttpMethod.get:
          resp = await _http.get(uri, headers: mergedHeaders).timeout(timeout);
          break;
        case HttpMethod.post:
          resp = await _http
              .post(uri, headers: mergedHeaders, body: bodyBytes)
              .timeout(timeout);
          break;
        case HttpMethod.put:
          resp = await _http
              .put(uri, headers: mergedHeaders, body: bodyBytes)
              .timeout(timeout);
          break;
        case HttpMethod.patch:
          resp = await _http
              .patch(uri, headers: mergedHeaders, body: bodyBytes)
              .timeout(timeout);
          break;
        case HttpMethod.delete:
          resp = await _http
              .delete(uri, headers: mergedHeaders, body: bodyBytes)
              .timeout(timeout);
          break;
      }
    } catch (e) {
      throw ApiException(message: '网络异常：$e');
    }

    return _decodeResponse(resp);
  }

  /// 解析响应：成功取 `data`，失败抛 ApiException
  dynamic _decodeResponse(http.Response resp) {
    final status = resp.statusCode;
    final raw = resp.body;
    dynamic decoded;
    if (raw.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      } catch (_) {
        if (status >= 200 && status < 300) return raw;
        throw ApiException(code: status, message: raw);
      }
    }

    if (status >= 200 && status < 300) {
      if (decoded is Map && decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    }

    if (status == 401 && onUnauthorized != null) {
      // 401 时异步清理登录态，不阻塞当前异常抛出
      Future<void>(() async {
        try {
          await onUnauthorized!();
        } catch (_) {}
      });
    }

    if (decoded is Map && decoded['error'] is Map) {
      final err = (decoded['error'] as Map).cast<String, dynamic>();
      throw ApiException(
        code: status,
        errorCode: err['code']?.toString(),
        message: err['message']?.toString() ?? 'HTTP $status',
      );
    }
    throw ApiException(code: status, message: decoded?.toString() ?? raw);
  }

  /// 把 [filePathOrBase64] 解码为上传字节流。
  ///
  /// 当前仅支持 base64 / 字符串占位两种形式，
  /// 这样可以在 Flutter Web 上无需 `dart:io`、`image_picker`
  /// 也能跑通联调（上传成功后后端会保存一个占位文件）。
  ///
  /// 接入 `image_picker` 时，调用方可以自己读出 bytes，
  /// 然后改用 [http.MultipartFile.fromBytes] 直接构造上传请求，
  /// 这里保留这个降级路径只是为了"演示版可点击上传"。
  Future<Uint8List> _resolveUploadBytes(String filePathOrBase64) async {
    final b64 = _maybeStripBase64Prefix(filePathOrBase64);
    if (b64 != null) {
      try {
        return base64Decode(b64);
      } catch (_) {
        // 不是合法 base64，继续按字符串处理
      }
    }
    return Uint8List.fromList(utf8.encode(filePathOrBase64));
  }

  String? _maybeStripBase64Prefix(String s) {
    if (s.startsWith('data:')) {
      final idx = s.indexOf(',');
      if (idx > 0) return s.substring(idx + 1);
    }
    // 简单启发式：长度较长 + 仅含 base64 字符
    if (s.length > 100 && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(s)) {
      return s;
    }
    return null;
  }

  String _inferUploadFilename(String s) {
    if (s.startsWith('data:')) return 'upload.bin';
    if (s.startsWith('local://')) {
      return '${s.substring('local://'.length).replaceAll(RegExp(r'[^\w.-]'), '_')}.png';
    }
    if (s.startsWith('/') || s.contains('\\') || s.contains('/')) {
      final base = s.split(RegExp(r'[\\/]+')).last;
      return base.isEmpty ? 'upload.bin' : base;
    }
    return 'upload.bin';
  }

  String _brief(String? s) {
    if (s == null) return 'null';
    if (s.length <= 200) return s;
    return '${s.substring(0, 200)}...';
  }
}
