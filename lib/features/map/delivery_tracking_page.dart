import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/delivery_location_api.dart';
import '../../config/map_config.dart';
import '../../models/delivery_location_model.dart';
import '../../models/dish_model.dart';
import '../../models/order_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/order_batch_key.dart';
import '../../widgets/map_location_card.dart';
import 'amap_view.dart';

/// 员工端查看配送位置
class DeliveryTrackingPage extends StatefulWidget {
  final Order order;

  const DeliveryTrackingPage({super.key, required this.order});

  static Future<void> open(BuildContext context, Order order) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeliveryTrackingPage(order: order),
      ),
    );
  }

  @override
  State<DeliveryTrackingPage> createState() => _DeliveryTrackingPageState();
}

class _DeliveryTrackingPageState extends State<DeliveryTrackingPage> {
  DeliveryLocation? _merchantLoc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = DeliveryLocationApi(context.read<ApiClient>());
      final date = formatOrderDate(widget.order.createdAt);
      final mealType = widget.order.items.isNotEmpty
          ? widget.order.items.first.dish.mealType
          : MealType.lunch;
      final loc = await api.getCurrent(
        date: date,
        mealType: mealType,
        merchantId: widget.order.merchantId,
      );
      if (mounted) setState(() => _merchantLoc = loc);
    } catch (_) {
      // 降级展示
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _statusText {
    switch (widget.order.status) {
      case OrderStatus.accepted:
        return '商家已接单，正在备餐';
      case OrderStatus.delivering:
        return '商家已出餐，正在配送';
      case OrderStatus.completed:
        return '订单已完成';
      default:
        return widget.order.status.label;
    }
  }

  double? get _pickupLat => widget.order.collectorLatitude;
  double? get _pickupLng => widget.order.collectorLongitude;

  String get _pickupName => widget.order.collectorPoiName;

  String get _pickupAddress {
    if (widget.order.collectorAddressText.isNotEmpty) {
      return widget.order.collectorAddressText;
    }
    if (widget.order.isMealCollector &&
        widget.order.collectorAddress.isNotEmpty) {
      return widget.order.collectorAddress;
    }
    return widget.order.address;
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final hasMerchantLoc = _merchantLoc?.hasCoordinates == true;
    final markers = <MapMarkerData>[];
    if (_pickupLat != null &&
        _pickupLng != null &&
        (_pickupLat != 0 || _pickupLng != 0)) {
      markers.add(MapMarkerData(
        latitude: _pickupLat!,
        longitude: _pickupLng!,
        label: '取餐点',
        color: AppColors.accent,
      ));
    }
    if (hasMerchantLoc) {
      markers.add(MapMarkerData(
        latitude: _merchantLoc!.latitude!,
        longitude: _merchantLoc!.longitude!,
        label: '商家位置',
      ));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '配送位置',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _statusText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!MapConfig.isConfigured) ...[
                  MapLocationCard.fromOrderCollector(
                    title: '统一取餐点 / 收货点',
                    poiName: _pickupName,
                    addressText: _pickupAddress,
                    latitude: _pickupLat,
                    longitude: _pickupLng,
                  ),
                  const SizedBox(height: 10),
                  MapLocationCard.fromDeliveryLocation(
                    '商家当前位置',
                    _merchantLoc,
                    emptyHint: '商家暂未开启实时位置，请稍后查看',
                  ),
                ] else ...[
                  SizedBox(
                    height: 320,
                    child: AmapView(
                      centerLat: hasMerchantLoc
                          ? _merchantLoc!.latitude
                          : _pickupLat,
                      centerLng: hasMerchantLoc
                          ? _merchantLoc!.longitude
                          : _pickupLng,
                      markers: markers,
                      height: 320,
                    ),
                  ),
                  if (!hasMerchantLoc) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '商家暂未开启实时位置，请稍后查看',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  MapLocationCard.fromOrderCollector(
                    title: '取餐点',
                    poiName: _pickupName,
                    addressText: _pickupAddress,
                    latitude: _pickupLat,
                    longitude: _pickupLng,
                  ),
                  const SizedBox(height: 10),
                  MapLocationCard.fromDeliveryLocation(
                    '商家位置',
                    _merchantLoc,
                    emptyHint: '暂无实时位置',
                  ),
                ],
                if (_merchantLoc?.updatedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '最后更新：${df.format(_merchantLoc!.updatedAt!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
