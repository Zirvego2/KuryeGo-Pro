import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// iOS [LocationWakeManager] ile MethodChannel köprüsü. Android no-op.
class NativeLocationBridge {
  NativeLocationBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.zirvego/native_location');

  static Future<void> setIosTrackingState({
    required bool enabled,
    required int courierId,
    String? apiToken,
  }) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('setTrackingState', {
        'enabled': enabled,
        'courierId': courierId,
        if (apiToken != null) 'apiToken': apiToken,
      });
    } catch (_) {}
  }

  static Future<Map<String, double>?> getSharedLastSent() async {
    if (kIsWeb || !Platform.isIOS) return null;
    try {
      final r = await _channel.invokeMethod<dynamic>('getSharedLastSent');
      if (r is! Map) return null;
      final lat = (r['lat'] as num?)?.toDouble();
      final lon = (r['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      return {'lat': lat, 'lon': lon};
    } catch (_) {
      return null;
    }
  }

  static Future<String?> drainNativePendingQueueRaw() async {
    if (kIsWeb || !Platform.isIOS) return null;
    try {
      final s = await _channel.invokeMethod<dynamic>('drainNativePendingQueue');
      if (s is String) return s;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> syncLastSentToNative({
    required double latitude,
    required double longitude,
    required int timestampMs,
  }) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('syncLastSentFromFlutter', {
        'lat': latitude,
        'lon': longitude,
        'timestampMs': timestampMs,
      });
    } catch (_) {}
  }
}
