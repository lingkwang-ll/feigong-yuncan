import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'notification_settings.dart';

/// 商家 / 员工端提示音（新消息 / 新订单）。播放失败不影响业务。
class NotificationSound {
  NotificationSound._();

  static final AudioPlayer _messagePlayer = AudioPlayer();
  static final AudioPlayer _orderPlayer = AudioPlayer();
  static bool _warmedUp = false;
  static bool _unlocked = false;

  static Future<void> warmUp() async {
    if (_warmedUp) return;
    _warmedUp = true;
    try {
      await _messagePlayer.setReleaseMode(ReleaseMode.stop);
      await _orderPlayer.setReleaseMode(ReleaseMode.stop);
      await _messagePlayer.setVolume(0.85);
      await _orderPlayer.setVolume(0.9);
      await _messagePlayer.setSource(AssetSource('audio/message.wav'));
      await _orderPlayer.setSource(AssetSource('audio/new_order.wav'));
      debugPrint('[notify-sound] warmUp ok');
    } catch (e) {
      debugPrint('[notify-sound] warmUp failed: $e');
    }
  }

  /// 首次用户交互后调用，解锁浏览器自动播放限制。
  static Future<void> unlockAfterUserGesture() async {
    if (_unlocked) return;
    await warmUp();
    try {
      await _messagePlayer.setVolume(0);
      await _messagePlayer.resume();
      await _messagePlayer.stop();
      await _messagePlayer.setVolume(0.85);
      _unlocked = true;
      debugPrint('[notify-sound] unlocked');
    } catch (e) {
      debugPrint('[notify-sound] unlock failed: $e');
    }
  }

  static Future<void> playMerchantMessage() async {
    await NotificationSettings.load();
    if (!NotificationSettings.merchantMessageSoundEnabled) return;
    await _play(_messagePlayer, 'message');
  }

  static Future<void> playMerchantNewOrder() async {
    await NotificationSettings.load();
    if (!NotificationSettings.merchantNewOrderSoundEnabled) return;
    await _play(_orderPlayer, 'new_order');
  }

  static Future<void> playEmployeeMessage() async {
    await NotificationSettings.load();
    if (!NotificationSettings.employeeMessageSoundEnabled) return;
    await _play(_messagePlayer, 'message');
  }

  static Future<void> _play(AudioPlayer player, String label) async {
    await warmUp();
    try {
      await player.stop();
      await player.play(AssetSource('audio/$label.wav'));
    } catch (e) {
      debugPrint('[notify-sound] play $label failed: $e');
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }
}
