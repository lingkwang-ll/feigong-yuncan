import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

import 'review_image_picker.dart';

Future<PickedReviewImage?> pickReviewImageFromCameraWeb() async {
  final completer = Completer<PickedReviewImage?>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/jpeg,image/png,image/webp'
    ..setAttribute('capture', 'environment');

  void cleanup() => input.remove();

  input.onChange.listen((_) async {
    try {
      final file = input.files?.first;
      if (file == null) {
        completer.complete(null);
        return;
      }
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      final raw = reader.result;
      if (raw is! ByteBuffer) {
        completer.complete(null);
        return;
      }
      final bytes = raw.asUint8List();
      if (bytes.isEmpty || bytes.length > kReviewImageMaxBytes) {
        completer.complete(null);
        return;
      }
      final name = file.name.isNotEmpty ? file.name : 'camera.jpg';
      completer.complete(PickedReviewImage(bytes: bytes, filename: name));
    } catch (_) {
      completer.complete(null);
    } finally {
      cleanup();
    }
  });

  input.click();
  return completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      cleanup();
      return null;
    },
  );
}
