import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/delivery_location_model.dart';
import '../theme/app_theme.dart';

/// 位置信息卡片（优先展示地点名称 + 详细地址）
class MapLocationCard extends StatelessWidget {
  final String title;
  final String? locationName;
  final String? addressText;
  final double? latitude;
  final double? longitude;
  final DateTime? updatedAt;
  final String? emptyHint;
  final bool showCoordinates;

  const MapLocationCard({
    super.key,
    required this.title,
    this.locationName,
    this.addressText,
    this.latitude,
    this.longitude,
    this.updatedAt,
    this.emptyHint,
    this.showCoordinates = false,
  });

  factory MapLocationCard.fromDeliveryLocation(
    String title,
    DeliveryLocation? loc, {
    String? emptyHint,
    bool showCoordinates = false,
  }) {
    return MapLocationCard(
      title: title,
      locationName: loc?.addressText,
      addressText: loc?.addressText,
      latitude: loc?.latitude,
      longitude: loc?.longitude,
      updatedAt: loc?.updatedAt,
      emptyHint: emptyHint,
      showCoordinates: showCoordinates,
    );
  }

  factory MapLocationCard.fromOrderCollector({
    required String title,
    String? poiName,
    String? addressText,
    double? latitude,
    double? longitude,
    String? emptyHint,
  }) {
    return MapLocationCard(
      title: title,
      locationName: poiName,
      addressText: addressText,
      latitude: latitude,
      longitude: longitude,
      emptyHint: emptyHint,
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final name = locationName?.trim() ?? '';
    final addr = addressText?.trim() ?? '';
    final hasName = name.isNotEmpty;
    final hasAddr = addr.isNotEmpty && addr != name;
    final hasCoords =
        latitude != null && longitude != null && (latitude != 0 || longitude != 0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (!hasName && !hasAddr && !hasCoords)
            Text(
              emptyHint ?? '暂无位置信息',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            )
          else ...[
            if (hasName)
              Text(
                name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
            if (hasAddr) ...[
              if (hasName) const SizedBox(height: 4),
              Text(
                addr,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            if (!hasName && hasAddr)
              Text(
                addr,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            if (showCoordinates && hasCoords) ...[
              const SizedBox(height: 4),
              Text(
                '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
            if (updatedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                '更新：${df.format(updatedAt!)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
