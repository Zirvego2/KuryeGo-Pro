import 'package:http/http.dart' as http;
import 'dart:convert';

/// JaviPos API Servisi
/// Sipariş durumu güncelleme API'si
class JaviPosApiService {
  // ⭐ API URL
  static const String _baseUrl = 'https://webapi.javipos.com';
  static const String _endpoint = '/api/Package/setPackageStatusList';

  /// JaviPos API çağrısı - Sipariş durumu güncelleme
  /// 
  /// [javiPosid] - JaviPosid (Id için)
  /// [clientId] - ClientId (UserId için)
  /// [status] - Status: "2"=Hazırlanıyor, "3"=Yolda, "4"=Teslim Edildi
  static Future<bool> updateOrderStatus({
    required String javiPosid,
    required String clientId,
    required String status, // "2", "3", "4"
    int maxRetries = 3,
  }) async {
    print('📱 JaviPos API - Sipariş durumu güncelleme başlatılıyor...');
    print('   JaviPosid: $javiPosid');
    print('   ClientId: $clientId');
    print('   Status: $status');

    // Validasyon
    if (javiPosid.isEmpty) {
      print('❌ JaviPosid bulunamadı!');
      return false;
    }

    if (clientId.isEmpty) {
      print('❌ ClientId bulunamadı!');
      return false;
    }

    if (!['2', '3', '4'].contains(status)) {
      print('❌ Geçersiz status: $status (2, 3 veya 4 olmalı)');
      return false;
    }

    // Request body
    final requestBody = json.encode([
      {
        'Id': javiPosid,
        'Status': status,
        'UserId': clientId,
      }
    ]);

    // Headers
    final headers = {
      'Authorization': 'Basic SmFydmlzUG9zOINoYXJrMTIzKg==',
      'x-clientid': clientId,
      'Content-Type': 'application/json',
    };

    // API URL
    final apiUrl = '$_baseUrl$_endpoint';

    // Retry mekanizması ile API çağrısı
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🌐 API URL: $apiUrl');
        print('📤 Request Body: $requestBody');
        print('🔑 Headers: $headers');

        final response = await http.post(
          Uri.parse(apiUrl),
          headers: headers,
          body: requestBody,
        ).timeout(const Duration(seconds: 10));

        print('📨 API yanıtı (${response.statusCode}): ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          print('✅ JaviPos API - Sipariş durumu güncellendi!');
          return true;
        }

        print('⚠️ API başarısız (deneme $attempt/$maxRetries), tekrar deneniyor...');

        if (attempt < maxRetries) {
          // Exponential backoff
          await Future.delayed(Duration(seconds: attempt));
        }
      } catch (e) {
        print('❌ JaviPos API hatası (deneme $attempt/$maxRetries): $e');

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    print('❌ JaviPos API - Maksimum deneme sayısına ulaşıldı');
    return false;
  }
}
