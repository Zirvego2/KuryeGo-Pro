import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/courier_cash_transaction_model.dart';

/// Kurye Nakit Transaction Servisi
/// Her sipariş için nakit işlemlerini kaydeder
class CourierCashTransactionService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collectionName = 't_courier_cash_transactions';

  /// Nakit transaction kaydı oluştur
  /// 
  /// [orderId] - Sipariş docId
  /// [orderPid] - Platform Order ID
  /// [courierId] - Kurye ID
  /// [bayId] - Bay ID
  /// [workId] - Restoran/İşletme ID (t_workid) - null olabilir
  /// [originalPaymentType] - Orijinal ödeme tipi (0=Nakit, 1=Kart, 2=Online)
  /// [finalPaymentType] - Son ödeme tipi (0=Nakit, 1=Kart, 2=Online)
  /// [cashAmount] - Nakit tutarı
  /// [orderDeliveredAt] - Sipariş teslim tarihi
  static Future<void> createCashTransaction({
    required String orderId,
    required String orderPid,
    required int courierId,
    required int bayId,
    int? workId,
    required int originalPaymentType,
    required int finalPaymentType,
    required double cashAmount,
    required DateTime orderDeliveredAt,
  }) async {
    try {
      // Sadece nakit işlemi varsa kaydet
      if (cashAmount <= 0) {
        print('⚠️ Nakit tutarı 0, transaction kaydı oluşturulmayacak');
        return;
      }

      // Transaction tipini belirle
      String transactionType;
      if (originalPaymentType == 0) {
        // Zaten nakitliydi, müşteriden nakit alındı
        transactionType = 'cash_received';
      } else {
        // Ödeme nakit çevrildi (kart/online -> nakit)
        transactionType = 'payment_converted_to_cash';
      }

      print('💰 Nakit transaction kaydı oluşturuluyor...');
      print('   Sipariş: $orderId ($orderPid)');
      print('   Kurye: $courierId');
      print('   Bay: $bayId');
      if (workId != null) print('   Restoran: $workId');
      print('   Tip: $transactionType');
      print('   Tutar: $cashAmount₺');
      print('   Orijinal Ödeme: ${_getPaymentTypeName(originalPaymentType)}');
      print('   Son Ödeme: ${_getPaymentTypeName(finalPaymentType)}');

      final transaction = CourierCashTransactionModel(
        docId: '', // Firestore otomatik oluşturacak
        orderId: orderId,
        orderPid: orderPid,
        courierId: courierId,
        bayId: bayId,
        workId: workId,
        transactionType: transactionType,
        cashAmount: cashAmount,
        originalPaymentType: originalPaymentType,
        finalPaymentType: finalPaymentType,
        transactionDate: DateTime.now(),
        orderDeliveredAt: orderDeliveredAt,
      );

      await _db.collection(_collectionName).add(transaction.toFirestore());

      print('✅ Nakit transaction kaydı oluşturuldu!');
    } catch (e) {
      print('❌ Nakit transaction kaydı hatası: $e');
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

  /// Kuryenin nakit transaction'larını getir
  static Future<List<CourierCashTransactionModel>> getCourierTransactions({
    required int courierId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query query = _db
          .collection(_collectionName)
          .where('courier_id', isEqualTo: courierId);

      if (startDate != null) {
        query = query.where('transaction_date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }

      if (endDate != null) {
        query = query.where('transaction_date',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }

      final snapshot = await query.orderBy('transaction_date', descending: true).get();

      return snapshot.docs.map((doc) {
        return CourierCashTransactionModel.fromFirestore(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
    } catch (e) {
      print('❌ Transaction sorgulama hatası: $e');
      return [];
    }
  }
}
