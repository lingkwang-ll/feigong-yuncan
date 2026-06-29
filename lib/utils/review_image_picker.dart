import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'review_image_picker_stub.dart'
    if (dart.library.html) 'review_image_picker_web.dart';

const int kReviewImageMaxBytes = 10 * 1024 * 1024;
const int kReviewImageMaxCount = 9;

const _allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

class PickedReviewImage {
  final Uint8List bytes;
  final String filename;

  const PickedReviewImage({
    required this.bytes,
    required this.filename,
  });
}

String _normalizeExt(String? ext, String name) {
  var e = (ext ?? '').toLowerCase().trim();
  if (e.isEmpty) {
    final dot = name.lastIndexOf('.');
    if (dot >= 0) e = name.substring(dot + 1).toLowerCase();
  }
  if (e == 'jpeg') return 'jpg';
  return e;
}

bool _isAllowedExt(String ext) => _allowedExtensions.contains(ext);

PickedReviewImage? _fromPlatformFile(PlatformFile picked) {
  final bytes = picked.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  final ext = _normalizeExt(picked.extension, picked.name);
  if (!_isAllowedExt(ext)) return null;
  if (bytes.length > kReviewImageMaxBytes) return null;
  final filename = picked.name.isNotEmpty ? picked.name : 'review.$ext';
  return PickedReviewImage(bytes: bytes, filename: filename);
}

Future<String?> _showSourceSheet(BuildContext context) {
  return showModalBottomSheet<String>(
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
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('拍照'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册/文件选择'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('取消'),
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<PickedReviewImage?> pickReviewImage(BuildContext context) async {
  final source = await _showSourceSheet(context);
  if (source == null || !context.mounted) return null;

  if (source == 'camera') {
    if (kIsWeb) {
      final picked = await pickReviewImageFromCameraWeb();
      if (picked == null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前浏览器不支持直接拍照，请从相册/文件选择'),
          ),
        );
      }
      return picked;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前环境请从相册/文件选择图片')),
      );
    }
    return null;
  }

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _allowedExtensions,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final picked = _fromPlatformFile(result.files.single);
  if (picked == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅支持 jpg / jpeg / png / webp，且不超过 10MB')),
      );
    }
    return null;
  }
  if (picked.bytes.length > kReviewImageMaxBytes) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('单张图片不能超过 10MB')),
      );
    }
    return null;
  }
  return picked;
}

bool isLocalOrBlobImageUrl(String url) {
  final u = url.trim().toLowerCase();
  return u.startsWith('local://') ||
      u.startsWith('blob:') ||
      u.startsWith('file://');
}
