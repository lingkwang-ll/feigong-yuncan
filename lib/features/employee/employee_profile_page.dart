import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/change_password_sheet.dart';
import '../../widgets/employee_avatar.dart';
import '../../widgets/account_login_status_tile.dart';
import '../../widgets/notification_setting_tiles.dart';
import '../../features/chat/support_conversation_page.dart';
import '../../state/support_conversation_state.dart';
import '../auth/login_page.dart';
import 'employee_address_list_page.dart';
import 'employee_shell.dart';

/// 员工端"我的" - 参考 06_employee_profile.png
class EmployeeProfilePage extends StatelessWidget {
  const EmployeeProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final supportUnread = context.watch<SupportConversationState>().unreadCount;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // 顶部 Hero 区：右上叶子+碗 装饰 + 左侧 Logo / 标题 / 副标
            SizedBox(
              height: 130,
              child: Stack(
                children: [
                  // 右上装饰图（profile_hero_top.png）
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/ui/profile_hero_top.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.topRight,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  // 左侧 Logo + 文字
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const AppLogo(size: 52, radius: 13),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('非攻云餐',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark,
                                  letterSpacing: 2,
                                )),
                            SizedBox(height: 4),
                            ThemeSlogan(fontSize: 13),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 用户卡片
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    EmployeeAvatar(
                      avatarUrl: user?.avatarUrl,
                      size: 64,
                      editable: user != null,
                      onUpload: user == null
                          ? null
                          : (bytes, filename) => context
                              .read<AppState>()
                              .uploadEmployeeAvatar(bytes, filename),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.name ?? '未登录',
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.phone,
                                  color: AppColors.primary, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                user?.phone ?? '',
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 主题文案
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.local_florist_outlined,
                        color: AppColors.primary, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '企业订餐更健康、更方便',
                        style: TextStyle(
                            fontSize: 14,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: AppColors.primary, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 菜单卡
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x10000000),
                      blurRadius: 10,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _MenuRow(
                      icon: Icons.assignment_outlined,
                      label: '我的订单',
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) =>
                                const EmployeeShell(initialIndex: 1),
                          ),
                        );
                      },
                    ),
                    const Divider(
                        height: 1, indent: 50, endIndent: 14),
                    _MenuRow(
                      icon: Icons.location_on_outlined,
                      label: '收货地址',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const EmployeeAddressListPage(),
                          ),
                        );
                      },
                    ),
                    const Divider(
                        height: 1, indent: 50, endIndent: 14),
                    _MenuRow(
                      icon: Icons.headset_mic_outlined,
                      label: '联系客服',
                      unreadCount: supportUnread,
                      onTap: () => SupportConversationPage.open(context),
                    ),
                    const Divider(
                        height: 1, indent: 50, endIndent: 14),
                    _MenuRow(
                      icon: Icons.settings_outlined,
                      label: '设置',
                      onTap: () => _showSettings(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AccountLoginStatusTile(),
            const EmployeeNotificationSettingTile(),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: AppColors.primary),
              title: const Text('修改密码'),
              onTap: () {
                Navigator.pop(ctx);
                showChangePasswordSheet(context).then((_) {
                  if (!context.mounted) return;
                  if (context.read<AppState>().currentUser == null) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (_) => false,
                    );
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('退出登录', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _showLogout(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AppState>().logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (_) => const LoginPage()),
                (_) => false,
              );
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int unreadCount;
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textPrimary)),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const Spacer(),
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}
