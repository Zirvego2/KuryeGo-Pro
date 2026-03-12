import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'statistics_screen.dart';
import 'finance_screen.dart';
import 'reports_screen.dart';
import 'profile_screen.dart';
import '../services/firebase_service.dart';

/// 📱 Ana Profil Ekranı (3 Tab)
class MainProfileScreen extends StatefulWidget {
  final int courierId;
  final String courierName;
  final int bayId;

  const MainProfileScreen({
    super.key,
    required this.courierId,
    required this.courierName,
    required this.bayId,
  });

  @override
  State<MainProfileScreen> createState() => _MainProfileScreenState();
}

class _MainProfileScreenState extends State<MainProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // İstatistikler
  int _todayDeliveries = 0;
  double _todayEarnings = 0.0;
  double _todayDistance = 0.0;
  double _todayExtraKm = 0.0; // ⭐ EKSTRA KM
  String _shiftTime = '00:00 - 23:59';
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // ⭐ 3 → 4 (Raporlar eklendi)
    _loadDailyStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Vardiya saatini al
  Future<String> _getShiftTime() async {
    try {
      // Kurye bilgilerini al
      final courierQuery = await FirebaseFirestore.instance
          .collection('t_courier')
          .where('s_id', isEqualTo: widget.courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) return '00:00 - 23:59';

      final courierData = courierQuery.docs.first.data();
      final tShift = courierData['t_shift'];
      final courierBayId = courierData['s_bay'];

      if (tShift == null || courierBayId == null) return '00:00 - 23:59';

      // t_shift'i int'e çevir
      int shiftId;
      if (tShift is String) {
        shiftId = int.tryParse(tShift) ?? 0;
      } else if (tShift is int) {
        shiftId = tShift;
      } else {
        return '00:00 - 23:59';
      }

      // Vardiya bilgilerini al
      final shiftQuery = await FirebaseFirestore.instance
          .collection('t_shift')
          .where('s_id', isEqualTo: shiftId)
          .where('s_bay', isEqualTo: courierBayId)
          .limit(1)
          .get();

      if (shiftQuery.docs.isEmpty) return '00:00 - 23:59';

      final shiftData = shiftQuery.docs.first.data();
      final sShifts = shiftData['s_shifts'];

      if (sShifts == null) return '00:00 - 23:59';

      // Bugünün gününü al
      final weekdayMap = {
        1: 'ss_pazartesi',
        2: 'ss_sali',
        3: 'ss_carsamba',
        4: 'ss_persembe',
        5: 'ss_cuma',
        6: 'ss_cumartesi',
        7: 'ss_pazar',
      };

      final today = DateTime.now().weekday;
      final todayKey = weekdayMap[today];

      if (todayKey == null) return '00:00 - 23:59';

      final todayShift = sShifts[todayKey];
      if (todayShift is List && todayShift.length >= 2) {
        final startTime = todayShift[0]?.toString() ?? '00:00';
        final endTime = todayShift[1]?.toString() ?? '23:59';
        return '$startTime - $endTime';
      }

      return '00:00 - 23:59';
    } catch (e) {
      print('❌ Vardiya saati yükleme hatası: $e');
      return '00:00 - 23:59';
    }
  }

  /// ⭐ YENİ SİSTEM: t_courier.s_pricing ile hesaplama
  /// Index: s_courier + s_stat + s_ddate
  Future<void> _loadDailyStats() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      print('📊 Günlük istatistik sorgusu başlatılıyor...');
      print('   Kurye ID: ${widget.courierId}');
      print('   Bugün başlangıç: $todayStart');

      // ⭐ 1. Kurye ücretlendirme bilgisini çek (t_courier.s_pricing)
      final pricing = await FirebaseService.getCourierPricingFromCourier(widget.courierId);
      if (pricing == null) {
        print('❌ Kurye ücretlendirme bilgisi yüklenemedi!');
        setState(() => _isLoadingStats = false);
        return;
      }

      final fixedFee = pricing['s_fixed_fee'] as double;
      final minKm = pricing['s_min_km'] as double;
      final perKmFee = pricing['s_per_km_fee'] as double;

      print('   ✅ Ücretlendirme bilgisi:');
      print('      Sabit Ücret: ${fixedFee.toStringAsFixed(2)}₺');
      print('      Minimum KM: ${minKm.toStringAsFixed(2)} km');
      print('      KM Başı Ücret: ${perKmFee.toStringAsFixed(2)}₺/km');

      // ⭐ 2. Bugünkü teslim edilenler (s_ddate filtresi ile)
      final todayQueryByDdate = await FirebaseFirestore.instance
          .collection('t_orders')
          .where('s_courier', isEqualTo: widget.courierId)
          .where('s_stat', isEqualTo: 2)
          .where('s_ddate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .get();

      print('   📦 Bugün teslim edilen sipariş: ${todayQueryByDdate.docs.length}');

      // ⭐ Bugün teslim edilenleri kullan
      int deliveries = todayQueryByDdate.docs.length;
      double earnings = 0.0;
      double totalDistance = 0.0;
      double totalExtraKm = 0.0; // ⭐ EKSTRA KM TOPLAMI

      print('   💰 Kazanç hesaplaması başlatılıyor...');
      
      int orderIndex = 0;
      for (var doc in todayQueryByDdate.docs) {
        orderIndex++;
        final data = doc.data();
        final orderId = data['s_pid'] ?? data['s_id']?.toString() ?? 'N/A';
        
        print('      🔹 Sipariş #$orderIndex (ID: $orderId):');
        
        // ⭐ MESAFE (s_dinstance STRING olabilir!)
        final distanceRaw = data['s_dinstance'];
        double distance = 0.0;
        
        if (distanceRaw is String) {
          distance = double.tryParse(distanceRaw) ?? 0.0;
        } else if (distanceRaw is num) {
          distance = distanceRaw.toDouble();
        }
        
        print('         Mesafe: ${distance.toStringAsFixed(2)} km');
        
        // ⭐ YENİ HESAPLAMA MANTIĞI:
        // Kazanç = Sabit Ücret + (Mesafe > MinKM ? (Mesafe - MinKM) × KM Başı Ücret : 0)
        
        double orderEarnings = fixedFee; // Başlangıç: Sabit ücret
        double extraKm = 0.0;
        
        // Ekstra KM hesaplama
        if (distance > 0 && minKm > 0 && distance > minKm) {
          extraKm = distance - minKm;
          final extraKmEarnings = extraKm * perKmFee;
          orderEarnings += extraKmEarnings;
          
          print('         ✅ EKSTRA KM: ${extraKm.toStringAsFixed(2)} km (${distance.toStringAsFixed(2)} - ${minKm.toStringAsFixed(2)})');
          print('         ✅ Ekstra Ücret: ${extraKm.toStringAsFixed(2)} × ${perKmFee.toStringAsFixed(2)}₺ = ${extraKmEarnings.toStringAsFixed(2)}₺');
        } else if (minKm == 0) {
          print('         ⚠️ MinKM tanımlı değil!');
        } else {
          print('         ℹ️ Mesafe MinKM içinde (${distance.toStringAsFixed(2)} ≤ ${minKm.toStringAsFixed(2)} km) - Sadece sabit ücret');
        }
        
        print('         💵 TOPLAM Kazanç: ${orderEarnings.toStringAsFixed(2)}₺ (Sabit: ${fixedFee.toStringAsFixed(2)}₺ + Ekstra: ${(orderEarnings - fixedFee).toStringAsFixed(2)}₺)');
        
        earnings += orderEarnings;
        totalDistance += distance;
        totalExtraKm += extraKm;
      }
      
      print('   ════════════════════════════════════');
      print('   📊 GENEL TOPLAM:');
      print('      📦 Sipariş: $deliveries');
      print('      💰 Kazanç: ${earnings.toStringAsFixed(2)}₺');
      print('      🛣️ Toplam Mesafe: ${totalDistance.toStringAsFixed(1)} km');
      print('      ⚡ EKSTRA KM: ${totalExtraKm.toStringAsFixed(1)} km');
      print('   ════════════════════════════════════');

      // Vardiya saatini al
      String shiftTime = await _getShiftTime();

      print('   ✅ İstatistikler hazır:');
      print('      📦 Paket: $deliveries');
      print('      💰 Kazanç: ₺${earnings.toStringAsFixed(2)}');
      print('      🛣️ Toplam Mesafe: ${totalDistance.toStringAsFixed(1)} km');
      print('      ⚡ EKSTRA KM: ${totalExtraKm.toStringAsFixed(1)} km');
      print('      ⏰ Vardiya: $shiftTime');

      setState(() {
        _todayDeliveries = deliveries;
        _todayEarnings = earnings;
        _todayDistance = totalDistance;
        _todayExtraKm = totalExtraKm; // ⭐ EKSTRA KM
        _shiftTime = shiftTime;
        _isLoadingStats = false;
      });

      print('   🎨 UI güncellendi!');
    } catch (e) {
      print('❌ Günlük istatistik yükleme hatası: $e');
      print('   Stack trace: ${StackTrace.current}');
      setState(() => _isLoadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profil',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Profil kartı
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                // Avatar ve isim
                Row(
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2196F3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 40),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.courierName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          // ⭐ Vardiya saati geçici olarak yorum satırına alındı
                          // const SizedBox(height: 4),
                          // Container(
                          //   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          //   decoration: BoxDecoration(
                          //     color: const Color(0xFF4CAF50).withOpacity(0.1),
                          //     borderRadius: BorderRadius.circular(8),
                          //   ),
                          //   child: Text(
                          //     '⏰ Vardiya Saatiniz: $_shiftTime',
                          //     style: const TextStyle(
                          //       fontSize: 12,
                          //       fontWeight: FontWeight.w600,
                          //       color: Color(0xFF4CAF50),
                          //     ),
                          //   ),
                          // ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // İstatistikler (Günlük)
                _isLoadingStats
                    ? const SizedBox(
                        height: 60,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            _todayDeliveries.toString(),
                            'Paket',
                            Icons.local_shipping,
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey[300],
                          ),
                          _buildStatItem(
                            '₺${_todayEarnings.toStringAsFixed(2)}',
                            'Kazanç',
                            Icons.account_balance_wallet,
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey[300],
                          ),
                          _buildStatItem(
                            _todayExtraKm.toStringAsFixed(2),
                            'Ekstra KM',
                            Icons.local_fire_department, // ⭐ Farklı icon
                          ),
                        ],
                      ),
              ],
            ),
          ),

          // Tab bar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF2196F3),
              indicatorWeight: 3,
              labelColor: const Color(0xFF2196F3),
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.assessment, size: 20), text: 'Paketler'),
                Tab(icon: Icon(Icons.account_balance_wallet, size: 20), text: 'Mutabakat'),
                Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'Raporlar'),
                Tab(icon: Icon(Icons.settings, size: 20), text: 'Ayarlar'),
              ],
            ),
          ),

          // Tab view
          Expanded(
            child: Container(
              color: const Color(0xFFF5F5F5),
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 1️⃣ İstatistikler & Performans
                  StatisticsScreen(
                    courierId: widget.courierId,
                    courierName: widget.courierName,
                  ),

                  // 2️⃣ Finans & Mutabakat
                  FinanceScreen(
                    courierId: widget.courierId,
                    courierName: widget.courierName,
                    bayId: widget.bayId, // ⭐ Bay ID eklendi
                  ),

                  // 3️⃣ Raporlar
                  ReportsScreen(
                    courierId: widget.courierId,
                    courierName: widget.courierName,
                  ),

                  // 4️⃣ Profil & Ayarlar
                  ProfileScreen(
                    courierId: widget.courierId,
                    courierName: widget.courierName,
                    bayId: widget.bayId,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// İstatistik item widget
  Widget _buildStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}


