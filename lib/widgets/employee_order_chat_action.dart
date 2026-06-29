import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/chat/order_conversation_page.dart';
import '../models/order_model.dart';
import '../state/employee_conversation_state.dart';
import '../theme/app_theme.dart';
import 'merchant_order_chat_action.dart';

/// 员工端订单「联系商家」入口（未读样式与商家端对称）
class EmployeeOrderChatAction extends StatelessWidget {
  final Order order;
  final int unreadCount;
  final bool compact;

  const EmployeeOrderChatAction({
    super.key,
    required this.order,
    this.unreadCount = 0,
    this.compact = true,
  });

  static int unreadOf(BuildContext context, String orderId) {
    try {
      return context
          .watch<EmployeeConversationState>()
          .unreadForOrder(orderId);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _openChat(BuildContext context) async {
    await OrderConversationPage.open(
      context,
      order: order,
      asMerchant: false,
    );
    if (!context.mounted) return;
    try {
      final convState = context.read<EmployeeConversationState>();
      final employeeId = convState.lastEmployeeId;
      if (employeeId != null && employeeId.isNotEmpty) {
        await convState.refresh(employeeId: employeeId);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final unread = unreadCount;
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
                '联系商家',
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
    final label = unread == 1
        ? '未读 1'
        : '未读 ${MerchantUnreadBadge.label(unread)}';
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
      height: 40,
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
          size: 16,
          color: AppColors.textSecondary.withValues(alpha: 0.9),
        ),
        label: const Text(
          '联系商家',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
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
    final label = unread == 1
        ? '未读 1 · 联系商家'
        : '未读 ${MerchantUnreadBadge.label(unread)} · 联系商家';
    return SizedBox(
      width: double.infinity,
      height: 40,
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
        icon: const Icon(Icons.mark_chat_unread_outlined, size: 16),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
