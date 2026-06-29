import 'package:flutter/material.dart';

class MapMarkerData {
  final double latitude;
  final double longitude;
  final String label;
  final Color color;

  const MapMarkerData({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.color = const Color(0xFF1FA855),
  });
}

typedef MapPositionCallback = void Function(
  double lat,
  double lng,
  String? address,
);
