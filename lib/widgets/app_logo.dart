import 'package:flutter/material.dart';

import '../api/api_config.dart';
import '../theme/app_theme.dart';

/// 非攻云餐 P+ Logo（官方 PNG，完整显示、不裁切、不拉伸）
///
/// - 小图：assets/images/ui/app_logo_small.png（512×512）
/// - 大图：assets/images/ui/app_logo_large.png（1024×1024，与 small 同源裁切）
class AppLogo extends StatelessWidget {
  final double size;

  static const String _assetLarge = 'assets/images/ui/app_logo_large.png';
  static const String _assetSmall = 'assets/images/ui/app_logo_small.png';

  /// [size] 必须为正方形边长；[radius] 保留兼容旧调用，不再用于裁切。
  const AppLogo({super.key, required this.size, this.radius = 14});

  final double radius;

  String get _asset => size <= 48 ? _assetSmall : _assetLarge;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        _asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (ctx, err, st) => Image.asset(
          _assetSmall,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// 带"非攻云餐"文字的横向 Logo
class AppLogoTitle extends StatelessWidget {
  final double logoSize;
  final double fontSize;
  final Color textColor;
  final String? subtitle;
  final Color? subtitleColor;

  const AppLogoTitle({
    super.key,
    this.logoSize = 40,
    this.fontSize = 22,
    this.textColor = AppColors.primaryDark,
    this.subtitle,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '非攻云餐',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: textColor,
                letterSpacing: 2,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: fontSize * 0.5,
                  color: subtitleColor ?? AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 商家小 Logo — 有自定义 logo 时显示网络图，否则 P+ Logo
class MerchantBadgeLogo extends StatelessWidget {
  final String seed;
  final double size;
  final double radius;

  const MerchantBadgeLogo({
    super.key,
    required this.seed,
    this.size = 40,
    this.radius = 10,
  });

  bool get _isRemote =>
      seed.startsWith('/uploads/') ||
      seed.startsWith('http://') ||
      seed.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (!_isRemote) {
      return AppLogo(size: size, radius: radius);
    }
    final resolved = resolveAssetUrl(seed) ?? seed;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        resolved,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => AppLogo(size: size, radius: radius),
      ),
    );
  }
}

/// 主题副标题 零抽成·直供餐·更实惠
class ThemeSlogan extends StatelessWidget {
  final double fontSize;
  const ThemeSlogan({super.key, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: fontSize,
      color: AppColors.primary,
      fontWeight: FontWeight.w500,
    );
    final accent = base.copyWith(color: AppColors.accent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('零抽成', style: base),
        Text('  ·  ', style: base.copyWith(color: AppColors.textSecondary)),
        Text('直供餐', style: accent),
        Text('  ·  ', style: base.copyWith(color: AppColors.textSecondary)),
        Text('更实惠', style: base),
      ],
    );
  }
}
