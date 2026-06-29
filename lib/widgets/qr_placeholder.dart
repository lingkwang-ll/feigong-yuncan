import 'package:flutter/material.dart';

import '../api/api_config.dart';
import '../theme/app_theme.dart';

/// 收款码组件 —— 严格按 04_employee_payment_upload.png 复刻
///
/// 视觉规范：
/// - 白色卡片 + 浅绿圆角边框
/// - 中央：固定使用静态资源 `assets/images/ui/payment_qr.png`
///   （PNG 自带中心 P+ Logo，无需再叠加 CustomPainter）
/// - 当 [seed] 是真实图片路径（远端 / uploads）时，优先用真实图
class QrPlaceholder extends StatelessWidget {
  final double size;
  final String seed;

  const QrPlaceholder({
    super.key,
    this.size = 220,
    this.seed = 'default',
  });

  bool get _isRemoteImage =>
      seed.startsWith('http://') ||
      seed.startsWith('https://') ||
      seed.startsWith('/uploads/');

  static const String _qrAsset = 'assets/images/ui/payment_qr.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primaryLight, width: 2),
      ),
      child: _isRemoteImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.network(
                resolveAssetUrl(seed) ?? seed,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => _localQr(),
              ),
            )
          : _localQr(),
    );
  }

  Widget _localQr() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image.asset(
        _qrAsset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
