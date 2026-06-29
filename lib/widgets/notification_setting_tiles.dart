import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/notification_settings.dart';

/// 商家端提示音开关（设置页）
class MerchantNotificationSettingTiles extends StatefulWidget {
  const MerchantNotificationSettingTiles({super.key});

  @override
  State<MerchantNotificationSettingTiles> createState() =>
      _MerchantNotificationSettingTilesState();
}

class _MerchantNotificationSettingTilesState
    extends State<MerchantNotificationSettingTiles> {
  bool _newOrder = true;
  bool _message = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await NotificationSettings.load();
    if (!mounted) return;
    setState(() {
      _newOrder = NotificationSettings.merchantNewOrderSoundEnabled;
      _message = NotificationSettings.merchantMessageSoundEnabled;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: const Text('新订单提示音'),
          subtitle: const Text('顾客完成支付后可接单时提醒'),
          value: _newOrder,
          activeThumbColor: AppColors.primary,
          onChanged: (v) async {
            setState(() => _newOrder = v);
            await NotificationSettings.setMerchantNewOrderSound(v);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.chat_bubble_outline),
          title: const Text('消息提示音'),
          subtitle: const Text('顾客发送文字或图片时提醒'),
          value: _message,
          activeThumbColor: AppColors.primary,
          onChanged: (v) async {
            setState(() => _message = v);
            await NotificationSettings.setMerchantMessageSound(v);
          },
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// 员工端消息提示音开关（设置页）
class EmployeeNotificationSettingTile extends StatefulWidget {
  const EmployeeNotificationSettingTile({super.key});

  @override
  State<EmployeeNotificationSettingTile> createState() =>
      _EmployeeNotificationSettingTileState();
}

class _EmployeeNotificationSettingTileState
    extends State<EmployeeNotificationSettingTile> {
  bool _message = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await NotificationSettings.load();
    if (!mounted) return;
    setState(() {
      _message = NotificationSettings.employeeMessageSoundEnabled;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return SwitchListTile(
      secondary: const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
      title: const Text('消息提示音'),
      subtitle: const Text('商家回复文字或图片时提醒'),
      value: _message,
      activeThumbColor: AppColors.primary,
      onChanged: (v) async {
        setState(() => _message = v);
        await NotificationSettings.setEmployeeMessageSound(v);
      },
    );
  }
}
