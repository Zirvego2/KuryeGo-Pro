import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../widgets/shift_menu_sheet.dart';
import '../services/shift_service.dart';
import 'login_screen.dart';
import 'payment_changes_screen.dart';
import 'settings_screen.dart';
import 'cash_on_hand_screen.dart';
import 'leave_plan_screen.dart';
import 'my_external_orders_screen.dart';
import 'my_external_orders_report_screen.dart';
import 'courier_penalty_reward_screen.dart';

/// 👤 Profil & Ayarlar Ekranı
class ProfileScreen extends StatefulWidget {
  final int courierId;
  final String courierName;
  final int bayId;

  const ProfileScreen({
    super.key,
    required this.courierId,
    required this.courierName,
    required this.bayId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  bool _locationSharing = true;
  bool _pushNotifications = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _autoRouteEnabled = true; // Rota özelliği aktif mi?

  // Kullanıcı bilgileri
  String _phone = '';
  String _email = '';
  String _iban = '';
  String _plaka = '';
  String _vehicleModel = '';
  int _courierStatus = 1;

  // Haftalık vardiya bilgileri
  Map<String, dynamic>? _weeklyShift;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _loadRouteSetting();
  }
  
  /// Rota özelliği ayarını yükle
  Future<void> _loadRouteSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _autoRouteEnabled = prefs.getBool('auto_route_enabled') ?? true; // Default: true
      });
    } catch (e) {
      print('❌ Rota ayarı yüklenemedi: $e');
    }
  }
  
  /// Rota özelliği ayarını kaydet
  Future<void> _saveRouteSetting(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_route_enabled', value);
      setState(() {
        _autoRouteEnabled = value;
      });
      print('✅ Rota özelliği ${value ? "açıldı" : "kapatıldı"}');
    } catch (e) {
      print('❌ Rota ayarı kaydedilemedi: $e');
    }
  }

  /// Profil verilerini yükle
  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);

    try {
      // Firestore'dan kurye bilgilerini çek
      final courierDoc = await FirebaseFirestore.instance
          .collection('t_courier')
          .where('s_id', isEqualTo: widget.courierId)
          .limit(1)
          .get();

      if (courierDoc.docs.isNotEmpty) {
        final data = courierDoc.docs.first.data();
        final tShift = data['t_shift'];
        final courierBayId = data['s_bay'];

        setState(() {
          _phone = data['s_phone'] ?? '';
          _email = data['s_email'] ?? '';
          _iban = data['s_info']?['ss_iban'] ?? '';
          _plaka = data['s_info']?['ss_plaka'] ?? '';
          _vehicleModel = data['s_info']?['ss_vehicle_model'] ?? 'Motosiklet';
          _courierStatus = data['s_stat'] ?? 1;
        });

        // Vardiya bilgilerini çek
        if (tShift != null && courierBayId != null) {
          await _loadShiftData(tShift, courierBayId);
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('❌ Profil veri yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Vardiya bilgilerini yükle
  Future<void> _loadShiftData(dynamic tShift, int bayId) async {
    try {
      // t_shift String veya int olabilir
      int? shiftId;
      if (tShift is String) {
        shiftId = int.tryParse(tShift);
      } else if (tShift is int) {
        shiftId = tShift;
      }

      if (shiftId == null) return;

      // t_shift koleksiyonundan vardiya bilgilerini çek
      final shiftQuery = await FirebaseFirestore.instance
          .collection('t_shift')
          .where('s_bay', isEqualTo: bayId)
          .where('s_id', isEqualTo: shiftId)
          .limit(1)
          .get();

      if (shiftQuery.docs.isNotEmpty) {
        final shiftData = shiftQuery.docs.first.data();
        setState(() {
          _weeklyShift = shiftData['s_shifts'];
        });
        print('✅ Haftalık vardiya yüklendi');
      }
    } catch (e) {
      print('❌ Vardiya bilgisi yükleme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Haftalık vardiya butonu
                  _buildSectionTitle('📅 Vardiya Bilgilerim'),
                  _buildActionButton(
                    'Haftalık Vardiyam',
                    Icons.calendar_month,
                    const Color(0xFF673AB7),
                    _showWeeklyShiftDialog,
                  ),
                  const SizedBox(height: 10),
                  _buildActionButton(
                    'İzin Günüm',
                    Icons.beach_access,
                    const Color(0xFF00BCD4),
                    _openLeavePlan,
                  ),

                  const SizedBox(height: 20),

                  // Ödeme değişiklikleri
                  _buildSectionTitle('💳 Ödeme İşlemleri'),
                  _buildActionButton(
                    'Ödeme Değişikliklerim',
                    Icons.swap_horiz,
                    const Color(0xFFFF9800),
                    _openPaymentChanges,
                  ),
                  const SizedBox(height: 10),
                  _buildActionButton(
                    'Üzerimdeki Nakit',
                    Icons.money,
                    const Color(0xFF4CAF50),
                    _openCashOnHand,
                  ),

                  const SizedBox(height: 20),

                  // Sistem Dışı İşlemler
                  _buildSectionTitle('📦 Sistem Dışı İşlemler'),
                  _buildActionButton(
                    'Sistem Dışı Siparişlerim',
                    Icons.assignment_outlined,
                    const Color(0xFF2563EB),
                    _openExternalOrders,
                  ),
                  const SizedBox(height: 10),
                  _buildActionButton(
                    'Sistem Dışı Sipariş Raporlarım',
                    Icons.bar_chart_rounded,
                    const Color(0xFF7C3AED),
                    _openExternalOrdersReport,
                  ),

                  const SizedBox(height: 20),

                  // Ödül & Ceza (profil / Ayarlar sekmesinde doğrudan görünsün)
                  _buildSectionTitle('🏅 Ödül & Ceza'),
                  _buildActionButton(
                    'Ödül ve ceza kayıtlarım',
                    Icons.account_balance,
                    const Color(0xFF5E35B1),
                    _openPenaltyReward,
                  ),

                  const SizedBox(height: 20),

                  // Özellikler
                  _buildSectionTitle('⚙️ Özellikler'),
                  _buildSwitchTileWithSubtitle(
                    'Otomatik Rota Özelliği',
                    'Teslim alınmış siparişler için otomatik rota oluşturma',
                    _autoRouteEnabled,
                    Icons.tune,
                    (value) {
                      _saveRouteSetting(value);
                    },
                  ),

                  const SizedBox(height: 20),

                  // Kişisel bilgiler (buton)
                  _buildSectionTitle('👤 Kişisel Bilgiler'),
                  _buildActionButton(
                    'Kişisel Bilgilerim',
                    Icons.person,
                    const Color(0xFF2196F3),
                    _showPersonalInfoSheet,
                  ),

                  const SizedBox(height: 20),

                  // Bildirim ayarları (buton)
                  _buildSectionTitle('🔔 Bildirim Ayarları'),
                  _buildActionButton(
                    'Bildirim Ayarlarım',
                    Icons.notifications,
                    Colors.orange,
                    _showNotificationSettingsSheet,
                  ),

                  const SizedBox(height: 20),

                  // Konum & Gizlilik (buton)
                  _buildSectionTitle('📍 Konum & Gizlilik'),
                  _buildActionButton(
                    'Konum & Gizlilik Ayarlarım',
                    Icons.location_on,
                    Colors.green,
                    _showLocationPrivacySheet,
                  ),

                  const SizedBox(height: 20),

                  // Ayarlar
                  _buildSectionTitle('⚙️ Uygulama'),
                  _buildActionButton(
                    'Ayarlar & Gizlilik',
                    Icons.settings,
                    const Color(0xFF673AB7),
                    _openSettings,
                  ),

                  const SizedBox(height: 20),

                  // Acil durum
                  _buildSectionTitle('🆘 Acil Durum'),
                  _buildActionButton(
                    'Acil Durum Bildirimi',
                    Icons.emergency,
                    Colors.red,
                    _showEmergencyDialog,
                  ),

                  const SizedBox(height: 20),

                  // Çıkış
                  _buildLogoutButton(),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  /// Haftalık vardiya içeriği (BottomSheet için)
  Widget _buildWeeklyShiftContent() {
    if (_weeklyShift == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            '⏰ Vardiya bilgisi yükleniyor...',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // Gün isimleri
    final dayNames = {
      'ss_pazartesi': 'Pazartesi',
      'ss_sali': 'Salı',
      'ss_carsamba': 'Çarşamba',
      'ss_persembe': 'Perşembe',
      'ss_cuma': 'Cuma',
      'ss_cumartesi': 'Cumartesi',
      'ss_pazar': 'Pazar',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: dayNames.entries.map((entry) {
        final dayKey = entry.key;
        final dayName = entry.value;
        final shiftTimes = _weeklyShift![dayKey];
        
        if (shiftTimes is List && shiftTimes.length >= 2) {
          final startTime = shiftTimes[0] ?? '00:00';
          final endTime = shiftTimes[1] ?? '00:00';
          
          // 00:00 - 00:00 ise boş gün
          final isEmpty = startTime == '00:00' && endTime == '00:00';
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isEmpty 
                  ? Colors.grey.shade100
                  : const Color(0xFF673AB7).withOpacity(0.1),
              border: Border.all(
                color: isEmpty 
                    ? Colors.grey.shade300
                    : const Color(0xFF673AB7).withOpacity(0.3),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isEmpty ? Colors.grey : const Color(0xFF673AB7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isEmpty ? Colors.grey.shade600 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isEmpty ? 'Çalışma Yok' : '$startTime - $endTime',
                        style: TextStyle(
                          fontSize: 14,
                          color: isEmpty ? Colors.grey.shade500 : const Color(0xFF673AB7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isEmpty ? Icons.cancel_outlined : Icons.check_circle,
                  color: isEmpty ? Colors.grey : Colors.green,
                  size: 28,
                ),
              ],
            ),
          );
        }
        
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  Color _getStatusColor() {
    switch (_courierStatus) {
      case 0: return Colors.grey;
      case 1: return Colors.green;
      case 2: return Colors.orange;
      case 3: return Colors.blue;
      case 4: return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusText() {
    switch (_courierStatus) {
      case 0: return 'ÇALIŞMIYOR';
      case 1: return 'MÜSAİT';
      case 2: return 'MEŞGUL';
      case 3: return 'MOLA';
      case 4: return 'KAZA';
      default: return 'BİLİNMİYOR';
    }
  }

  /// Bölüm başlığı
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  /// Bilgi kartı
  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF2196F3), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
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

  /// Switch tile
  Widget _buildSwitchTile(String label, bool value, IconData icon, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF2196F3), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF4CAF50),
          ),
        ],
      ),
    );
  }

  /// Switch tile with subtitle
  Widget _buildSwitchTileWithSubtitle(
    String label,
    String subtitle,
    bool value,
    IconData icon,
    Function(bool) onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF2196F3), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF4CAF50),
          ),
        ],
      ),
    );
  }

  /// Aksiyon butonu
  Widget _buildActionButton(String label, IconData? icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  /// Çıkış butonu
  Widget _buildLogoutButton() {
    return GestureDetector(
      onTap: _logout,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF44336), Color(0xFFD32F2F)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF44336).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.logout, color: Colors.white, size: 22),
            SizedBox(width: 12),
            Text(
              'Çıkış Yap',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vardiya menüsünü göster
  void _showShiftMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ShiftMenuSheet(
        courierId: widget.courierId,
        bayId: widget.bayId,
        currentStatus: _courierStatus,
        onStatusChanged: (newStatus) {
          setState(() {
            _courierStatus = newStatus;
          });
        },
      ),
    );
  }

  /// Ödeme değişiklikleri sayfasını aç
  void _openPaymentChanges() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentChangesScreen(
          courierId: widget.courierId,
          courierName: widget.courierName,
        ),
      ),
    );
  }

  /// Üzerimdeki Nakit sayfasını aç
  void _openCashOnHand() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashOnHandScreen(
          courierId: widget.courierId,
          bayId: widget.bayId,
        ),
      ),
    );
  }

  /// İzin Günüm sayfasını aç
  void _openLeavePlan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeavePlanScreen(
          courierId: widget.courierId,
          bayId: widget.bayId,
        ),
      ),
    );
  }

  /// Ayarlar sayfasını aç
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          courierId: widget.courierId,
          courierName: widget.courierName,
          bayId: widget.bayId,
        ),
      ),
    );
  }

  /// Ödül & ceza kayıtları (panelden girilen)
  void _openPenaltyReward() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourierPenaltyRewardScreen(
          courierId: widget.courierId,
          bayId: widget.bayId,
        ),
      ),
    );
  }

  /// Sistem Dışı Siparişlerim sayfasını aç
  void _openExternalOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyExternalOrdersScreen(
          courierId: widget.courierId,
          bayId: widget.bayId,
        ),
      ),
    );
  }

  /// Sistem Dışı Sipariş Raporlarım sayfasını aç
  void _openExternalOrdersReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyExternalOrdersReportScreen(
          courierId: widget.courierId,
          bayId: widget.bayId,
        ),
      ),
    );
  }

  /// Haftalık vardiya dialog'unu göster
  void _showWeeklyShiftDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Kapatma handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Başlık
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF673AB7), Color(0xFF512DA8)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.calendar_month,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '📅 Haftalık Vardiyam',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Vardiya listesi
            Expanded(
              child: _weeklyShift == null
                  ? const Center(
                      child: Text(
                        '⏰ Vardiya bilgisi yükleniyor...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _buildWeeklyShiftContent(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Acil durum dialogu
  void _showEmergencyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🆘 Acil Durum'),
        content: const Text(
          'Acil durum bildirimi göndermek istediğinizden emin misiniz?\n\nYöneticiniz ve yakın kuryeler bilgilendirilecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Acil durum bildirimi gönder
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🆘 Acil durum bildirimi gönderildi!'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
  }

  /// Kişisel bilgiler bottom sheet'ini göster
  void _showPersonalInfoSheet() {
    // İçerik elemanlarının sayısını hesapla
    int itemCount = 3; // Telefon, E-posta, IBAN (her zaman var)
    if (_plaka.isNotEmpty) itemCount++;
    if (_vehicleModel.isNotEmpty) itemCount++;
    
    // Dinamik yükseklik hesapla: Header (~100px) + İçerik (~80px/item) + Padding (~40px)
    final headerHeight = 12 + 20 + 20 + 24 + 20 + 1; // handle + padding + başlık + divider
    final itemHeight = 80.0; // Her bilgi kartı yaklaşık yüksekliği
    final padding = 40.0; // Top + bottom padding
    final calculatedHeight = headerHeight + (itemCount * itemHeight) + padding;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9; // Maksimum %90 ekran
    final minHeight = 300.0; // Minimum 300px
    final finalHeight = calculatedHeight.clamp(minHeight, maxHeight);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: finalHeight,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kapatma handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Başlık
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Color(0xFF2196F3),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '👤 Kişisel Bilgiler',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Kişisel bilgiler içeriği
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInfoCard('Telefon', _phone.isNotEmpty ? _phone : 'Belirtilmemiş', Icons.phone),
                    const SizedBox(height: 12),
                    _buildInfoCard('E-posta', _email.isNotEmpty ? _email : 'Belirtilmemiş', Icons.email),
                    const SizedBox(height: 12),
                    _buildInfoCard('IBAN', _iban.isNotEmpty ? _iban : 'Belirtilmemiş', Icons.account_balance),
                    if (_plaka.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoCard('Plaka', _plaka, Icons.directions_car),
                    ],
                    if (_vehicleModel.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoCard('Araç Modeli', _vehicleModel, Icons.two_wheeler),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bildirim ayarları bottom sheet'ini göster
  void _showNotificationSettingsSheet() {
    // İçerik elemanlarının sayısını hesapla (3 switch)
    const int itemCount = 3;
    
    // Dinamik yükseklik hesapla: Header (~100px) + İçerik (~80px/item) + Padding (~40px)
    const headerHeight = 12 + 20 + 20 + 24 + 20 + 1; // handle + padding + başlık + divider
    const itemHeight = 80.0; // Her switch yaklaşık yüksekliği
    const padding = 40.0; // Top + bottom padding
    final calculatedHeight = headerHeight + (itemCount * itemHeight) + padding;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9; // Maksimum %90 ekran
    const minHeight = 300.0; // Minimum 300px
    final finalHeight = calculatedHeight.clamp(minHeight, maxHeight);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: finalHeight,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kapatma handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Başlık
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications,
                      color: Colors.orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '🔔 Bildirim Ayarları',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Bildirim ayarları içeriği
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSwitchTile(
                      'Push Bildirimleri',
                      _pushNotifications,
                      Icons.notifications,
                      (value) {
                        setState(() => _pushNotifications = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSwitchTile(
                      'Ses',
                      _soundEnabled,
                      Icons.volume_up,
                      (value) {
                        setState(() => _soundEnabled = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSwitchTile(
                      'Titreşim',
                      _vibrationEnabled,
                      Icons.vibration,
                      (value) {
                        setState(() => _vibrationEnabled = value);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Konum & Gizlilik bottom sheet'ini göster
  void _showLocationPrivacySheet() {
    // İçerik elemanlarının sayısını hesapla (1 switch)
    const int itemCount = 1;
    
    // Dinamik yükseklik hesapla: Header (~100px) + İçerik (~80px/item) + Padding (~40px)
    const headerHeight = 12 + 20 + 20 + 24 + 20 + 1; // handle + padding + başlık + divider
    const itemHeight = 80.0; // Her switch yaklaşık yüksekliği
    const padding = 40.0; // Top + bottom padding
    final calculatedHeight = headerHeight + (itemCount * itemHeight) + padding;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9; // Maksimum %90 ekran
    const minHeight = 250.0; // Minimum 250px (az içerik)
    final finalHeight = calculatedHeight.clamp(minHeight, maxHeight);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: finalHeight,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kapatma handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Başlık
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '📍 Konum & Gizlilik',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Konum & Gizlilik ayarları içeriği
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSwitchTile(
                      'Konum Paylaşımı',
                      _locationSharing,
                      Icons.location_on,
                      (value) {
                        setState(() => _locationSharing = value);
                        if (!value) {
                          LocationService.stopService();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Çıkış yap
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Çıkış yapmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Background service durdur
      await LocationService.stopService();

      // Local storage temizle
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}

