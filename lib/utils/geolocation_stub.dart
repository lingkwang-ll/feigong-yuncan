class GeoPosition {
  final double latitude;
  final double longitude;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
  });
}

Future<GeoPosition?> getCurrentGeoPosition() async => null;

String? geolocationUnsupportedMessage() => '当前浏览器不支持定位';

String geolocationErrorMessage(Object error) => '定位失败，请重试';
