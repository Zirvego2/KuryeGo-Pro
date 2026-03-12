import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// 📦 TESLİM AL SMS Servisi
/// Kurye siparişi aldığında müşteriye bilgilendirme SMS'i gönderir
class SmsService {
  // 🌐 API Base URL
  static const String _baseUrl = 'https://zirvego.app'; // Production URL
  // Test için: 'http://localhost:3000' veya 'https://your-vercel-url.vercel.app'

  /// 📦 Sipariş teslim alındığında müşteriye SMS gönder
  /// 
  /// [orderDocId] - Firestore'daki sipariş döküman ID'si
  /// 
  /// Returns: SMS gönderim başarılı ise true, değilse false
  static Future<bool> sendPickupSMS(String orderDocId) async {
    try {
      print('📦 TESLİM AL SMS gönderiliyor... Order: $orderDocId');

      // 1️⃣ Firestore'dan sipariş verisini çek
      final orderDoc = await FirebaseFirestore.instance
          .collection('t_orders')
          .doc(orderDocId)
          .get();

      if (!orderDoc.exists) {
        print('⚠️ Sipariş bulunamadı: $orderDocId');
        return false;
      }

      final orderData = orderDoc.data()!;

      // 2️⃣ Müşteri bilgilerini kontrol et
      final customer = orderData['s_customer'] as Map<String, dynamic>?;
      final customerPhone = customer?['ss_phone'] as String?;
      final customerName = customer?['ss_fullname'] as String? ?? 'Müşteri';

      if (customerPhone == null || customerPhone.isEmpty) {
        print('⚠️ Müşteri telefonu yok, SMS gönderilmedi');
        return false;
      }

      // 3️⃣ Bayi ID kontrolü
      final bayId = orderData['s_bay'] as int?;
      if (bayId == null) {
        print('⚠️ Bayi ID bulunamadı');
        return false;
      }

      // 4️⃣ Bayi tracking kontrolü
      final bayDoc = await FirebaseFirestore.instance
          .collection('t_bay')
          .where('s_id', isEqualTo: bayId)
          .limit(1)
          .get();

      if (bayDoc.docs.isEmpty) {
        print('⚠️ Bayi bulunamadı: $bayId');
        return false;
      }

      final bayData = bayDoc.docs.first.data();
      final trackingEnabled = bayData['s_tracking_enabled'] as bool? ?? false;

      if (!trackingEnabled) {
        print('🚫 Bayi $bayId için tracking kapalı, SMS gönderilmedi');
        return false;
      }

      // 5️⃣ Restoran adı (iş yeri adı)
      final restaurantName = orderData['s_work_name'] as String? ?? 'Restoran';
      final orderId = orderData['s_id'] as int? ?? 0;

      // 6️⃣ API'ye istek gönder
      print('📤 TESLİM AL SMS hazırlandı:');
      print('  - Phone: $customerPhone');
      print('  - Customer: $customerName');
      print('  - Restaurant: $restaurantName');
      print('  - Order ID: $orderId');
      print('  - Bay ID: $bayId');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/send-pickup-sms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': customerPhone,
          'customerName': customerName,
          'restaurantName': restaurantName,
          'orderId': orderId.toString(),
          'bayId': bayId,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('SMS API zaman aşımı (10s)');
        },
      );

