import 'package:http/http.dart' as http;

/// Platform API Servisi
/// Posentegra changeStatus API entegrasyonu
class PlatformApiService {
  /// Platform API çağrısı - Sipariş durumu değişikliği
  /// organizationToken: Authorization header için token
  /// orderId: s_orderid (Sipariş ID)
  static Future<bool> callPlatformDeliveryApi({
    required int platformId,
    required String organizationToken,
    required String orderId,
    int maxRetries = 3,
  }) async {
    print('📱 Sipariş durumu değişikliği başlatılıyor...');
    print('   Sipariş ID: $orderId');
    print('   Platform ID: $platformId');

    // Token kontrolü
    if (organizationToken.isEmpty) {
      print('❌ Authorization token bulunamadı!');
      return false;
    }

    // OrderId kontrolü
    if (orderId.isEmpty) {
      print('❌ Sipariş ID bulunamadı!');
      return false;
    }

    // ⭐ Token işleme: Pipe varsa SADECE pipe'dan SONRAKİ kısmı kullan
    String actualToken = organizationToken;
    print('   Token (ORIJINAL): $organizationToken');
    print('   Token uzunluğu: ${organizationToken.length} karakter');
    
    if (organizationToken.contains('|')) {
      final parts = organizationToken.split('|');
      actualToken = parts[1]; // Pipe'dan sonraki kısım
      print('   Token pipe ile ayrıldı:');
      print('      Pipe öncesi: ${parts[0]}');
      print('      Pipe sonrası (KULLANILACAK): $actualToken');
    } else {
      print('   Token içinde pipe yok, olduğu gibi kullanılacak');
    }

    // API URL
    final apiUrl = 'https://zirvego.client.posentegra.com/api/pe/changeStatus?id=$orderId';

    // Retry mekanizması ile API çağrısı
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🌐 API URL: $apiUrl');
        print('🔑 Authorization Header: Bearer $actualToken');

        final response = await http.get(
          Uri.parse(apiUrl),
          headers: {
            'Authorization': 'Bearer $actualToken',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));

        print('📨 API yanıtı (${response.statusCode}): ${response.body}');

        if (response.statusCode == 200) {
          print('✅ Sipariş durumu güncellendi!');
          return true;
        } else if (response.statusCode == 201) {
          print('✅ Sipariş durumu güncellendi! (201)');
          return true;
        }

        print('⚠️ API başarısız (deneme $attempt/$maxRetries), tekrar deneniyor...');

        if (attempt < maxRetries) {
          // Exponential backoff
          await Future.delayed(Duration(seconds: attempt));
        }
      } catch (e) {
        print('❌ API hatası (deneme $attempt/$maxRetries): $e');

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    print('❌ Maksimum deneme sayısına ulaşıldı');
    return false;
  }
}

