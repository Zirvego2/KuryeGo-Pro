import 'dart:convert';
import 'package:http/http.dart' as http;

class SepettakipStatusService {
  static const String _baseUrl = 'https://zirvego.app/api';

  static bool isSepettakipOrder(String? source) {
    return (source ?? '').toLowerCase() == 'sepettakip';
  }

  static Future<void> notifyAssigned({
    required int orderId,
    required int courierId,
  }) async {
    final uri = Uri.parse('$_baseUrl/courier-order-response');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'orderId': orderId,
            'courierId': courierId,
            'accepted': true,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('assigned status gonderilemedi: HTTP ${response.statusCode}');
    }
  }

  static Future<void> notifyPickedUp({
    required int orderId,
    required int courierId,
  }) async {
    await _notifyOrderStatus(orderId: orderId, courierId: courierId, status: 1);
  }

  static Future<void> notifyDelivered({
    required int orderId,
    required int courierId,
  }) async {
    await _notifyOrderStatus(orderId: orderId, courierId: courierId, status: 2);
  }

  static Future<void> _notifyOrderStatus({
    required int orderId,
    required int courierId,
    required int status,
  }) async {
    final uri = Uri.parse('$_baseUrl/updateOrderStatus');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'orderId': orderId,
            'status': status,
            'courierId': courierId,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('status gonderilemedi ($status): HTTP ${response.statusCode}');
    }
  }
}

