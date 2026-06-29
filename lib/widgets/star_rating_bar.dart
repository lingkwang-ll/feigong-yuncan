import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 1~5 星评分条（与现有 UI 风格一致，使用 Material Icons）
class StarRatingBar extends StatelessWidget {
  final int rating;
  final ValueChanged<int>? onChanged;
  final double size;
  final bool readOnly;

  const StarRatingBar({
    super.key,
    required this.rating,
    this.onChanged,
    this.size = 28,
    this.readOnly = false,
  });

  static const Color _starActive = Color(0xFFFFB020);
  static const Color _starInactive = AppColors.divider;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final star = i + 1;
        final filled = star <= rating;
        return GestureDetector(
          onTap: readOnly || onChanged == null ? null : () => onChanged!(star),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: filled ? _starActive : _starInactive,
            ),
          ),
        );
      }),
    );
  }
}
