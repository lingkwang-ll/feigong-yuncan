import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 设置页登录状态说明（不展示 token 等技术信息）
class AccountLoginStatusTile extends StatelessWidget {
  const AccountLoginStatusTile({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    if (user == null) return const SizedBox.shrink();
    final subtitle = user.name.trim().isNotEmpty ? user.name.trim() : user.phone;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.verified_user_outlined,
              color: AppColors.primary),
          title: const Text('当前账号已登录'),
          subtitle: Text(subtitle),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
