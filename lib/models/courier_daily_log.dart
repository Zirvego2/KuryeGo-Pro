import 'package:cloud_firestore/cloud_firestore.dart';

/// Kurye Günlük Vardiya Log Modeli
/// Firestore: courier_daily_logs collection
class CourierDailyLog {
  final String? docId;
  final int courierId;
  final DateTime shiftStartAt;
  final DateTime? shiftEndAt;
  final String shiftDate; // YYYY-MM-DD formatında
  final String status; // "ACTIVE" | "BREAK" | "OFF"
  final int breakAllowedMinutes; // Günlük mola hakkı (dakika)
  final int breakUsedMinutes; // Kullanılan mola (dakika)
  final int breakRemainingMinutes; // Kalan mola (dakika)
  final List<BreakSession> breaks; // Parça parça mola oturumları
  final bool isClosed; // Vardiya kapalı mı?
  final DateTime? closedAt; // Vardiya kapanma zamanı
  final int? earlyStartMinutes; // ⭐ Vardiya başlangıç saatinden kaç dakika erken giriş yaptı (null = geç veya zamanında)
  final int? lateStartMinutes; // ⭐ Vardiya başlangıç saatinden kaç dakika geç giriş yaptı (null = erken veya zamanında)

  CourierDailyLog({
    this.docId,
    required this.courierId,
    required this.shiftStartAt,
    this.shiftEndAt,
    required this.shiftDate,
    required this.status,
    required this.breakAllowedMinutes,
    required this.breakUsedMinutes,
    required this.breakRemainingMinutes,
    required this.breaks,
    required this.isClosed,
    this.closedAt,
    this.earlyStartMinutes, // ⭐ Erken giriş dakikası
    this.lateStartMinutes, // ⭐ Geç giriş dakikası
  });

  /// Firestore'dan model oluştur
  factory CourierDailyLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CourierDailyLog(
      docId: doc.id,
      courierId: data['courierId'] as int,
      shiftStartAt: (data['shiftStartAt'] as Timestamp).toDate(),
      shiftEndAt: data['shiftEndAt'] != null
          ? (data['shiftEndAt'] as Timestamp).toDate()
          : null,
      shiftDate: data['shiftDate'] as String,
      status: data['status'] as String? ?? 'OFF',
      breakAllowedMinutes: data['breakAllowedMinutes'] as int? ?? 0,
      breakUsedMinutes: data['breakUsedMinutes'] as int? ?? 0,
      breakRemainingMinutes: data['breakRemainingMinutes'] as int? ?? 0,
      breaks: (data['breaks'] as List<dynamic>?)
              ?.map((b) => BreakSession.fromMap(b as Map<String, dynamic>))
              .toList() ??
          [],
      isClosed: data['isClosed'] as bool? ?? false,
      closedAt: data['closedAt'] != null
          ? (data['closedAt'] as Timestamp).toDate()
          : null,
      earlyStartMinutes: data['earlyStartMinutes'] as int?, // ⭐ Erken giriş dakikası
      lateStartMinutes: data['lateStartMinutes'] as int?, // ⭐ Geç giriş dakikası
    );
  }

  /// Firestore'a yazmak için Map'e dönüştür
  Map<String, dynamic> toFirestore() {
    return {
      'courierId': courierId,
      'shiftStartAt': Timestamp.fromDate(shiftStartAt),
      'shiftEndAt': shiftEndAt != null ? Timestamp.fromDate(shiftEndAt!) : null,
      'shiftDate': shiftDate,
      'status': status,
      'breakAllowedMinutes': breakAllowedMinutes,
      'breakUsedMinutes': breakUsedMinutes,
      'breakRemainingMinutes': breakRemainingMinutes,
      'breaks': breaks.map((b) => b.toMap()).toList(),
      'isClosed': isClosed,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'earlyStartMinutes': earlyStartMinutes, // ⭐ Erken giriş dakikası
      'lateStartMinutes': lateStartMinutes, // ⭐ Geç giriş dakikası
    };
  }

  /// CopyWith metodu (güncellemeler için)
  CourierDailyLog copyWith({
    String? docId,
    int? courierId,
    DateTime? shiftStartAt,
    DateTime? shiftEndAt,
    String? shiftDate,
    String? status,
    int? breakAllowedMinutes,
    int? breakUsedMinutes,
    int? breakRemainingMinutes,
    List<BreakSession>? breaks,
    bool? isClosed,
    DateTime? closedAt,
    int? earlyStartMinutes, // ⭐ Erken giriş dakikası
    int? lateStartMinutes, // ⭐ Geç giriş dakikası
  }) {
    return CourierDailyLog(
      docId: docId ?? this.docId,
      courierId: courierId ?? this.courierId,
      shiftStartAt: shiftStartAt ?? this.shiftStartAt,
      shiftEndAt: shiftEndAt ?? this.shiftEndAt,
      shiftDate: shiftDate ?? this.shiftDate,
      status: status ?? this.status,
      breakAllowedMinutes: breakAllowedMinutes ?? this.breakAllowedMinutes,
      breakUsedMinutes: breakUsedMinutes ?? this.breakUsedMinutes,
      breakRemainingMinutes:
          breakRemainingMinutes ?? this.breakRemainingMinutes,
      breaks: breaks ?? this.breaks,
      isClosed: isClosed ?? this.isClosed,
      closedAt: closedAt ?? this.closedAt,
      earlyStartMinutes: earlyStartMinutes ?? this.earlyStartMinutes, // ⭐ Erken giriş dakikası
      lateStartMinutes: lateStartMinutes ?? this.lateStartMinutes, // ⭐ Geç giriş dakikası
    );
  }
}

/// Parça Parça Mola Oturumu
class BreakSession {
  final DateTime startAt;
  final DateTime? endAt;
  final int minutes; // Kullanılan dakika (endAt doldurulduğunda hesaplanır)
  final int? remainingAtStart; // Mola başladığında kalan süre (dakika) - otomatik bitiş için

  BreakSession({
    required this.startAt,
    this.endAt,
    required this.minutes,
    this.remainingAtStart, // Opsiyonel - otomatik bitiş için gerekli
  });

  /// Map'ten model oluştur
  factory BreakSession.fromMap(Map<String, dynamic> map) {
    return BreakSession(
      startAt: (map['startAt'] as Timestamp).toDate(),
      endAt: map['endAt'] != null
          ? (map['endAt'] as Timestamp).toDate()
          : null,
      minutes: map['minutes'] as int? ?? 0,
      remainingAtStart: map['remainingAtStart'] as int?,
    );
  }

  /// Map'e dönüştür
  Map<String, dynamic> toMap() {
    return {
      'startAt': Timestamp.fromDate(startAt),
      'endAt': endAt != null ? Timestamp.fromDate(endAt!) : null,
      'minutes': minutes,
      'remainingAtStart': remainingAtStart,
    };
  }

  /// Aktif mola mı? (endAt null ise)
  bool get isActive => endAt == null;

  /// CopyWith
  BreakSession copyWith({
    DateTime? startAt,
    DateTime? endAt,
    int? minutes,
    int? remainingAtStart,
  }) {
    return BreakSession(
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      minutes: minutes ?? this.minutes,
      remainingAtStart: remainingAtStart ?? this.remainingAtStart,
    );
  }
}
