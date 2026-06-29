import 'package:flutter/material.dart';

import '../../models/map_pick_result.dart';

/// 非 Web 平台占位（请使用 Web 或手动选点降级页）
class AmapPickerIframe extends StatelessWidget {
  final MapPickResult? initial;
  final ValueChanged<MapPickResult> onConfirmed;

  const AmapPickerIframe({
    super.key,
    this.initial,
    required this.onConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '完整地图选点仅支持 Flutter Web',
        style: TextStyle(color: Color(0xFF888888)),
      ),
    );
  }
}
