import 'package:cloud_firestore/cloud_firestore.dart';

/// Ödeme değişikliği loglama servisi
/// React Native PaymentChangeLogger.js karşılığı
class PaymentChangeLogger {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Ödeme değişikliğini logla (Firestore'a)
  static Future<void> logPaymentChange({
    required String orderId,
    required int courierId,
    required String orderPid,
    required Map<String, dynamic> oldPayment,
    required Map<String, dynamic> newPayment,
  }) async {
    try {
      print('📝 Ödeme değişikliği loglanıyor...');
      print('   Sipariş: $orderId');
      print('   Kurye: $courierId');
      print('   Eski: ${oldPayment.toString()}');
      print('   Yeni: ${newPayment.toString()}');

      // Değişiklik detayı
      final changeDetails = <String, dynamic>{};

      // Nakit değişimi
      if (oldPayment['cash'] != newPayment['cash']) {
        changeDetails['cash_change'] = {
          'old': oldPayment['cash'],
          'new': newPayment['cash'],
        };
      }

      // Kart değişimi
      if (oldPayment['card'] != newPayment['card']) {
        changeDetails['card_change'] = {
          'old': oldPayment['card'],
          'new': newPayment['card'],
        };
      }

      // Online ödeme değişimi
      if (oldPayment['online'] != newPayment['online']) {
        changeDetails['online_change'] = {
          'old': oldPayment['online'],
          'new': newPayment['online'],
        };
      }

      // Ödeme tipi değişimi
      if (oldPayment['type'] != newPayment['type']) {
        changeDetails['payment_type_change'] = {
          'old': _getPaymentTypeName(oldPayment['type']),
          'new': _getPaymentTypeName(newPayment['type']),
        };
      }

      // Toplam tutar değişimi
      if (oldPayment['total'] != newPayment['total']) {
        changeDetails['total_change'] = {
          'old': oldPayment['total'],
          'new': newPayment['total'],
        };
      }

      // Firestore'a log kaydet
      await _db.collection('t_payment_changes').add({
        's_order_id': orderId,
        's_order_pid': orderPid,
        's_courier_id': courierId,
        's_old_payment': oldPayment,
        's_new_payment': newPayment,
        's_changes': changeDetails,
        's_timestamp': FieldValue.serverTimestamp(),
        's_date': DateTime.now().toIso8601String(),
      });

      print('✅ Ödeme değişikliği loglandı!');
    } catch (e) {
      print('❌ Ödeme değişikliği loglama hatası: $e');
      // Hata olsa bile throw etme, sipariş işlemini engelleme
    }
  }

  /// Ödeme tipi adını getir
  static String _getPaymentTypeName(int type) {
    switch (type) {
      case 0:
        return 'Nakit';
      case 1:
        return 'Kart';
      case 2:
        return 'Online';
      default:
        return 'Bilinmeyen';
    }
  }
}

