import 'package:cloud_firestore/cloud_firestore.dart';

/// Sipariş modeli (t_orders)
class OrderModel {
  final String docId;
  final int sId;
  final int sBay;
  final int sWork;
  final int sCourier;
  final int sStat; // 0=Yeni, 1=Teslim alındı, 2=Teslim edildi
  final int sOrderscr; // 1=Getir, 2=YemekSepeti, 3=Trendyol, 4=Migros
  final String sPid; // Platform Order ID
  final String sOrderid; // Sipariş ID (API için)
  final String sOrganizationToken; // Platform API Token
  final DateTime? sCdate; // Oluşturulma tarihi
  final int sReady; // Hazırlık süresi (dakika)
  final DateTime? sReceived; // Teslim alma zamanı
  final DateTime? sDelivered; // Teslim etme zamanı

  // Müşteri bilgileri
  final String ssFullname;
  final String ssPhone;
  final String ssAdres;
  final String ssNote;
  final Map<String, dynamic>? ssLoc; // {latitude, longitude}

  // İşletme bilgileri
  final String sNameWork;
  final String? sRestaurantName; // Restoran adı
  final String sPhonework;
  final String sWorkAdres;
  final Map<String, dynamic>? ssLocationWork; // {latitude, longitude}

  // Ödeme bilgileri
  final int ssPaytype; // 0=Nakit, 1=Kart, 2=Online
  final double ssPaycount;
  // Yeni ödeme alanları
  final int? sOdemeId;     // 4-31
  final String? sOdemeAdi; // "Nakit", "Multinet" vb.

  // Mesafe
  final String sDinstance;

  // Onay sistemi
  final bool? sCourierAccepted;
  final DateTime? sCourierResponseTime; // Kurye onay/red zamanı (geriye dönük)
  final DateTime? sAcceptedAt;          // Onaylanma zamanı
  final DateTime? sRejectedAt;          // Red zamanı

  // JaviPos API için
  final String? clientId; // ClientId (UserId için)
  final String? javiPosid; // JaviPosid (Id için)
  
  // Yeni nesil ödeme alanları (paymentMethodOriginal)
  final int? paymentMethodId;     // paymentMethodOriginal.id
  final String? paymentMethodText; // paymentMethodOriginal.text

  OrderModel({
    required this.docId,
    required this.sId,
    required this.sBay,
    required this.sWork,
    required this.sCourier,
    required this.sStat,
    required this.sOrderscr,
    required this.sPid,
    required this.sOrderid,
    required this.sOrganizationToken,
    this.sCdate,
    required this.sReady,
    this.sReceived,
    this.sDelivered,
    required this.ssFullname,
    required this.ssPhone,
    required this.ssAdres,
    required this.ssNote,
    this.ssLoc,
    required this.sNameWork,
    this.sRestaurantName,
    required this.sPhonework,
    required this.sWorkAdres,
    this.ssLocationWork,
    required this.ssPaytype,
    required this.ssPaycount,
    this.sOdemeId,
    this.sOdemeAdi,
    required this.sDinstance,
    this.sCourierAccepted,
    this.sCourierResponseTime,
    this.sAcceptedAt,
    this.sRejectedAt,
    this.clientId,
    this.javiPosid,
    this.paymentMethodId,
    this.paymentMethodText,
  });

  /// GeoPoint'i Map'e çevir
  static Map<String, dynamic>? _parseGeoPoint(dynamic geoData) {
    if (geoData == null) return null;
    
    // Zaten Map ise direkt döndür
    if (geoData is Map<String, dynamic>) {
      return geoData;
    }
    
    // GeoPoint ise Map'e çevir
    if (geoData is GeoPoint) {
      return {
        'latitude': geoData.latitude,
        'longitude': geoData.longitude,
      };
    }
    
    return null;
  }

  factory OrderModel.fromFirestore(Map<String, dynamic> data, String docId) {
    // ⭐ Tip güvenli String dönüşümü (int veya String olabilir)
    String toStringValue(dynamic value, String defaultValue) {
      if (value == null) return defaultValue;
      if (value is String) return value;
      if (value is int) return value.toString();
      return value.toString();
    }
    
    return OrderModel(
      docId: docId,
      sId: data['s_id'] ?? 0,
      sBay: data['s_bay'] ?? 0,
      sWork: data['s_work'] ?? 0,
      sCourier: data['s_courier'] ?? 0,
      sStat: data['s_stat'] ?? 0,
      sOrderscr: data['s_orderscr'] ?? 0,
      sPid: toStringValue(data['s_pid'], ''),
      sOrderid: toStringValue(data['s_orderid'], toStringValue(data['s_pid'], '')),
      sOrganizationToken: toStringValue(data['s_organizationToken'], ''),
      sCdate: data['s_cdate'] != null
          ? (data['s_cdate'] as Timestamp).toDate()
          : null,
      sReady: data['s_ready'] ?? 0,
      sReceived: data['s_received'] != null
          ? (data['s_received'] as Timestamp).toDate()
          : null,
      sDelivered: data['s_delivered'] != null
          ? (data['s_delivered'] as Timestamp).toDate()
          : null,
      ssFullname: toStringValue(data['s_customer']?['ss_fullname'] ?? data['ss_fullname'], ''),
      ssPhone: toStringValue(data['s_customer']?['ss_phone'] ?? data['ss_phone'], ''),
      ssAdres: toStringValue(data['s_customer']?['ss_adres'] ?? data['ss_adres'], ''),
      ssNote: toStringValue(data['s_customer']?['ss_note'] ?? data['ss_note'], ''),
      ssLoc: _parseGeoPoint(data['s_customer']?['ss_loc'] ?? data['ss_loc']),
      sNameWork: toStringValue(data['s_nameWork'] ?? data['s_restaurantName'], ''),
      sRestaurantName: data['s_restaurantName'] != null ? toStringValue(data['s_restaurantName'], '') : null,
      sPhonework: toStringValue(data['s_phonework'], ''),
      sWorkAdres: toStringValue(data['s_workAdres'], ''),
      ssLocationWork: _parseGeoPoint(data['ss_locationWork']),
      ssPaytype: data['s_pay']?['ss_paytype'] ?? data['ss_paytype'] ?? 0,
      ssPaycount: (data['s_pay']?['ss_paycount'] ?? data['ss_paycount'] ?? 0).toDouble(),
      sOdemeId: data['s_odeme_id'] is int ? data['s_odeme_id'] : int.tryParse('${data['s_odeme_id'] ?? ''}'),
      sOdemeAdi: data['s_odeme_adi']?.toString(),
      sDinstance: data['s_dinstance']?.toString() ?? '0',
      sCourierAccepted: data['s_courier_accepted'],
      sCourierResponseTime: data['s_courier_response_time'] != null
          ? (data['s_courier_response_time'] as Timestamp).toDate()
          : null,
      sAcceptedAt: data['s_accepted_at'] != null
          ? (data['s_accepted_at'] as Timestamp).toDate()
          : null,
      sRejectedAt: data['s_rejected_at'] != null
          ? (data['s_rejected_at'] as Timestamp).toDate()
          : null,
      clientId: data['ClientId']?.toString(),
      javiPosid: data['JaviPosid']?.toString(),
      paymentMethodId: data['paymentMethodOriginal'] == null
          ? null
          : (data['paymentMethodOriginal']['id'] is int
              ? (data['paymentMethodOriginal']['id'] as int)
              : int.tryParse(data['paymentMethodOriginal']['id']?.toString() ?? '')),
      paymentMethodText: data['paymentMethodOriginal']?['text']?.toString(),
    );
  }
}