      print('📬 SMS API Yanıtı:');
      print('  - Status Code: ${response.statusCode}');
      print('  - Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ TESLİM AL SMS başarıyla gönderildi!');
          return true;
        } else {
          print('❌ SMS API hatası: ${data['error']}');
          return false;
        }
      } else {
        print('❌ HTTP Hatası: ${response.statusCode}');
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ TESLİM AL SMS gönderim hatası: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  /// 📍 Sipariş yola çıktığında müşteriye takip linki SMS'i gönder
  /// (Bu fonksiyon mevcut sistem ile entegrasyon için eklenmiştir)
  static Future<bool> sendTrackingSMS(String orderDocId, String trackingToken) async {
    try {
      print('📍 YOLDA SMS gönderiliyor... Order: $orderDocId, Token: $trackingToken');

      // Firestore'dan sipariş verisini çek
      final orderDoc = await FirebaseFirestore.instance
          .collection('t_orders')
          .doc(orderDocId)
          .get();

      if (!orderDoc.exists) {
        print('⚠️ Sipariş bulunamadı: $orderDocId');
        return false;
      }

      final orderData = orderDoc.data()!;
      final customer = orderData['s_customer'] as Map<String, dynamic>?;
      final customerPhone = customer?['ss_phone'] as String?;
      final customerName = customer?['ss_fullname'] as String? ?? 'Müşteri';
      final bayId = orderData['s_bay'] as int?;

      if (customerPhone == null || bayId == null) {
        print('⚠️ Müşteri telefonu veya Bayi ID yok');
        return false;
      }

      // Bayi tracking kontrolü
      final bayDoc = await FirebaseFirestore.instance
          .collection('t_bay')
          .where('s_id', isEqualTo: bayId)
          .limit(1)
          .get();

      if (bayDoc.docs.isEmpty) {
        print('⚠️ Bayi bulunamadı: $bayId');
        return false;
      }

      final bayData = bayDoc.docs.first.data();
      final trackingEnabled = bayData['s_tracking_enabled'] as bool? ?? false;

      if (!trackingEnabled) {
        print('🚫 Bayi $bayId için tracking kapalı, YOLDA SMS gönderilmedi');
        return false;
      }

      // Tracking URL oluştur
      final trackingUrl = '$_baseUrl/takip/$trackingToken';

      // API'ye istek gönder
      final response = await http.post(
        Uri.parse('$_baseUrl/api/send-tracking-sms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': customerPhone,
          'customerName': customerName,
          'trackingUrl': trackingUrl,
          'bayId': bayId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ YOLDA SMS başarıyla gönderildi!');
          return true;
        }
      }

      return false;
    } catch (e) {
      print('❌ YOLDA SMS gönderim hatası: $e');
      return false;
    }
  }

  /// 🚨 Kaza bildirimi SMS'i gönder
  /// Kurye kaza bildirimi yaptığında bayiye SMS gönderir
  /// 
  /// [courierId] - Kurye ID
  /// [bayId] - Bayi ID
  /// 
  /// Returns: SMS gönderim başarılı ise true, değilse false
  static Future<bool> sendAccidentSMS(int courierId, int bayId) async {
    try {
      print('🚨 KAZA BİLDİRİMİ SMS gönderiliyor... Courier: $courierId, Bay: $bayId');

      // 1️⃣ t_bay collection'ından s_phone field'ını çek
      final bayDoc = await FirebaseFirestore.instance
          .collection('t_bay')
          .where('s_id', isEqualTo: bayId)
          .limit(1)
          .get();

      if (bayDoc.docs.isEmpty) {
        print('⚠️ Bayi bulunamadı: $bayId');
        return false;
      }

      final bayData = bayDoc.docs.first.data();
      final bayPhone = bayData['s_phone'] as String?;

      if (bayPhone == null || bayPhone.isEmpty) {
        print('⚠️ Bayi telefonu yok (s_phone), SMS gönderilmedi');
        return false;
      }

      // 2️⃣ Kurye bilgilerini çek (kurye adı için)
      final courierDoc = await FirebaseFirestore.instance
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      String courierName = 'Kurye';
      if (courierDoc.docs.isNotEmpty) {
        final courierData = courierDoc.docs.first.data();
        final courierInfo = courierData['s_info'] as Map<String, dynamic>?;
        final firstName = courierInfo?['ss_name'] as String? ?? '';
        final lastName = courierInfo?['ss_surname'] as String? ?? '';
        courierName = '$firstName $lastName'.trim();
        if (courierName.isEmpty) {
          courierName = courierData['s_phone'] as String? ?? 'Kurye';
        }
      }

      // 3️⃣ API'ye istek gönder
      print('📤 KAZA BİLDİRİMİ SMS hazırlandı:');
      print('  - Bay Phone: $bayPhone');
      print('  - Courier Name: $courierName');
      print('  - Courier ID: $courierId');
      print('  - Bay ID: $bayId');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/send-accident-sms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': bayPhone,
          'courierName': courierName,
          'courierId': courierId,
          'bayId': bayId,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('SMS API zaman aşımı (10s)');
        },
      );

      print('📬 SMS API Yanıtı:');
      print('  - Status Code: ${response.statusCode}');
      print('  - Body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ KAZA BİLDİRİMİ SMS başarıyla gönderildi!');
          return true;
        } else {
          print('❌ SMS API hatası: ${data['error']}');
          return false;
        }
      } else if (response.statusCode == 404) {
        print('❌ ❌ ❌ HTTP 404 Hatası: Backend endpoint bulunamadı!');
        print('⚠️ Backend\'de /api/send-accident-sms endpoint\'i oluşturulmalı!');
        print('   Mevcut endpoint\'ler: /api/send-pickup-sms, /api/send-tracking-sms');
        return false;
      } else {
        print('❌ HTTP Hatası: ${response.statusCode}');
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ KAZA BİLDİRİMİ SMS gönderim hatası: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }
}

