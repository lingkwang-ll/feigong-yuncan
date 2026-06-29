import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/api_config.dart';
import '../theme/app_theme.dart';
import '../utils/image_pick_upload.dart';

/// 员工头像：支持本地预览、上传与默认图
class EmployeeAvatar extends StatefulWidget {
  final String? avatarUrl;
  final double size;
  final bool editable;
  final Future<bool> Function(Uint8List bytes, String filename)? onUpload;

  const EmployeeAvatar({
    super.key,
    this.avatarUrl,
    this.size = 64,
    this.editable = false,
    this.onUpload,
  });

  @override
  State<EmployeeAvatar> createState() => _EmployeeAvatarState();
}

class _EmployeeAvatarState extends State<EmployeeAvatar> {
  Uint8List? _previewBytes;
  bool _uploading = false;

  @override
  void didUpdateWidget(covariant EmployeeAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl && _previewBytes == null) {
      setState(() {});
    }
  }

  Future<void> _handleTap() async {
    if (!widget.editable || widget.onUpload == null || _uploading) return;
    final bytes = await pickImageBytes(context);
    if (bytes == null) return;
    setState(() {
      _previewBytes = bytes;
      _uploading = true;
    });
    final ok = await widget.onUpload!(bytes, 'avatar.jpg');
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (ok) _previewBytes = null;
    });
    if (!ok) {
      setState(() => _previewBytes = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像上传失败，请重试')),
      );
    }
  }

  Widget _buildImage() {
    if (_previewBytes != null) {
      return Image.memory(
        _previewBytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }
    final raw = widget.avatarUrl;
    if (raw != null && raw.isNotEmpty) {
      if (raw.startsWith('data:')) {
        try {
          return Image.memory(
            UriData.parse(raw).contentAsBytes(),
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => _defaultAvatar(),
          );
        } catch (_) {
          return _defaultAvatar();
        }
      }
      final url = resolveAssetUrl(raw) ?? raw;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return Image.network(
          url,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _defaultAvatar(),
        );
      }
    }
    return _defaultAvatar();
  }

  Widget _defaultAvatar() {
    return Image.asset(
      'assets/images/ui/user_avatar.png',
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = ClipOval(child: _buildImage());
    if (!widget.editable) {
      return SizedBox(width: widget.size, height: widget.size, child: avatar);
    }
    return GestureDetector(
      onTap: _handleTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(width: widget.size, height: widget.size, child: avatar),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white, width: 2),
                ),
              ),
              alignment: Alignment.center,
              child: _uploading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt, color: Colors.white, size: 12),
            ),
          ),
        ],
      ),
    );
  }
}
