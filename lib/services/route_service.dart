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
  /// OSRM ile gerçek yol geometrisi; yoksa haritada düz çizgi interpolasyonu
  final List<LatLng>? routePolyline;

  RouteResult({
    required this.routePoints,
    required this.totalDistanceKm,
    required this.estimatedMinutes,
    this.routePolyline,
  });
}

class _OsrmLeg {
  final List<LatLng> polyline;
  final double distanceKm;
  final int durationMinutes;

  _OsrmLeg({
    required this.polyline,
    required this.distanceKm,
    required this.durationMinutes,
  });
}

/// Web `/api/calculate-distance` ile aynı OSRM projesi (Project-OSRM demo sunucusu)
const String _kOsrmBase = 'https://router.project-osrm.org/route/v1/driving';

/// Rota hesaplama: Nearest Neighbor sıralama + **OSRM** mesafe/polyline.
/// Google Directions / Distance Matrix kullanılmaz.
class RouteService {
  /// İki nokta arası düz çizgiye ara noktalar (OSRM yokken harita fallback)
  static List<LatLng> interpolatePoints(LatLng a, LatLng b, int segmentCount) {
    if (segmentCount < 1) return [a, b];
    final out = <LatLng>[];
    for (int i = 0; i <= segmentCount; i++) {
      final t = i / segmentCount;
      out.add(LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ));
    }
    return out;
  }

  static Future<_OsrmLeg?> _fetchOsrmRoute(List<LatLng> path) async {
    if (path.length < 2) return null;
    final coordStr = path.map((p) => '${p.longitude},${p.latitude}').join(';');
    final uri = Uri.parse(
      '$_kOsrmBase/$coordStr?overview=full&geometries=geojson&steps=false',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return null;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final distanceM = (route['distance'] as num?)?.toDouble() ?? 0;
      final durationS = (route['duration'] as num?)?.toDouble() ?? 0;
      final geometry = route['geometry'];
      final poly = <LatLng>[];
      if (geometry is Map && geometry['coordinates'] is List) {
        for (final c in geometry['coordinates'] as List<dynamic>) {
          if (c is List && c.length >= 2) {
            final lng = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            poly.add(LatLng(lat, lng));
          }
        }
      }
      if (poly.isEmpty) return null;
      return _OsrmLeg(
        polyline: poly,
        distanceKm: distanceM / 1000.0,
        durationMinutes: (durationS / 60.0).round().clamp(1, 24 * 60),
      );
    } catch (e) {
      print('⚠️ [ROTA] OSRM hatası, Haversine kullanılacak: $e');
      return null;
    }
  }

  static Future<RouteResult> calculateRoute({
    required LatLng startLocation,
    required List<OrderModel> orders,
  }) async {
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

    final ordersToRoute = validOrders.take(5).toList();

    final routePoints = <RoutePoint>[];
    LatLng currentLocation = startLocation;
    final remainingOrders = List<OrderModel>.from(ordersToRoute);
    int sequenceNumber = 1;

    while (remainingOrders.isNotEmpty && routePoints.length < 5) {
      OrderModel? nearestOrder;
      double minDistance = double.infinity;

      for (final order in remainingOrders) {
        if (order.ssLoc == null) continue;

        final deliveryLat = order.ssLoc!['latitude'] as double;
        final deliveryLng = order.ssLoc!['longitude'] as double;

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

      final deliveryLat = nearestOrder.ssLoc!['latitude'] as double;
      final deliveryLng = nearestOrder.ssLoc!['longitude'] as double;
      final deliveryLocation = LatLng(deliveryLat, deliveryLng);

      routePoints.add(RoutePoint(
        order: nearestOrder,
        sequenceNumber: sequenceNumber++,
        deliveryLocation: deliveryLocation,
      ));

      currentLocation = deliveryLocation;
      remainingOrders.remove(nearestOrder);
    }

    // OSRM: kurye → durak1 → … (tek istek, web ile uyumlu yönlendirme motoru)
    final path = <LatLng>[
      startLocation,
      ...routePoints.map((p) => p.deliveryLocation),
    ];
    final osrm = await _fetchOsrmRoute(path);
    if (osrm != null) {
      print(
        '✅ [ROTA] OSRM: ${osrm.distanceKm.toStringAsFixed(2)} km, ~${osrm.durationMinutes} dk',
      );
      return RouteResult(
        routePoints: routePoints,
        totalDistanceKm: osrm.distanceKm,
        estimatedMinutes: osrm.durationMinutes,
        routePolyline: osrm.polyline,
      );
    }

    // Fallback: Haversine (kuş uçuşu)
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

    final totalDistanceKm = totalDistanceMeters / 1000.0;
    final estimatedMinutes = (totalDistanceKm / 30.0 * 60.0).round();

    print(
      '✅ [ROTA] Haversine ile hesaplandı: ${totalDistanceKm.toStringAsFixed(2)} km, ~$estimatedMinutes dk',
    );

    return RouteResult(
      routePoints: routePoints,
      totalDistanceKm: totalDistanceKm,
      estimatedMinutes: estimatedMinutes,
      routePolyline: null,
    );
  }

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

    double minExtraDistance = double.infinity;
    int bestInsertIndex = currentRoute.routePoints.length;

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
      }
    }

    for (int i = 0; i < currentRoute.routePoints.length; i++) {
      LatLng previousLocation;
      if (i == 0) {
        previousLocation = currentCourierLocation;
      } else {
        previousLocation = currentRoute.routePoints[i - 1].deliveryLocation;
      }

      final nextPoint = currentRoute.routePoints[i];

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

      final currentDistance = Geolocator.distanceBetween(
        previousLocation.latitude,
        previousLocation.longitude,
        nextPoint.deliveryLocation.latitude,
        nextPoint.deliveryLocation.longitude,
      );

      final extraDistance = distanceToNew + distanceFromNewToNext - currentDistance;

      if (extraDistance < minExtraDistance) {
        minExtraDistance = extraDistance;
        bestInsertIndex = i;
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
