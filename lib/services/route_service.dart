import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/order_model.dart';

/// Rota noktası (sipariş + sıra numarası)
class RoutePoint {
  final OrderModel order;
  final int sequenceNumber; // 1, 2, 3, 4, 5
  final LatLng deliveryLocation; // Teslimat adresi

  RoutePoint({
    required this.order,
    required this.sequenceNumber,
    required this.deliveryLocation,
  });
}

/// Rota sonucu
class RouteResult {
  final List<RoutePoint> routePoints; // Sıralı rota noktaları
  final double totalDistanceKm; // Toplam mesafe (km)
  final int estimatedMinutes; // Tahmini süre (dakika)
  final List<LatLng>? routePolyline; // Directions API'den gelen rota çizgisi noktaları

  RouteResult({
    required this.routePoints,
    required this.totalDistanceKm,
    required this.estimatedMinutes,
    this.routePolyline,
  });
}

/// Directions API yanıt sonucu
class DirectionsResult {
  final List<LatLng> polyline; // Rota çizgisi noktaları
  final double totalDistanceMeters; // Toplam mesafe (metre)
  final int totalDurationSeconds; // Toplam süre (saniye)

  DirectionsResult({
    required this.polyline,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
  });
}

/// Rota hesaplama servisi
/// v1 seviyesi: Nearest Neighbor algoritması (basit ve stabil)
class RouteService {
  // Google Maps Directions API Key (AndroidManifest.xml'den alınmalı)
  // Not: Production'da environment variable veya config'den alınmalı
  // ⚠️ Directions API aktif değilse düz çizgi kullanılacak
  static const String _directionsApiKey = 'AIzaSyBpgppKBVULdvG8yHq8F57TljP9PpXTvCM';
  static const String _directionsApiUrl = 'https://maps.googleapis.com/maps/api/directions/json';

  /// İki nokta arasına ara noktalar ekle (daha düzgün görünüm için)
  static List<LatLng> interpolatePoints(LatLng start, LatLng end, int segments) {
    final points = <LatLng>[];
    for (int i = 0; i <= segments; i++) {
      final ratio = i / segments;
      final lat = start.latitude + (end.latitude - start.latitude) * ratio;
      final lng = start.longitude + (end.longitude - start.longitude) * ratio;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  /// Google Maps Encoded Polyline'i decode et
  /// https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  static List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return poly;
  }

  /// Google Maps Directions API (Legacy) - Gerçek yollar üzerinden rota bilgisi al
  /// Kullanılan API: Legacy Directions API v1
  /// Endpoint: https://maps.googleapis.com/maps/api/directions/json
  /// 
  /// Not: Google artık yeni Routes API'yi öneriyor ancak v1 seviyesinde
  /// basit tutmak için legacy Directions API kullanıyoruz
  /// 
  /// Döndürür: DirectionsResult (polyline + mesafe + süre) veya null
  static Future<DirectionsResult?> getDirectionsWithWaypoints({
    required LatLng origin,
    required List<LatLng> waypoints,
    required LatLng destination,
  }) async {
    try {
      // Waypoints'i string formatına çevir (max 25 waypoint - Google limit)
      final limitedWaypoints = waypoints.take(25).toList();
      final waypointsStr = limitedWaypoints
          .map((wp) => '${wp.latitude},${wp.longitude}')
          .join('|');

      // Legacy Directions API URL oluştur
      String urlStr = '$_directionsApiUrl?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&mode=driving&key=$_directionsApiKey';
      
      // Waypoints varsa ekle (optimize parametresi ile)
      if (limitedWaypoints.isNotEmpty) {
        urlStr += '&waypoints=optimize:true|$waypointsStr';
      }

      final url = Uri.parse(urlStr);
      
      print('🗺️ [Directions API] Çağrı: ${limitedWaypoints.length + 2} nokta (${limitedWaypoints.length} waypoint)');

      final response = await http.get(url).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'] as String?;
        
        if (status == 'OK' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final overviewPolyline = route['overview_polyline']?['points'] as String?;
          
          if (overviewPolyline == null || overviewPolyline.isEmpty) {
            print('⚠️ [Directions API] Polyline boş');
            return null;
          }

          // Overview polyline'i decode et (tüm rotayı içerir - gerçek yollar üzerinden)
          final decodedPoints = _decodePolyline(overviewPolyline);
          
          // Mesafe ve süre bilgilerini topla (legs içinden)
          double totalDistanceMeters = 0.0;
          int totalDurationSeconds = 0;
          
          final legs = route['legs'] as List?;
          if (legs != null && legs.isNotEmpty) {
            for (var leg in legs) {
              // Mesafe (metre cinsinden)
              final distance = leg['distance']?['value'];
              if (distance != null && distance is num) {
                totalDistanceMeters += distance.toDouble();
              }
              
              // Süre (saniye cinsinden)
              final duration = leg['duration']?['value'];
              if (duration != null && duration is num) {
                totalDurationSeconds += duration.toInt();
              }
            }
          }
          
          print('✅ [Directions API] Başarılı:');
          print('   📍 Polyline: ${decodedPoints.length} nokta (gerçek yollar)');
          print('   🛣️  Mesafe: ${(totalDistanceMeters / 1000).toStringAsFixed(2)} km');
          print('   ⏱️  Süre: ${(totalDurationSeconds / 60).toStringAsFixed(1)} dakika');
          
          return DirectionsResult(
            polyline: decodedPoints,
            totalDistanceMeters: totalDistanceMeters,
            totalDurationSeconds: totalDurationSeconds,
          );
        } else if (status == 'REQUEST_DENIED') {
          final errorMsg = data['error_message'] as String? ?? 'API key hatası';
          print('❌ [Directions API] REQUEST_DENIED');
          print('   💡 $errorMsg');
          print('   → Google Cloud Console: Directions API aktif mi? API key izinleri kontrol edin');
        } else if (status == 'ZERO_RESULTS') {
          print('⚠️ [Directions API] Rota bulunamadı (ZERO_RESULTS)');
        } else {
          print('⚠️ [Directions API] Status: $status');
        }
      } else {
        print('❌ [Directions API] HTTP hatası: ${response.statusCode}');
      }
      
      return null;
    } catch (e) {
      print('❌ [Directions API] Hata: $e');
      return null;
    }
  }

