import 'dart:async';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'geolocation_stub.dart';

Future<GeoPosition?> getCurrentGeoPosition() async {
  final geo = html.window.navigator.geolocation;
  if (geo == null) return null;

  final completer = Completer<GeoPosition?>();
  geo.getCurrentPosition().then((pos) {
    final coords = pos.coords;
    if (coords == null) {
      completer.complete(null);
      return;
    }
    completer.complete(GeoPosition(
      latitude: (coords.latitude ?? 0).toDouble(),
      longitude: (coords.longitude ?? 0).toDouble(),
    ));
  }).catchError((Object e) {
    completer.completeError(e);
  });
  return completer.future;
}

String? geolocationUnsupportedMessage() {
  if (html.window.navigator.geolocation == null) {
    return '当前浏览器不支持定位';
  }
  return null;
}

String geolocationErrorMessage(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('denied') || msg.contains('permission')) {
    return '请允许定位权限';
  }
  return '定位失败，请重试';
}
