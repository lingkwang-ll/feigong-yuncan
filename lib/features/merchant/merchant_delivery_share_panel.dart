import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/delivery_location_api.dart';
import '../../models/dish_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/geolocation.dart';
import '../../utils/order_batch_key.dart';
import '../../widgets/app_button.dart';

/// 商家端实时配送位置上报
class MerchantDeliverySharePanel extends StatefulWidget {
  final String merchantId;
  final DateTime date;
  final MealType mealType;
  final bool enabled;

  const MerchantDeliverySharePanel({
    super.key,
    required this.merchantId,
    required this.date,
    required this.mealType,
    required this.enabled,
  });

  @override
  State<MerchantDeliverySharePanel> createState() =>
      _MerchantDeliverySharePanelState();
}

class _MerchantDeliverySharePanelState
    extends State<MerchantDeliverySharePanel> {
  Timer? _timer;
  bool _sharing = false;
  DateTime? _lastUpdated;
  String? _error;
  String _lastAddress = '';

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _uploadOnce() async {
    final unsupported = geolocationUnsupportedMessage();
    if (unsupported != null) {
      setState(() => _error = unsupported);
      return;
    }
    try {
      final pos = await getCurrentGeoPosition();
      if (pos == null || !mounted) return;
      final api = DeliveryLocationApi(context.read<ApiClient>());
      final loc = await api.update(
        date: formatOrderDate(widget.date),
        mealType: widget.mealType,
        merchantId: widget.merchantId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        addressText: _lastAddress.isNotEmpty ? _lastAddress : '当前位置',
      );
      if (mounted) {
        setState(() {
          _lastUpdated = loc?.updatedAt ?? DateTime.now();
          _lastAddress = loc?.addressText ?? _lastAddress;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = geolocationErrorMessage(e));
      }
    }
  }

  Future<void> _startSharing() async {
    await _uploadOnce();
    if (!mounted || _error != null) return;
    setState(() => _sharing = true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _uploadOnce());
  }

  void _stopSharing() {
    _timer?.cancel();
    _timer = null;
    setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '实时配送位置',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _sharing ? '状态：已开启（每 15 秒更新）' : '状态：未开启',
            style: TextStyle(
              fontSize: 13,
              color: _sharing ? AppColors.primary : AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_lastUpdated != null) ...[
            const SizedBox(height: 4),
            Text(
              '最新更新：${_lastUpdated!.toString().substring(0, 19)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: AppColors.accent),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (!_sharing)
                Expanded(
                  child: PrimaryActionButton(
                    label: '开启实时配送位置',
                    height: 42,
                    onPressed: _startSharing,
                  ),
                )
              else
                Expanded(
                  child: OutlineAccentButton(
                    label: '停止共享位置',
                    onPressed: _stopSharing,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
