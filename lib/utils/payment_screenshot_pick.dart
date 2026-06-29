import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const int kPaymentScreenshotMaxBytes = 10 * 1024 * 1024;

const _allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

class PickedPaymentScreenshot {
  final Uint8List bytes;
  final String filename;

  const PickedPaymentScreenshot({
    required this.bytes,
    required this.filename,
  });
}

/// 选择付款截图（Web / 桌面优先文件选择器，兼容 Chrome 调试）
Future<PickedPaymentScreenshot?> pickPaymentScreenshot(
  BuildContext context,
) async {
  if (!kIsWeb) {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('从文件选择'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source != 'file') return null;
  }

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _allowedExtensions,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final picked = result.files.single;
  final bytes = picked.bytes;
  if (bytes == null || bytes.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未读取到文件，请重新选择')),
      );
    }
    return null;
  }

  final ext = _normalizeExt(picked.extension ?? picked.name);
  if (!_allowedExtensions.contains(ext)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅支持 jpg / jpeg / png / webp 格式')),
      );
    }
    return null;
  }

  if (bytes.length > kPaymentScreenshotMaxBytes) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片过大，请选择 10MB 以内的文件')),
      );
    }
    return null;
  }

  final filename = picked.name.isNotEmpty
      ? picked.name
      : 'payment_${DateTime.now().millisecondsSinceEpoch}.$ext';

  return PickedPaymentScreenshot(bytes: bytes, filename: filename);
}

String _normalizeExt(String raw) {
  final name = raw.trim().toLowerCase();
  if (name.contains('.')) {
    return name.split('.').last;
  }
  return name;
}
