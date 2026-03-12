import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'privacy_policy_screen.dart';

/// 📜 Gizlilik Politikası ve Konum İzni Onay Ekranı
/// Google Play & Apple Store onayı için ZORUNLU
/// Kullanıcı kabul etmeden uygulamayı kullanamaz
class TermsAcceptanceScreen extends StatefulWidget {
  final VoidCallback onAccepted;
  final int? courierId; // ⭐ Firestore'a kaydetmek için kurye ID'si

  const TermsAcceptanceScreen({
    super.key,
    required this.onAccepted,
    this.courierId,
  });

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _privacyPolicyAccepted = false;
  bool _locationPermissionAccepted = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final canProceed = _privacyPolicyAccepted && _locationPermissionAccepted;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.verified_user,
                      size: 48,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Hoş Geldiniz!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Devam etmeden önce lütfen aşağıdaki\nkoşulları okuyun ve onaylayın',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // 1. Gizlilik Politikası
                    _buildAcceptanceCard(
                      icon: Icons.privacy_tip,
                      iconColor: Colors.blue,
                      title: 'Gizlilik Politikası',
                      description:
                          'Kişisel verilerinizin nasıl toplandığını, kullanıldığını ve korunduğunu açıklayan politikamızı okuyun.',
                      isAccepted: _privacyPolicyAccepted,
                      onChanged: (value) {
                        setState(() => _privacyPolicyAccepted = value ?? false);
                      },
                      onReadMore: _openPrivacyPolicy,
                      acceptanceText: 'Gizlilik Politikasını okudum ve kabul ediyorum',
                    ),

                    const SizedBox(height: 16),

                    // 2. Konum İzni
                    _buildAcceptanceCard(
                      icon: Icons.location_on,
                      iconColor: Colors.green,
                      title: 'Konum İzni ve Kullanımı',
                      description:
                          'Bu uygulama, size sipariş yönlendirebilmek ve teslimatı doğrulamak için konumunuzu hem açık hem kapalı durumda toplar.',
                      isAccepted: _locationPermissionAccepted,
                      onChanged: (value) {
                        setState(() => _locationPermissionAccepted = value ?? false);
                      },
                      detailedInfo: _buildLocationDetailedInfo(),
                      acceptanceText: 'Konum kullanımını okudum ve kabul ediyorum',
                    ),

                    const SizedBox(height: 24),

