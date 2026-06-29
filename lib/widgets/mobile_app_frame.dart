import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 移动端外壳
///
/// 用于把 Flutter App 在桌面 / Web 等宽屏环境下，
/// 强制约束到一台"模拟手机"的尺寸内，避免布局被拉成网页表单。
///
/// 使用方式：在 [MaterialApp.builder] 中包一层：
/// ```dart
/// MaterialApp(
///   builder: (context, child) => MobileAppFrame(child: child ?? const SizedBox.shrink()),
///   ...
/// )
/// ```
///
/// 真机 / 已经是手机尺寸时不会限制，外侧也不会出现"双背景"。
class MobileAppFrame extends StatelessWidget {
  final Widget child;

  /// 模拟手机宽度（参考主流 iPhone 设计稿）
  final double maxWidth;

  /// 模拟手机高度（仅在屏幕足够高时使用，否则铺满）
  final double maxHeight;

  const MobileAppFrame({
    super.key,
    required this.child,
    this.maxWidth = 430,
    this.maxHeight = 920,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;

    // 真机或小屏：不做任何包装，避免出现"边框感"
    final needFrame = _shouldFrame(size.width);
    if (!needFrame) {
      return child;
    }

    final w = size.width < maxWidth ? size.width : maxWidth;
    final h = size.height < maxHeight ? size.height : maxHeight;

    return ColoredBox(
      // 模拟手机外侧的"桌面背景"
      color: const Color(0xFFEDE7DA),
      child: Center(
        child: SizedBox(
          width: w,
          height: h,
          child: ClipRRect(
            // Web 端给一个圆角，强化"手机壳"视觉
            borderRadius: BorderRadius.circular(kIsWeb ? 28 : 0),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.background,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  static bool _shouldFrame(double screenWidth) {
    // Web / 桌面：超过 500px 才启用，避免移动浏览器被无谓裁切
    if (kIsWeb) return screenWidth > 500;
    // 桌面平台同理
    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return screenWidth > 500;
      default:
        return false;
    }
  }
}
