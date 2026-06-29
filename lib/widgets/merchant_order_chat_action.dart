import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/chat/order_conversation_page.dart';
import '../models/order_model.dart';
import '../state/merchant_conversation_state.dart';
import '../theme/app_theme.dart';

/// 商家端订单「联系顾客」入口。
///
/// - 无未读：低调描边「联系顾客」
/// - 有未读：醒目「未读 N」/「新消息」+ 红点
class MerchantOrderChatAction extends StatelessWidget {
  final Order order;
  final int unreadCount;
  final bool compact;
  final bool iconOnly;

  const MerchantOrderChatAction({
    super.key,
    required this.order,
    this.unreadCount = 0,
    this.compact = false,
    this.iconOnly = false,
  });

  static int unreadOf(BuildContext context, String orderId) {
    try {
      return context
          .watch<MerchantConversationState>()
          .unreadForOrder(orderId);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _openChat(BuildContext context) async {
    await OrderConversationPage.open(
      context,
      order: order,
      asMerchant: true,
    );
    if (!context.mounted) return;
    try {
      final merchantId = order.merchantId;
      final convState = context.read<MerchantConversationState>();
      await convState.refresh(merchantId: merchantId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final unread = unreadCount;
    if (iconOnly) {
      return _SubtleIconButton(unread: unread, onTap: () => _openChat(context));
    }
    if (compact) {
      return unread > 0
          ? _UnreadChip(unread: unread, onTap: () => _openChat(context))
          : _SubtleCompactButton(onTap: () => _openChat(context));
    }
    return unread > 0
        ? _UnreadFullButton(unread: unread, onTap: () => _openChat(context))
        : _SubtleFullButton(onTap: () => _openChat(context));
  }
}

/// 订单卡片右上角未读角标（仅 unread > 0 时显示）
class MerchantOrderUnreadDot extends StatelessWidget {
  final int unreadCount;

  const MerchantOrderUnreadDot({super.key, required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    if (unreadCount <= 0) return const SizedBox.shrink();
    return Positioned(
      top: 6,
      right: 6,
      child: MerchantUnreadBadge(count: unreadCount),
    );
  }
}

class MerchantUnreadBadge extends StatelessWidget {
  final int count;
  final double size;

  const MerchantUnreadBadge({
    super.key,
    required this.count,
    this.size = 8,
  });

  static String label(int count) {
    if (count <= 0) return '';
    if (count > 9) return '9+';
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    if (count <= 9 && size <= 10) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFFEF4444),
          shape: BoxShape.circle,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
      alignment: Alignment.center,
      child: Text(
        label(count),
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _SubtleCompactButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SubtleCompactButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 13,
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 3),
              Text(
                '联系顾客',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadChip extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;

  const _UnreadChip({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = unread == 1 ? '新消息' : '未读 ${MerchantUnreadBadge.label(unread)}';
    return Material(
      color: const Color(0xFFFFEBEB),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.mark_chat_unread_outlined,
                size: 14,
                color: Color(0xFFDC2626),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtleFullButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SubtleFullButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        onPressed: onTap,
        icon: Icon(
          Icons.chat_bubble_outline,
          size: 18,
          color: AppColors.textSecondary.withValues(alpha: 0.9),
        ),
        label: const Text(
          '联系顾客',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _UnreadFullButton extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;

  const _UnreadFullButton({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label =
        unread == 1 ? '新消息 · 联系顾客' : '未读 ${MerchantUnreadBadge.label(unread)} · 联系顾客';
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          elevation: 0,
        ),
        onPressed: onTap,
        icon: const Icon(Icons.mark_chat_unread_outlined, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _SubtleIconButton extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;

  const _SubtleIconButton({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (unread > 0) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.mark_chat_unread_outlined,
                size: 22,
                color: Color(0xFFDC2626),
              ),
              Positioned(
                top: -4,
                right: -8,
                child: MerchantUnreadBadge(count: unread, size: 14),
              ),
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.chat_bubble_outline,
          size: 20,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