  /// Rota hesapla (Nearest Neighbor algoritması)
  /// 
  /// Algoritma:
  /// 1. Başlangıç noktası: Kuryenin mevcut konumu
  /// 2. İlk durak: En yakın teslimat adresi
  /// 3. Sonraki duraklar: Bir önceki durağa en yakın olan
  /// 4. Maksimum 5 sipariş
  static Future<RouteResult> calculateRoute({
    required LatLng startLocation, // Kuryenin mevcut konumu
    required List<OrderModel> orders, // Teslim alındı (s_stat=1) siparişler
  }) async {
    // Sadece teslim alındı (s_stat=1) ve teslimat adresi olan siparişleri filtrele
    final validOrders = orders.where((order) {
      return order.sStat == 1 && order.ssLoc != null;
    }).toList();

    if (validOrders.isEmpty) {
      return RouteResult(
        routePoints: [],
        totalDistanceKm: 0.0,
        estimatedMinutes: 0,
        routePolyline: null,
      );
    }

    // Maksimum 5 sipariş
    final ordersToRoute = validOrders.take(5).toList();

    // Nearest Neighbor algoritması
    final routePoints = <RoutePoint>[];
    LatLng currentLocation = startLocation;
    final remainingOrders = List<OrderModel>.from(ordersToRoute);
    int sequenceNumber = 1;

    while (remainingOrders.isNotEmpty && routePoints.length < 5) {
      // En yakın siparişi bul
      OrderModel? nearestOrder;
      double minDistance = double.infinity;

      for (final order in remainingOrders) {
        if (order.ssLoc == null) continue;

        final deliveryLat = order.ssLoc!['latitude'] as double;
        final deliveryLng = order.ssLoc!['longitude'] as double;
        final deliveryLocation = LatLng(deliveryLat, deliveryLng);

        final distance = Geolocator.distanceBetween(
          currentLocation.latitude,
          currentLocation.longitude,
          deliveryLat,
          deliveryLng,
        );

        if (distance < minDistance) {
          minDistance = distance;
          nearestOrder = order;
        }
      }

      if (nearestOrder == null) break;

      // Rota noktası ekle
      final deliveryLat = nearestOrder.ssLoc!['latitude'] as double;
      final deliveryLng = nearestOrder.ssLoc!['longitude'] as double;
      final deliveryLocation = LatLng(deliveryLat, deliveryLng);

      routePoints.add(RoutePoint(
        order: nearestOrder,
        sequenceNumber: sequenceNumber++,
        deliveryLocation: deliveryLocation,
      ));

      // Güncel konumu güncelle ve siparişi listeden çıkar
      currentLocation = deliveryLocation;
      remainingOrders.remove(nearestOrder);
    }

    // Directions API ile gerçek yollar üzerinden rota bilgisi al (mesafe + süre + polyline)
    double totalDistanceKm = 0.0;
    int estimatedMinutes = 0;
    List<LatLng>? routePolyline;
    
    try {
      if (routePoints.isEmpty) {
        routePolyline = null;
      } else if (routePoints.length == 1) {
        // Tek durak varsa direkt origin-destination
        final directionsResult = await getDirectionsWithWaypoints(
          origin: startLocation,
          waypoints: [],
          destination: routePoints.first.deliveryLocation,
        );
        
        if (directionsResult != null) {
          // ✅ Directions API'den gelen gerçek mesafe ve süre
          totalDistanceKm = directionsResult.totalDistanceMeters / 1000.0;
          estimatedMinutes = (directionsResult.totalDurationSeconds / 60.0).round();
          routePolyline = directionsResult.polyline;
          
          print('✅ [ROTA] Directions API bilgileri kullanıldı: ${totalDistanceKm.toStringAsFixed(2)} km, ~$estimatedMinutes dk');
        } else {
          // Fallback: Düz çizgi mesafe hesaplama
          final fallbackDistance = Geolocator.distanceBetween(
            startLocation.latitude,
            startLocation.longitude,
            routePoints.first.deliveryLocation.latitude,
            routePoints.first.deliveryLocation.longitude,
          );
          totalDistanceKm = fallbackDistance / 1000.0;
          estimatedMinutes = (totalDistanceKm / 30.0 * 60.0).round();
          routePolyline = null;
          
          print('⚠️ [ROTA] Directions API başarısız → Fallback (düz çizgi): ${totalDistanceKm.toStringAsFixed(2)} km, ~$estimatedMinutes dk');
        }
      } else {
        // Birden fazla durak varsa waypoints kullan
        final waypoints = routePoints
            .take(routePoints.length - 1)
            .map((rp) => rp.deliveryLocation)
            .toList();
        final destination = routePoints.last.deliveryLocation;
        
        final directionsResult = await getDirectionsWithWaypoints(
          origin: startLocation,
          waypoints: waypoints,
          destination: destination,
        );
        
        if (directionsResult != null) {
          // ✅ Directions API'den gelen gerçek mesafe ve süre
          totalDistanceKm = directionsResult.totalDistanceMeters / 1000.0;
          estimatedMinutes = (directionsResult.totalDurationSeconds / 60.0).round();
          routePolyline = directionsResult.polyline;
          
          print('✅ [ROTA] Directions API bilgileri kullanıldı: ${totalDistanceKm.toStringAsFixed(2)} km, ~$estimatedMinutes dk');
        } else {
          // Fallback: Düz çizgi mesafe hesaplama (her nokta arası topla)
          double totalDistanceMeters = 0.0;
          LatLng previousLocation = startLocation;

          for (final point in routePoints) {
            final distance = Geolocator.distanceBetween(
              previousLocation.latitude,
              previousLocation.longitude,
              point.deliveryLocation.latitude,
              point.deliveryLocation.longitude,
            );
            totalDistanceMeters += distance;
            previousLocation = point.deliveryLocation;
          }

          totalDistanceKm = totalDistanceMeters / 1000.0;
          estimatedMinutes = (totalDistanceKm / 30.0 * 60.0).round();
          routePolyline = null;
          
          print('⚠️ [ROTA] Directions API başarısız → Fallback (düz çizgi): ${totalDistanceKm.toStringAsFixed(2)} km, ~$estimatedMinutes dk');
        }
      }
    } catch (e) {
      print('❌ [ROTA] Directions API hatası → Fallback kullanılacak: $e');
      
      // Fallback: Düz çizgi mesafe hesaplama
      double totalDistanceMeters = 0.0;
      LatLng previousLocation = startLocation;

      for (final point in routePoints) {
        final distance = Geolocator.distanceBetween(
          previousLocation.latitude,
          previousLocation.longitude,
          point.deliveryLocation.latitude,
          point.deliveryLocation.longitude,
        );
        totalDistanceMeters += distance;
        previousLocation = point.deliveryLocation;
      }

      totalDistanceKm = totalDistanceMeters / 1000.0;
      estimatedMinutes = (totalDistanceKm / 30.0 * 60.0).round();
      routePolyline = null;
    }

    return RouteResult(
      routePoints: routePoints,
      totalDistanceKm: totalDistanceKm,
      estimatedMinutes: estimatedMinutes,
      routePolyline: routePolyline,
    );
  }

