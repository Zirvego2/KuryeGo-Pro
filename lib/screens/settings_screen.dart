import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'privacy_policy_screen.dart';
import 'login_screen.dart';
import 'courier_penalty_reward_screen.dart';

/// ⚙️ Ayarlar Ekranı
/// Google Play & Apple Store Onayı için ZORUNLU özellikler:
/// - Gizlilik Politikası
/// - Sürüm Bilgisi
/// - Hesap Silme
/// - Konum Kullanım Açıklaması
class SettingsScreen extends StatefulWidget {
  final int courierId;
  final String courierName;
  final int bayId;

  const SettingsScreen({
    super.key,
    required this.courierId,
    required this.courierName,
    required this.bayId,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  /// Uygulama sürüm bilgisini yükle
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Sürüm bilgisi yüklenemedi: $e');
      setState(() {
        _appVersion = '1.0.0 (1)';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        toolbarHeight: 48,
        title: const Text(
          '⚙️ Ayarlar',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black, size: 22),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gizlilik & Güvenlik
                  _buildSectionTitle('🔒 Gizlilik & Güvenlik'),
                  const SizedBox(height: 8),
                  _buildSettingTile(
                    icon: Icons.privacy_tip,
                    title: 'Gizlilik Politikası',
                    subtitle: 'Verilerinizin nasıl kullanıldığını öğrenin',
                    iconColor: Colors.blue,
                    onTap: _openPrivacyPolicy,
                  ),
                  const SizedBox(height: 8),
                  _buildSettingTile(
                    icon: Icons.location_on,
                    title: 'Konum Kullanımı',
                    subtitle: 'Arka planda konum toplama hakkında',
                    iconColor: Colors.green,
                    onTap: _showLocationUsageDialog,
                  ),
                  const SizedBox(height: 8),
                  _buildSettingTile(
                    icon: Icons.delete_forever,
                    title: 'Hesabımı Sil',
                    subtitle: 'Tüm verilerinizi kalıcı olarak silin',
                    iconColor: Colors.red,
                    onTap: _showDeleteAccountDialog,
                  ),

                  const SizedBox(height: 20),

                  // Uygulama Bilgisi (Kişisel Bilgiler)
                  _buildSectionTitle('ℹ️ Kişisel Bilgiler'),
                  const SizedBox(height: 8),
                  _buildInfoCard(
                    icon: Icons.info,
                    title: 'Sürüm',
                    value: _appVersion,
                    iconColor: Colors.purple,
                  ),
                  const SizedBox(height: 8),
                  _buildInfoCard(
                    icon: Icons.person,
                    title: 'Kullanıcı Adı',
                    value: widget.courierName,
                    iconColor: Colors.orange,
                  ),
                  const SizedBox(height: 8),
                  _buildInfoCard(
                    icon: Icons.badge,
                    title: 'Kurye ID',
                    value: '#${widget.courierId}',
                    iconColor: Colors.teal,
                  ),

                  const SizedBox(height: 20),

                  _buildSectionTitle('🏅 Ödül & Ceza'),
                  const SizedBox(height: 8),
                  _buildSettingTile(
                    icon: Icons.account_balance,
                    title: 'Ödül ve ceza kayıtlarım',
                    subtitle:
                        'Size tanımlanan paket ödülleri ve cezaları görüntüleyin',
                    iconColor: Colors.deepPurple,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CourierPenaltyRewardScreen(
                            courierId: widget.courierId,
                            bayId: widget.bayId,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Destek
                  _buildSectionTitle('💬 Destek'),
                  const SizedBox(height: 8),
                  _buildSettingTile(
                    icon: Icons.help_outline,
                    title: 'Yardım & Destek',
                    subtitle: 'Sık sorulan sorular ve destek',
                    iconColor: Colors.indigo,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('📞 Destek için: support@zirvego.com'),
                          backgroundColor: Colors.indigo,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  /// Bölüm başlığı
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  /// Ayar kartı
  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  /// Switch tile (toggle switch ile)
  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.88,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: iconColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Bilgi kartı
  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Gizlilik Politikası Sayfasını Aç
  void _openPrivacyPolicy() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PrivacyPolicyScreen(),
      ),
    );
  }

  /// Konum Kullanımı Açıklama Dialogu
  void _showLocationUsageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.green),
            SizedBox(width: 8),
            Text('📍 Konum Kullanımı'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ZirveGo, aşağıdaki amaçlar için konumunuzu kullanır:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('✅ Size yakın siparişleri yönlendirmek'),
              SizedBox(height: 8),
              Text('✅ Teslimat mesafesini hesaplamak'),
              SizedBox(height: 8),
              Text('✅ Teslimatı doğrulamak'),
              SizedBox(height: 8),
              Text('✅ Rota takibi yapmak'),
              SizedBox(height: 16),
              Text(
                'Arka Plan Konum:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Uygulama kapalıyken bile konum gönderilir. Bu özellik teslimat doğruluğu için gereklidir.',
              ),
              SizedBox(height: 16),
              Text(
                '🔒 Verileriniz güvenli bir şekilde saklanır ve üçüncü taraflarla paylaşılmaz.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }

  /// Hesap Silme Dialogu
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('⚠️ Hesabı Sil'),
          ],
        ),
        content: const Text(
          'Hesabınızı silmek istediğinizden emin misiniz?\n\n'
          '⚠️ Bu işlem GERİ ALINAMAZ!\n\n'
          'Tüm verileriniz kalıcı olarak silinecek:\n'
          '• Profil bilgileriniz\n'
          '• Teslimat geçmişiniz\n'
          '• Kazanç bilgileriniz\n\n'
          'İşlemi onaylamak için "SİL" butonuna basın.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDeleteAccount();
            },
            child: const Text(
              'SİL',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Hesap Silme Onayı
  Future<void> _confirmDeleteAccount() async {
    // İkinci onay
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔴 SON ONAY'),
        content: const Text(
          'Hesabınızı kalıcı olarak silmek için tekrar onaylayın.\n\n'
          'Bu işlem 24 saat içinde tamamlanacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('KALICI OLARAK SİL'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  /// Hesap Silme API İsteği
  Future<void> _deleteAccount() async {
    try {
      // Loading göster
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Firestore'da kurye hesabını pasif yap (soft delete)
      final courierQuery = await FirebaseFirestore.instance
          .collection('t_courier')
          .where('s_id', isEqualTo: widget.courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isNotEmpty) {
        await courierQuery.docs.first.reference.update({
          's_stat': 0, // Çalışmıyor
          's_deleted': true,
          's_deleted_at': FieldValue.serverTimestamp(),
          's_delete_reason': 'Kullanıcı kendi isteğiyle hesabı sildi',
        });
      }

      // Local storage temizle
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        Navigator.pop(context); // Loading kapat
        
        // Başarı mesajı
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Hesap silme isteğiniz alındı. 24 saat içinde silinecek.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );

        // Login ekranına yönlendir
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      print('❌ Hesap silme hatası: $e');
      
      if (mounted) {
        Navigator.pop(context); // Loading kapat
        
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

