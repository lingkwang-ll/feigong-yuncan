import 'package:flutter/material.dart';

/// 中文 24 小时制时间选择器（商家营业时间等场景）。
Future<TimeOfDay?> showZhTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    helpText: '选择时间',
    cancelText: '取消',
    confirmText: '确定',
    builder: (ctx, child) {
      return MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: Localizations.override(
          context: ctx,
          locale: const Locale('zh', 'CN'),
          child: child ?? const SizedBox.shrink(),
        ),
      );
    },
  );
}
