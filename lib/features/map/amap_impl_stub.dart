import 'package:flutter/material.dart';

import '../../config/map_config.dart';
import 'amap_types.dart';

Widget buildAmapView({
  double? centerLat,
  double? centerLng,
  List<MapMarkerData> markers = const [],
  bool interactive = false,
  MapPositionCallback? onPositionChanged,
  double height = 280,
}) {
  return Container(
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFF1F3F5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0E0E0)),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: Text(
      MapConfig.notConfiguredHint,
      style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
      textAlign: TextAlign.center,
    ),
  );
}

Future<(double lat, double lng, String address)?> searchAddress(
  String keyword,
) async =>
    null;