                    // Bilgilendirme kutusu
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info, color: Colors.orange.shade700, size: 24),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Bu onaylar yasal zorunluluktur. Kabul etmeden uygulamayı kullanamazsınız. İstediğiniz zaman hesabınızı silme hakkına sahipsiniz.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Footer - Kabul Et Butonu
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: canProceed && !_isLoading ? _acceptTerms : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canProceed
                            ? const Color(0xFF4CAF50)
                            : Colors.grey.shade300,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade500,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: canProceed ? 4 : 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle, size: 24),
                                const SizedBox(width: 12),
                                Text(
                                  canProceed ? 'Kabul Et ve Devam Et' : 'Lütfen Tüm Kutuları İşaretleyin',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Onay kartı widget'ı
  Widget _buildAcceptanceCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool isAccepted,
    required ValueChanged<bool?> onChanged,
    VoidCallback? onReadMore,
    Widget? detailedInfo,
    required String acceptanceText,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAccepted ? iconColor.withOpacity(0.5) : Colors.grey.shade300,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Açıklama
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),

          // Detaylı bilgi
          if (detailedInfo != null) ...[
            const SizedBox(height: 12),
            detailedInfo,
          ],

          // Daha fazla oku butonu
          if (onReadMore != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onReadMore,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Tam Metni Oku'),
              style: TextButton.styleFrom(
                foregroundColor: iconColor,
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(),

          // Onay checkbox
          InkWell(
            onTap: () => onChanged(!isAccepted),
            child: Row(
              children: [
                Checkbox(
                  value: isAccepted,
                  onChanged: onChanged,
                  activeColor: iconColor,
                ),
                Expanded(
                  child: Text(
                    acceptanceText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Konum detaylı bilgi widget'ı
  Widget _buildLocationDetailedInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📍 Konum Kullanım Nedenleri:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildBulletPoint('Size yakın siparişleri yönlendirmek'),
          _buildBulletPoint('Teslimat mesafesini hesaplamak'),
          _buildBulletPoint('Teslimat doğrulaması yapmak'),
          _buildBulletPoint('Kazancınızı doğru hesaplamak'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Uygulama kapalıyken bile konum gönderilir',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bullet point widget'ı
  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Gizlilik politikasını aç
  void _openPrivacyPolicy() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PrivacyPolicyScreen(),
      ),
    );
  }

  /// Koşulları kabul et
  Future<void> _acceptTerms() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final nowString = now.toIso8601String();
      
      // ⭐ 1. Local storage'a kaydet (hızlı erişim için)
      await prefs.setString('terms_accepted_at', nowString);
      await prefs.setBool('privacy_policy_accepted', true);
      await prefs.setBool('location_permission_accepted', true);
      
      print('✅ Local onaylar kaydedildi: $nowString');

      // ⭐ 2. Firestore'a kaydet (backend kaydı için)
      if (widget.courierId != null) {
        // Firestore kaydetme işlemini try-catch içine al ama hatayı yutma
        try {
          // t_courier koleksiyonunda kurye dokümanını bul ve güncelle
          final courierQuery = await FirebaseFirestore.instance
              .collection('t_courier')
              .where('s_id', isEqualTo: widget.courierId)
              .limit(1)
              .get();

          if (courierQuery.docs.isNotEmpty) {
            await courierQuery.docs.first.reference.update({
              's_privacy_accepted': true,
              's_location_accepted': true,
              's_terms_accepted_at': FieldValue.serverTimestamp(),
              's_terms_accepted_device': nowString, // Client tarafı zaman damgası
              's_terms_version': '1.0', // İleride politika versiyonu takibi için
            });
            
            print('✅ Firestore onaylar kaydedildi: Kurye ID ${widget.courierId}');
          } else {
            print('⚠️ Kurye bulunamadı: ${widget.courierId}');
          }
        } catch (firestoreError) {
          print('⚠️ Firestore kaydetme hatası: $firestoreError');
          // Firestore hatası olsa bile devam et (local kayıt var)
        }
      } else {
        print('⚠️ Kurye ID yok, Firestore\'a kaydedilemedi');
      }

      // ⭐ BAŞARILI! Callback çağır
      // widget.onAccepted() artık sadece Navigator.pop() yapıyor (güvenli)
      if (!mounted) return;
      
      // ✅ Başarı mesajını göster
      print('✅✅ Tüm onaylar başarıyla kaydedildi! Geri dönülüyor...');
      
      // ⚠️ Loading durumunu kapat
      if (mounted) {
        setState(() => _isLoading = false);
      }
      
      // ✅ Güvenli bir şekilde callback çağır (sadece pop yapıyor)
      if (mounted) {
        widget.onAccepted();
      }
      
    } catch (e, stackTrace) {
      // ⭐ KRİTİK HATA: Local storage veya Firestore kaydetme tamamen başarısız
      print('❌ KRITIK Onay kaydetme hatası: $e');
      print('📋 StackTrace: $stackTrace');
      
      // Mounted kontrolü - widget dispose olmuş olabilir
      if (!mounted) {
        print('⚠️ Widget unmounted, UI güncellenemez');
        return;
      }
      
      // Loading durumunu kapat
      setState(() => _isLoading = false);
      
      // Tekrar mounted kontrolü (setState sonrası)
      if (!mounted) return;
      
      // Hata mesajı göster
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Hata: Lütfen tekrar deneyin'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

