import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/order_model.dart';

class PoolOrderService {
  static const String _claimUrl = 'https://zirvego.app/api/courier-pool-claim';

  static List<int> _normalizeBusinessIds(dynamic rawIds) {
    if (rawIds is! List) return [];
    return rawIds
        .map((item) => int.tryParse(item.toString()))
        .whereType<int>()
        .toSet()
        .toList();
  }

  static Future<Map<String, dynamic>> getCourierPoolConfig(int courierId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('t_courier')
        .where('s_id', isEqualTo: courierId)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return {
        'enabled': false,
        'allowWhileBusy': false,
        'scope': 'selected',
        'businessIds': <int>[],
      };
    }

    final data = snapshot.docs.first.data();
    return {
      'enabled': data['s_pool_permission_enabled'] == true,
      'allowWhileBusy': data['s_pool_allow_while_busy'] == true,
      'scope': data['s_pool_business_scope'] == 'all' ? 'all' : 'selected',
      'businessIds': _normalizeBusinessIds(data['s_pool_business_ids']),
    };
  }

  static Stream<List<OrderModel>> watchPoolOrders({
    required int bayId,
    required String scope,
    required List<int> allowedBusinessIds,
  }) {
    return FirebaseFirestore.instance
        .collection('t_orders')
        .where('s_bay', isEqualTo: bayId)
        .where('s_courier', isEqualTo: 0)
        .where('s_stat', whereIn: [0, 4])
        .snapshots()
        .map((snapshot) {
      final orders = snapshot.docs
          .map((doc) => OrderModel.fromFirestore(doc.data(), doc.id))
          .where((order) {
        if (scope == 'all') return true;
        return allowedBusinessIds.contains(order.sWork);
      }).toList();

      orders.sort((a, b) {
        final aKm = double.tryParse(a.sDinstance) ?? 999999;
        final bKm = double.tryParse(b.sDinstance) ?? 999999;
        return aKm.compareTo(bKm);
      });
      return orders;
    });
  }

  static Future<String?> claimPoolOrder({
    required int courierId,
    required int orderSId,
  }) async {
    final response = await http
        .post(
          Uri.parse(_claimUrl),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'courierId': courierId, 'orderSId': orderSId}),
        )
        .timeout(const Duration(seconds: 12));

    final rawBody = response.body.trim();
    dynamic body;
    if (rawBody.isNotEmpty) {
      try {
        body = jsonDecode(rawBody);
      } catch (_) {
        body = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return null;
    }

    if (body is Map<String, dynamic>) {
      return body['message']?.toString() ?? 'Sipariş alınamadı.';
    }

    if (rawBody.startsWith('<!DOCTYPE') || rawBody.startsWith('<html')) {
      return 'Sunucu beklenmeyen bir yanıt döndürdü (HTML). Lütfen birazdan tekrar deneyin.';
    }

    if (rawBody.isNotEmpty) {
      return 'Sipariş alınamadı (HTTP ${response.statusCode}): $rawBody';
    }

    return 'Sipariş alınamadı (HTTP ${response.statusCode}).';
  }
}
