import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Konum güncellemelerini backend'e iletir: önce POST (JSON), gerekirse mevcut GET sözleşmesine düşer.
/// iOS [LocationWakeManager] aynı POST/GET gövde ve URL ile gönderir.
class CourierLocationApi {
  CourierLocationApi._();

  static const String servisUrl = 'https://zirvego.app/api/servis';

  /// Opsiyonel: `SharedPreferences` anahtarı `location_api_token` — doluysa Authorization eklenir.
  static Future<bool> submitWithRetry({
    required double latitude,
    required double longitude,
    required int courierId,
    required int timestampMs,
    double? speedKmh,
    int maxRetries = 3,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('location_api_token');

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final ok = await _tryPost(
          latitude: latitude,
          longitude: longitude,
          courierId: courierId,
          timestampMs: timestampMs,
          speedKmh: speedKmh,
          token: token,
        );
        if (ok) return true;

        final legacyOk = await _legacyGet(
          latitude: latitude,
          longitude: longitude,
          courierId: courierId,
          timestampMs: timestampMs,
          speedKmh: speedKmh,
        );
        if (legacyOk) return true;

        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 1000 * (1 << (attempt - 1))));
        }
      } catch (_) {
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 1000 * (1 << (attempt - 1))));
        }
      }
    }
    return false;
  }

  static Future<bool> _tryPost({
    required double latitude,
    required double longitude,
    required int courierId,
    required int timestampMs,
    double? speedKmh,
    String? token,
  }) async {
    final body = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestampMs,
      'courierId': courierId,
      's_id': courierId,
      if (speedKmh != null) 'speedKmh': speedKmh,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http
        .post(
          Uri.parse(servisUrl),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200 || response.statusCode == 201) {
      return true;
    }

    // Sunucu POST desteklemiyorsa veya gövde reddedildiyse GET ile yeniden dene
    if (response.statusCode == 404 ||
        response.statusCode == 405 ||
        response.statusCode == 415 ||
        response.statusCode == 400 ||
        response.statusCode == 501) {
      return false;
    }

    // 5xx — üst katmanda retry
    if (response.statusCode >= 500) {
      return false;
    }

    // Diğer 4xx: GET fallback
    return false;
  }

  static Future<bool> _legacyGet({
    required double latitude,
    required double longitude,
    required int courierId,
    required int timestampMs,
    double? speedKmh,
  }) async {
    var url =
        '$servisUrl?x=$latitude&y=$longitude&s_id=$courierId&t=$timestampMs';
    if (speedKmh != null) {
      url += '&km=${speedKmh.toStringAsFixed(2)}';
    }

    final response = await http.get(Uri.parse(url)).timeout(
          const Duration(seconds: 15),
          onTimeout: () => http.Response('', 408),
        );

    return response.statusCode == 200;
  }
}
