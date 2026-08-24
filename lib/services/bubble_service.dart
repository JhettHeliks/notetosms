import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BubbleService {
  BubbleService._();
  static final BubbleService instance = BubbleService._();

  static const MethodChannel _channelPrimary = MethodChannel('com.notetosms/bubbles');
  static const MethodChannel _channelLegacy = MethodChannel('com.chatnotes/bubbles');

  /// Request Android System to pop out the given note room as a floating chat head / bubble
  Future<bool> showAsBubble({
    required String roomId,
    required String roomName,
    String icon = 'chat_bubble',
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      debugPrint('System bubbles are only supported on Android.');
      return false;
    }

    final arguments = <String, dynamic>{
      'roomId': roomId,
      'roomName': roomName,
      'icon': icon,
    };

    try {
      final bool? result = await _channelPrimary.invokeMethod<bool>('bubbleRoom', arguments);
      return result ?? false;
    } on MissingPluginException {
      try {
        final bool? result = await _channelLegacy.invokeMethod<bool>('bubbleRoom', arguments);
        return result ?? false;
      } catch (e) {
        debugPrint('Failed to invoke legacy bubble channel: $e');
        return false;
      }
    } catch (e) {
      debugPrint('Failed to pop out bubble for room $roomId: $e');
      return false;
    }
  }

  /// Check whether the current Android OS level supports system bubbles (Android 11 / API 30+)
  Future<bool> isBubbleSupported() async {
    if (kIsWeb || !Platform.isAndroid) return false;

    try {
      final bool? supported = await _channelPrimary.invokeMethod<bool>('isBubbleSupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }
}
