import 'package:flutter/material.dart';

import '../../config/map_config.dart';
import 'amap_impl_stub.dart'
    if (dart.library.html) 'amap_view_web.dart' as amap_impl;
import 'amap_types.dart';

export 'amap_types.dart';

/// 高德地图 Web 视图
class AmapView extends StatelessWidget {
  final double? centerLat;
  final double? centerLng;
  final List<MapMarkerData> markers;
  final bool interactive;
  final MapPositionCallback? onPositionChanged;
  final double height;

  const AmapView({
    super.key,
    this.centerLat,
    this.centerLng,
    this.markers = const [],
    this.interactive = false,
    this.onPositionChanged,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    return amap_impl.buildAmapView(
      centerLat: centerLat,
      centerLng: centerLng,
      markers: markers,
      interactive: interactive,
      onPositionChanged: onPositionChanged,
      height: height,
    );
  }
}

Future<(double lat, double lng, String address)?> searchMapAddress(
  String keyword,
) {
  return amap_impl.searchAddress(keyword);
}

Widget mapPlaceholder({double height = 280}) {
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
