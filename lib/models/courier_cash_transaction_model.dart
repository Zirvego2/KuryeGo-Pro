import 'package:cloud_firestore/cloud_firestore.dart';

/// Kurye Nakit Transaction Modeli
/// Her sipariş için nakit işlemi kaydı (t_courier_cash_transactions)
class CourierCashTransactionModel {
  final String docId;
  final String orderId; // Sipariş docId
  final String orderPid; // Platform Order ID
  final int courierId; // Kurye ID
  final int bayId; // Bay ID
  final int? workId; // Restoran/İşletme ID (t_workid) - null olabilir
  final String transactionType; // "cash_received" veya "payment_converted_to_cash"
  final double cashAmount; // Nakit tutarı
  final int originalPaymentType; // Orijinal ödeme tipi (0=Nakit, 1=Kart, 2=Online)
  final int finalPaymentType; // Son ödeme tipi (0=Nakit, 1=Kart, 2=Online)
  final DateTime transactionDate; // İşlem tarihi
  final DateTime orderDeliveredAt; // Sipariş teslim tarihi

  CourierCashTransactionModel({
    required this.docId,
    required this.orderId,
    required this.orderPid,
    required this.courierId,
    required this.bayId,
    this.workId,
    required this.transactionType,
    required this.cashAmount,
    required this.originalPaymentType,
    required this.finalPaymentType,
    required this.transactionDate,
    required this.orderDeliveredAt,
  });

  /// Firestore'dan model oluştur
  factory CourierCashTransactionModel.fromFirestore(
    Map<String, dynamic> data,
    String docId,
  ) {
    return CourierCashTransactionModel(
      docId: docId,
      orderId: data['order_id'] ?? '',
      orderPid: data['order_pid'] ?? '',
      courierId: data['courier_id'] ?? 0,
      bayId: data['bay_id'] ?? 0,
      workId: data['work_id'],
      transactionType: data['transaction_type'] ?? '',
      cashAmount: (data['cash_amount'] ?? 0).toDouble(),
      originalPaymentType: data['original_payment_type'] ?? 0,
      finalPaymentType: data['final_payment_type'] ?? 0,
      transactionDate: data['transaction_date'] != null
          ? (data['transaction_date'] as Timestamp).toDate()
          : DateTime.now(),
      orderDeliveredAt: data['order_delivered_at'] != null
          ? (data['order_delivered_at'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  /// Firestore'a kaydetmek için Map'e çevir
  Map<String, dynamic> toFirestore() {
    return {
      'order_id': orderId,
      'order_pid': orderPid,
      'courier_id': courierId,
      'bay_id': bayId,
      if (workId != null) 'work_id': workId,
      'transaction_type': transactionType,
      'cash_amount': cashAmount,
      'original_payment_type': originalPaymentType,
      'final_payment_type': finalPaymentType,
      'transaction_date': Timestamp.fromDate(transactionDate),
      'order_delivered_at': Timestamp.fromDate(orderDeliveredAt),
    };
  }
}
