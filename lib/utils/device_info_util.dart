import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// 构建设备信息字符串，供协议签署留存
String buildDeviceInfo() {
  if (kIsWeb) return 'web';
  try {
    return '${Platform.operatingSystem}; ${Platform.operatingSystemVersion}';
  } catch (_) {
    return defaultTargetPlatform.name;
  }
}

String agreementClientTimeIso() =>
    DateTime.now().toUtc().toIso8601String();
