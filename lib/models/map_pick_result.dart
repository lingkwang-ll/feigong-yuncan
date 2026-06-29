/// 地图选点结果
class MapPickResult {
  final String addressText;
  final String poiName;
  final String name;
  final double latitude;
  final double longitude;

  const MapPickResult({
    required this.addressText,
    this.poiName = '',
    this.name = '',
    required this.latitude,
    required this.longitude,
  });

  bool get hasCoordinates => latitude != 0 || longitude != 0;

  /// 展示用地点名称（name 与 poiName 可复用）
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (poiName.trim().isNotEmpty) return poiName.trim();
    return '';
  }
}