  /// Yeni sipariş rotaya eklendiğinde ekstra mesafe ve süre hesapla
  static Map<String, dynamic> calculateAdditionalRouteInfo({
    required RouteResult currentRoute,
    required OrderModel newOrder,
    required LatLng currentCourierLocation,
  }) {
    if (newOrder.ssLoc == null) {
      return {
        'extraDistanceKm': 0.0,
        'extraMinutes': 0,
        'estimatedSequence': 0,
      };
    }

    final newDeliveryLat = newOrder.ssLoc!['latitude'] as double;
    final newDeliveryLng = newOrder.ssLoc!['longitude'] as double;
    final newDeliveryLocation = LatLng(newDeliveryLat, newDeliveryLng);

    // Mevcut rotaya en uygun pozisyonu bul (en az mesafe artışı)
    double minExtraDistance = double.infinity;
    int bestInsertIndex = currentRoute.routePoints.length;
    LatLng? bestPreviousLocation;

    // Son noktadan yeni noktaya mesafe
    if (currentRoute.routePoints.isNotEmpty) {
      final lastPoint = currentRoute.routePoints.last;
      final distanceFromLast = Geolocator.distanceBetween(
        lastPoint.deliveryLocation.latitude,
        lastPoint.deliveryLocation.longitude,
        newDeliveryLat,
        newDeliveryLng,
      );

      if (distanceFromLast < minExtraDistance) {
        minExtraDistance = distanceFromLast;
        bestInsertIndex = currentRoute.routePoints.length;
        bestPreviousLocation = lastPoint.deliveryLocation;
      }
    }

    // Her nokta arasına ekleme senaryosunu dene
    for (int i = 0; i < currentRoute.routePoints.length; i++) {
      LatLng previousLocation;
      if (i == 0) {
        previousLocation = currentCourierLocation;
      } else {
        previousLocation = currentRoute.routePoints[i - 1].deliveryLocation;
      }

      final nextPoint = currentRoute.routePoints[i];
      
      // Önceki noktadan yeni noktaya, sonra yeni noktadan sonraki noktaya
      final distanceToNew = Geolocator.distanceBetween(
        previousLocation.latitude,
        previousLocation.longitude,
        newDeliveryLat,
        newDeliveryLng,
      );

      final distanceFromNewToNext = Geolocator.distanceBetween(
        newDeliveryLat,
        newDeliveryLng,
        nextPoint.deliveryLocation.latitude,
        nextPoint.deliveryLocation.longitude,
      );

      // Mevcut mesafe (önceki -> sonraki)
      final currentDistance = Geolocator.distanceBetween(
        previousLocation.latitude,
        previousLocation.longitude,
        nextPoint.deliveryLocation.latitude,
        nextPoint.deliveryLocation.longitude,
      );

      // Ekstra mesafe = (önceki -> yeni -> sonraki) - (önceki -> sonraki)
      final extraDistance = distanceToNew + distanceFromNewToNext - currentDistance;

      if (extraDistance < minExtraDistance) {
        minExtraDistance = extraDistance;
        bestInsertIndex = i;
        bestPreviousLocation = previousLocation;
      }
    }

    final extraDistanceKm = minExtraDistance / 1000.0;
    final extraMinutes = (extraDistanceKm / 30.0 * 60.0).round();
    final estimatedSequence = bestInsertIndex + 1;

    return {
      'extraDistanceKm': extraDistanceKm,
      'extraMinutes': extraMinutes,
      'estimatedSequence': estimatedSequence,
    };
  }
}
