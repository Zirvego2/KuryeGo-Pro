import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// ZirveGo web backend üzerinden HERE + cache (anahtar uygulamada değil).
/// POST https://zirvego.app/api/geocode
class ZirvegoMapsApi {
  ZirvegoMapsApi._();

  static const String baseUrl = 'https://zirvego.app';

  /// Adres → koordinat (sunucuda HERE → LocationIQ fallback).
  static Future<LatLng?> geocode(String query) async {
    final q = query.trim();
    if (q.length < 3) return null;
    try {
      final uri = Uri.parse('$baseUrl/api/geocode');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': q}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] != true) return null;
      final lat = data['lat'];
      final lng = data['lng'];
      if (lat == null || lng == null) return null;
      return LatLng(
        (lat as num).toDouble(),
        (lng as num).toDouble(),
      );
    } catch (e) {
      print('⚠️ [ZirvegoMapsApi] geocode hatası: $e');
      return null;
    }
  }
}
