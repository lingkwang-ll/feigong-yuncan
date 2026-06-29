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
  if (!MapConfig.isConfigured) {
    return _placeholder(height);
  }
  final lat = centerLat ?? 31.2304;
  final lng = centerLng ?? 121.4737;
  final markerParts = markers.isEmpty
      ? 'mid,,A:$lng,$lat'
      : markers.map((m) => 'mid,,A:${m.longitude},${m.latitude}').join('|');
  final url =
      'https://restapi.amap.com/v3/staticmap?location=$lng,$lat&zoom=15&size=600*400&markers=$markerParts&key=${MapConfig.amapWebKey}';

  return SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(height),
          ),
          if (interactive)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onPositionChanged?.call(lat, lng, null),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '点击确认当前地图中心位置',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Future<(double lat, double lng, String address)?> searchAddress(
  String keyword,
) async =>
    null;

Widget _placeholder(double height) {
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
