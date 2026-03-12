import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 🔒 Gizlilik Politikası Ekranı
/// Google Play & Apple Store onayı için ZORUNLU
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  // ⭐ Gizlilik politikası URL'i (web sitenizdeki gerçek URL ile değiştirin)
  static const String privacyPolicyUrl = 'https://zirvego.com/privacy-policy';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '🔒 Gizlilik Politikası',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık
            const Text(
              'ZirveGo Kurye\nGizlilik Politikası',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Son güncelleme: 20 Kasım 2024',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 32),

            // Web'de görüntüle butonu
            _buildWebButton(context),
            const SizedBox(height: 32),

            // Kısa özet
            const Text(
              '📋 Özet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoBox(
              icon: Icons.location_on,
              title: 'Konum Verisi',
              content:
                  'Uygulamanız açık veya kapalıyken, sipariş yönlendirme ve teslimat doğrulaması için konumunuz toplanır.',
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildInfoBox(
              icon: Icons.person,
              title: 'Kişisel Bilgiler',
              content:
                  'Ad, soyad, telefon, e-posta, IBAN ve plaka bilgileriniz güvenli bir şekilde saklanır.',
              color: Colors.orange,
            ),
            const SizedBox(height: 12),
            _buildInfoBox(
              icon: Icons.analytics,
              title: 'Teslimat Verileri',
              content:
                  'Teslimat sayısı, mesafe, kazanç bilgileri hesaplama için kullanılır.',
              color: Colors.green,
            ),
            const SizedBox(height: 12),
            _buildInfoBox(
              icon: Icons.lock,
              title: 'Veri Güvenliği',
              content:
                  'Tüm verileriniz Firebase üzerinde şifreli olarak saklanır ve üçüncü taraflarla paylaşılmaz.',
              color: Colors.red,
            ),

            const SizedBox(height: 32),

            // Detaylı açıklamalar
            const Text(
              '📖 Detaylı Açıklama',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            _buildSection(
              title: '1. Topladığımız Veriler',
              content: '''
⭐ Konum Bilgisi:
• Arka planda (uygulama kapalıyken) ve ön planda (uygulama açıkken) konumunuz toplanır
• Amaç: Sipariş yönlendirme, mesafe hesaplama, teslimat doğrulama
• Kullanım: Firebase Firestore'da güvenli şekilde saklanır

👤 Kişisel Bilgiler:
• Ad, Soyad, Telefon, E-posta
• IBAN (ödeme için)
• Plaka ve Araç Modeli

📊 Teslimat Bilgileri:
• Teslim edilen sipariş sayısı
• Katedilen mesafe
• Kazanç bilgileri
''',
            ),

            _buildSection(
              title: '2. Verilerin Kullanım Amacı',
              content: '''
✅ Sipariş yönlendirme
✅ Teslimat mesafesi hesaplama
✅ Teslimat doğrulama
✅ Kazanç hesaplama
✅ Rota optimizasyonu
✅ Performans analizi
''',
            ),

            _buildSection(
              title: '3. Veri Paylaşımı',
              content: '''
🔒 Verileriniz ASLA üçüncü taraflarla paylaşılmaz.

Sadece şu durumlar istisnadır:
• Yasal zorunluluk (mahkeme kararı vb.)
• Güvenlik ihlali durumu
• Kullanıcı açık rızası
''',
            ),

            _buildSection(
              title: '4. Veri Güvenliği',
              content: '''
🛡️ Firebase Firestore: End-to-end şifreleme
🛡️ SSL/TLS: Tüm veri aktarımları şifreli
🛡️ Erişim Kontrolü: Sadece yetkili personel
🛡️ Düzenli yedekleme ve felaket kurtarma planı
''',
            ),

            _buildSection(
              title: '5. Kullanıcı Hakları',
              content: '''
✔️ Verilerinizi görüntüleme hakkı
✔️ Verilerinizi düzeltme hakkı
✔️ Verilerinizi silme hakkı (Ayarlar > Hesabımı Sil)
✔️ Veri taşınabilirliği hakkı
✔️ İtiraz etme hakkı

📧 İletişim: support@zirvego.com
📞 Telefon: +90 530 905 20 18
''',
            ),

            const SizedBox(height: 32),

            // Tam metin için web'e yönlendir
            Center(
              child: Text(
                'Tam metni web sitemizde okuyabilirsiniz 👇',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildWebButton(context),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// Bilgi kutusu
  Widget _buildInfoBox({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bölüm
  Widget _buildSection({
    required String title,
    required String content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Web'de Görüntüle Butonu
  Widget _buildWebButton(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () => _openPrivacyPolicyWeb(context),
        icon: const Icon(Icons.open_in_browser),
        label: const Text('Web Sitesinde Görüntüle'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2196F3),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// Web'de gizlilik politikasını aç
  Future<void> _openPrivacyPolicyWeb(BuildContext context) async {
    try {
      final uri = Uri.parse(privacyPolicyUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Web sitesi açılamadı'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ URL açılma hatası: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

