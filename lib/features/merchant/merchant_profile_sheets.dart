import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/dish_model.dart';
import '../../models/merchant_model.dart';
import '../../state/app_state.dart';
import '../../state/merchant_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_pick_upload.dart';
import '../../utils/zh_time_picker.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/change_password_sheet.dart';
import '../../widgets/account_login_status_tile.dart';
import '../../widgets/notification_setting_tiles.dart';
import '../../widgets/qr_placeholder.dart';
import '../auth/login_page.dart';
import '../legal/legal_document_page.dart';
import '../legal/legal_documents.dart';

export 'merchant_wallet_sheet.dart' show showMerchantWalletSheet;

void showMerchantPaymentQrSheet(BuildContext context) {
  final merchantState = context.read<MerchantState>();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final merchant = merchantState.currentMerchant;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const SizedBox(height: 16),
              const Text(
                '我的收款码',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '员工选择付款截图方式时，可根据支付方式查看对应收款码。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _paymentQrSection(
                context: context,
                title: '微信收款码',
                qrUrl: merchant.effectiveWechatPaymentQr,
                onUpload: () async {
                  final bytes = await pickImageBytes(context);
                  if (bytes == null) return;
                  final ok = await merchantState.changePaymentQrBytes(
                    bytes,
                    'wechat_qr.png',
                    channel: 'wechat',
                  );
                  if (!context.mounted) return;
                  if (ok) {
                    setSheetState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('微信收款码已更换')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('图片上传失败，请重试')),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              _paymentQrSection(
                context: context,
                title: '支付宝收款码',
                qrUrl: merchant.effectiveAlipayPaymentQr,
                onUpload: () async {
                  final bytes = await pickImageBytes(context);
                  if (bytes == null) return;
                  final ok = await merchantState.changePaymentQrBytes(
                    bytes,
                    'alipay_qr.png',
                    channel: 'alipay',
                  );
                  if (!context.mounted) return;
                  if (ok) {
                    setSheetState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('支付宝收款码已更换')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('图片上传失败，请重试')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

Widget _paymentQrSection({
  required BuildContext context,
  required String title,
  required String qrUrl,
  required Future<void> Function() onUpload,
}) {
  final hasQr = qrUrl.isNotEmpty;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        hasQr ? '已上传' : '尚未上传',
        style: TextStyle(
          fontSize: 12,
          color: hasQr ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 10),
      Center(
        child: Container(
          width: 180,
          height: 180,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryLight, width: 2),
          ),
          child: hasQr
              ? QrPlaceholder(seed: qrUrl, size: 164)
              : Image.asset(
                  'assets/images/ui/merchant_payment_qr.png',
                  fit: BoxFit.contain,
                ),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: onUpload,
        icon: const Icon(Icons.upload_file, size: 18),
        label: Text(hasQr ? '更换收款码' : '上传收款码'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size.fromHeight(44),
        ),
      ),
    ],
  );
}

void showMerchantShopInfoSheet(BuildContext context, Merchant merchant) {
  final nameCtrl = TextEditingController(text: merchant.name);
  final contactCtrl = TextEditingController(text: merchant.contactName);
  final phoneCtrl = TextEditingController(
    text: merchant.contactPhone.isNotEmpty
        ? merchant.contactPhone
        : '',
  );
  final addressCtrl = TextEditingController(text: merchant.address);
  final descCtrl = TextEditingController(text: merchant.description);
  var logoUrl = merchant.logo;
  var uploadingLogo = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHandle(),
              const SizedBox(height: 12),
              const Text(
                '店铺信息',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: uploadingLogo
                      ? null
                      : () async {
                          final bytes = await pickImageBytes(context);
                          if (bytes == null) return;
                          setSheet(() => uploadingLogo = true);
                          final ok = await context
                              .read<MerchantState>()
                              .uploadLogoBytes(bytes, 'logo.png');
                          if (!context.mounted) return;
                          setSheet(() => uploadingLogo = false);
                          if (ok) {
                            logoUrl =
                                context.read<MerchantState>().currentMerchant.logo;
                            setSheet(() {});
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('头像上传失败，请重试'),
                              ),
                            );
                          }
                        },
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      MerchantBadgeLogo(seed: logoUrl, size: 72, radius: 14),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: uploadingLogo
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.camera_alt,
                                color: Colors.white, size: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _field('商家名称', nameCtrl),
              _field('联系人', contactCtrl),
              _field('联系电话', phoneCtrl, keyboard: TextInputType.phone),
              _field('店铺地址', addressCtrl, maxLines: 2),
              _field('店铺简介', descCtrl, maxLines: 3),
              const SizedBox(height: 16),
              PrimaryActionButton(
                label: '保 存',
                onPressed: () async {
                  final ok = await context.read<MerchantState>().saveShopProfile(
                        name: nameCtrl.text.trim(),
                        contactName: contactCtrl.text.trim(),
                        contactPhone: phoneCtrl.text.trim(),
                        address: addressCtrl.text.trim(),
                        description: descCtrl.text.trim(),
                        logo: logoUrl,
                      );
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.pop(sheetCtx);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('已保存')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('保存失败，请稍后重试')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

enum _DeliveryOption { delivery, selfPickup, both }

void showMerchantDeliverySheet(BuildContext context, Merchant merchant) {
  _DeliveryOption mode;
  if (merchant.deliveryModes.contains('delivery') &&
      merchant.deliveryModes.contains('selfPickup')) {
    mode = _DeliveryOption.both;
  } else if (merchant.deliveryModes.contains('selfPickup')) {
    mode = _DeliveryOption.selfPickup;
  } else {
    mode = _DeliveryOption.delivery;
  }
  var selectedMode = mode;
  final noteCtrl = TextEditingController(text: merchant.deliveryScope);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(),
            const SizedBox(height: 12),
            const Text(
              '配送设置',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        _modeChip('配送', _DeliveryOption.delivery, selectedMode, (v) {
                          setSheet(() => selectedMode = v);
                        }),
                        _modeChip('自取', _DeliveryOption.selfPickup, selectedMode, (v) {
                          setSheet(() => selectedMode = v);
                        }),
                        _modeChip('都支持', _DeliveryOption.both, selectedMode, (v) {
                          setSheet(() => selectedMode = v);
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _field('配送说明', noteCtrl, maxLines: 2),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryActionButton(
              label: '保 存',
              onPressed: () async {
                final modes = switch (selectedMode) {
                  _DeliveryOption.delivery => ['delivery'],
                  _DeliveryOption.selfPickup => ['selfPickup'],
                  _DeliveryOption.both => ['delivery', 'selfPickup'],
                };
                final current =
                    context.read<MerchantState>().currentMerchant;
                final ok =
                    await context.read<MerchantState>().saveDeliverySettings(
                          deliveryModes: modes,
                          deliveryFee: current.deliveryFee,
                          deliveryScope: noteCtrl.text.trim(),
                          estimatedDeliveryTime: current.estimatedDeliveryTime,
                        );
                if (!context.mounted) return;
                if (ok) {
                  Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('已保存')));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('保存失败，请稍后重试')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void showMerchantBusinessHoursSheet(BuildContext context, Merchant merchant) {
  final meals = MealType.values;
  final enabled = {
    for (final m in meals)
      m.name: merchant.supportedMealTypes.isEmpty
          ? merchant.mealOpeningHours[m.name]?.enabled ?? true
          : merchant.supportedMealTypes.contains(m.name),
  };
  final startTimes = <String, TimeOfDay?>{};
  final endTimes = <String, TimeOfDay?>{};
  for (final m in meals) {
    final setting = merchant.mealOpeningHours[m.name];
    final startStr = setting?.effectiveStart.isNotEmpty == true
        ? setting!.effectiveStart
        : _defaultStart(m);
    final endStr = setting?.effectiveEnd.isNotEmpty == true
        ? setting!.effectiveEnd
        : _defaultEnd(m);
    startTimes[m.name] = _parseTimeOfDay(startStr);
    endTimes[m.name] = _parseTimeOfDay(endStr);
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetHandle(),
              const SizedBox(height: 12),
              const Text(
                '营业时间',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...meals.map((m) {
                final key = m.name;
                final isOn = enabled[key] ?? false;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 72,
                            child: Text(m.label,
                                style: const TextStyle(fontSize: 14)),
                          ),
                          Switch(
                            value: isOn,
                            onChanged: (v) => setSheet(() => enabled[key] = v),
                            activeTrackColor:
                                AppColors.primary.withValues(alpha: 0.5),
                            activeThumbColor: AppColors.primary,
                          ),
                          const Text('启用', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                      if (isOn) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _BusinessHoursTimeButton(
                                label: '开始时间',
                                value: startTimes[key],
                                onPick: () async {
                                  final picked = await showZhTimePicker(
                                    context: sheetCtx,
                                    initialTime: startTimes[key] ??
                                        const TimeOfDay(hour: 9, minute: 0),
                                  );
                                  if (picked != null) {
                                    setSheet(() => startTimes[key] = picked);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _BusinessHoursTimeButton(
                                label: '结束时间',
                                value: endTimes[key],
                                onPick: () async {
                                  final picked = await showZhTimePicker(
                                    context: sheetCtx,
                                    initialTime: endTimes[key] ??
                                        const TimeOfDay(hour: 21, minute: 0),
                                  );
                                  if (picked != null) {
                                    setSheet(() => endTimes[key] = picked);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (m == MealType.overtime &&
                          isOn &&
                          _isCrossDayHours(startTimes[key], endTimes[key])) ...[
                        const SizedBox(height: 4),
                        Text(
                          '该时间段将跨天营业，截止到次日 ${_formatTimeOfDay(endTimes[key]!)}。',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primary.withValues(alpha: 0.85),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
              Text(
                '各餐段营业结束时间将作为员工订餐截止时间。',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              PrimaryActionButton(
                label: '保 存',
                onPressed: () async {
                  for (final m in meals) {
                    if (!enabled[m.name]!) continue;
                    final start = startTimes[m.name];
                    final end = endTimes[m.name];
                    if (start == null || end == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('请设置${m.label}营业时间')),
                      );
                      return;
                    }
                    final startMin = start.hour * 60 + start.minute;
                    final endMin = end.hour * 60 + end.minute;
                    if (startMin == endMin) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('开始与结束时间不能相同')),
                      );
                      return;
                    }
                    if (endMin < startMin && m != MealType.overtime) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('结束时间必须晚于开始时间'),
                        ),
                      );
                      return;
                    }
                  }
                  final supported = enabled.entries
                      .where((e) => e.value)
                      .map((e) => e.key)
                      .toList();
                  final opening = <String, MealHoursSetting>{};
                  for (final m in meals) {
                    final key = m.name;
                    final start = startTimes[key];
                    final end = endTimes[key];
                    opening[key] = MealHoursSetting(
                      enabled: enabled[key] ?? false,
                      start: start != null ? _formatTimeOfDay(start) : '',
                      end: end != null ? _formatTimeOfDay(end) : '',
                    );
                  }
                  try {
                    final ok =
                        await context.read<MerchantState>().saveBusinessHours(
                              supportedMealTypes: supported,
                              mealOpeningHours: opening,
                            );
                    if (!context.mounted) return;
                    if (ok) {
                      Navigator.pop(sheetCtx);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('已保存')));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('保存失败，请稍后重试')),
                      );
                    }
                  } catch (e) {
                    if (!context.mounted) return;
                    final msg = e.toString().contains('结束时间')
                        ? '结束时间必须晚于开始时间'
                        : '保存失败，请稍后重试';
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void showMerchantContactSheet(BuildContext context, Merchant merchant) {
  const platformPhone = '400-000-0000';
  final merchantPhone = merchant.contactPhone.isNotEmpty
      ? merchant.contactPhone
      : '未设置';

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('联系客服'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _phoneRow('平台客服', platformPhone),
          const SizedBox(height: 12),
          _phoneRow('商家联系人', merchantPhone),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

void showMerchantSettingsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            const SizedBox(height: 12),
            const Text(
              '设置',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const AccountLoginStatusTile(),
                    const MerchantNotificationSettingTiles(),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('修改密码'),
                      onTap: () {
                        Navigator.pop(ctx);
                        showChangePasswordSheet(context).then((_) {
                          if (!context.mounted) return;
                          if (context.read<AppState>().currentUser == null) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (_) => const LoginPage()),
                              (_) => false,
                            );
                          }
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('商家服务协议'),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalDocumentPage(
                                doc: legalMerchantService),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('隐私政策'),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                LegalDocumentPage(doc: legalPrivacy),
                          ),
                        );
                      },
                    ),
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('当前版本：1.0.0'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.headset_mic_outlined),
                      title: const Text('联系平台客服'),
                      subtitle: const Text('如有问题请联系平台管理员'),
                      onTap: () {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('请通过平台管理员电话联系客服')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('退出登录', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                await context.read<AppState>().logout();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (_) => false,
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _sheetHandle() => Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

Widget _field(
  String label,
  TextEditingController ctrl, {
  int maxLines = 1,
  TextInputType? keyboard,
  String? hint,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFFAFAF8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}

Widget _modeChip(
  String label,
  _DeliveryOption option,
  _DeliveryOption selected,
  ValueChanged<_DeliveryOption> onSelect,
) {
  final active = selected == option;
  return FilterChip(
    label: Text(label),
    selected: active,
    selectedColor: AppColors.primary.withValues(alpha: 0.15),
    checkmarkColor: AppColors.primary,
    onSelected: (_) => onSelect(option),
  );
}

Widget _phoneRow(String label, String phone) {
  return Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(phone,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      if (phone != '未设置')
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: phone));
          },
          child: const Text('复制'),
        ),
    ],
  );
}

String _defaultStart(MealType m) {
  switch (m) {
    case MealType.breakfast:
      return '07:00';
    case MealType.lunch:
      return '11:00';
    case MealType.dinner:
      return '17:00';
    case MealType.overtime:
      return '17:30';
  }
}

String _defaultEnd(MealType m) {
  switch (m) {
    case MealType.breakfast:
      return '09:00';
    case MealType.lunch:
      return '13:00';
    case MealType.dinner:
      return '19:00';
    case MealType.overtime:
      return '20:00';
  }
}

TimeOfDay? _parseTimeOfDay(String raw) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (m == null) return null;
  final h = int.tryParse(m.group(1)!);
  final min = int.tryParse(m.group(2)!);
  if (h == null || min == null) return null;
  return TimeOfDay(hour: h, minute: min);
}

String _formatTimeOfDay(TimeOfDay t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

bool _isCrossDayHours(TimeOfDay? start, TimeOfDay? end) {
  if (start == null || end == null) return false;
  final startMin = start.hour * 60 + start.minute;
  final endMin = end.hour * 60 + end.minute;
  return endMin <= startMin;
}

class _BusinessHoursTimeButton extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final VoidCallback onPick;

  const _BusinessHoursTimeButton({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final text = value != null ? _formatTimeOfDay(value!) : '请选择';
    return OutlinedButton(
      onPressed: onPick,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        side: BorderSide(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
