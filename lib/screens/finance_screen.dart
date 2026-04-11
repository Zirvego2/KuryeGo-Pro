import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/firebase_service.dart';
import '../utils/restaurant_pricing_fee.dart';

/// 💰 Finans & Mutabakat Ekranı (YENİ VERSİYON)
class FinanceScreen extends StatefulWidget {
  final int courierId;
  final String courierName;
  final int bayId;

  const FinanceScreen({
    super.key,
    required this.courierId,
    required this.courierName,
    required this.bayId,
  });

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  bool _isLoading = true;
  
  // Tarih ve saat seçimi
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 59);
  
  // Finansal veriler
  int _packageCount = 0;
  double _totalEarnings = 0.0;
  double _totalExtraKm = 0.0;
  double _totalCash = 0.0;
  double _totalCard = 0.0;
  double _totalOnline = 0.0;
  
  // Restoran bazlı sipariş sayıları
  Map<String, int> _restaurantOrderCounts = {};

  /// UI: Kazanç özeti restoran bazlı ücretlendirmeye göre mi hesaplandı
  bool _restaurantPricingEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadFinanceData();
  }

  /// Finansal verileri yükle
  Future<void> _loadFinanceData() async {
    setState(() => _isLoading = true);

    try {
      // Başlangıç ve bitiş DateTime'ı oluştur
      final startDateTime = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        _startTime.hour,
        _startTime.minute,
      );
      
      final endDateTime = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        _endTime.hour,
        _endTime.minute,
      );

      print('💰 Finans verileri yükleniyor...');
      print('   Başlangıç: $startDateTime');
      print('   Bitiş: $endDateTime');

      final restaurantMode =
          await FirebaseService.isRestaurantPricingEnabled(widget.bayId);

      Map<String, dynamic>? courierPricing;
      Map<int, RestaurantWorkPricing> restaurantPricingMap = {};

      if (restaurantMode) {
        restaurantPricingMap = await FirebaseService.getActiveRestaurantPricingByCourier(
          widget.bayId,
          widget.courierId,
        );
      } else {
        courierPricing = await FirebaseService.getCourierPricingFromCourier(widget.courierId);
        if (courierPricing == null) {
          print('❌ Kurye ücretlendirme bilgisi yüklenemedi!');
          setState(() {
            _isLoading = false;
            _restaurantPricingEnabled = restaurantMode;
          });
          return;
        }

        final fixedFee = courierPricing['s_fixed_fee'] as double;
        final minKm = courierPricing['s_min_km'] as double;
        final perKmFee = courierPricing['s_per_km_fee'] as double;

        print('   ✅ Ücretlendirme bilgisi (s_pricing):');
        print('      Sabit Ücret: ${fixedFee.toStringAsFixed(2)}₺');
        print('      Minimum KM: ${minKm.toStringAsFixed(2)} km');
        print('      KM Başı Ücret: ${perKmFee.toStringAsFixed(2)}₺/km');
      }

      // ⭐ Siparişleri çek - TESLİM TARİHİNE GÖRE (s_ddate)
      // Index: s_courier + s_stat + s_ddate ✅
      final ordersQuery = await FirebaseFirestore.instance
          .collection('t_orders')
          .where('s_courier', isEqualTo: widget.courierId)
          .where('s_stat', isEqualTo: 2)
          .where('s_ddate', isGreaterThanOrEqualTo: Timestamp.fromDate(startDateTime))
          .where('s_ddate', isLessThanOrEqualTo: Timestamp.fromDate(endDateTime))
          .get();

      int count = 0;
      double cash = 0.0;
      double card = 0.0;
      double online = 0.0;
      double earnings = 0.0;
      double extraKmSum = 0.0;
      Map<String, int> restaurantCounts = {};

      print('   📦 Index sorgusu: ${ordersQuery.docs.length} sipariş');

      for (var doc in ordersQuery.docs) {
        final data = doc.data();
        count++;

        // Ödeme türü
        final sPay = data['s_pay'] as Map<String, dynamic>?;
        final payType = sPay?['ss_paytype'] as int? ?? 0;
        final customerAmount = (sPay?['ss_paycount'] ?? 0).toDouble();

        // Ödeme türüne göre topla
        if (payType == 0) {
          cash += customerAmount;
        } else if (payType == 1) {
          card += customerAmount;
        } else if (payType == 2) {
          online += customerAmount;
        }

        final dist = parseOrderDistanceKm(data);

        if (restaurantMode) {
          final workId = parseWorkId(data['s_work']);
          final rp = workId != null ? restaurantPricingMap[workId] : null;
          if (rp == null) {
            earnings += parsePayCurPacketFromOrder(data);
          } else {
            final result = calculateRestaurantPricingFee(rp, dist);
            earnings += result.totalEarnings;
            extraKmSum += result.extraKm;
          }
        } else {
          final fixedFee = courierPricing!['s_fixed_fee'] as double;
          final minKm = courierPricing['s_min_km'] as double;
          final perKmFee = courierPricing['s_per_km_fee'] as double;

          double orderEarnings = fixedFee;

          if (dist > 0 && minKm > 0 && dist > minKm) {
            final extraKm = dist - minKm;
            extraKmSum += extraKm;
            final extraKmEarnings = extraKm * perKmFee;
            orderEarnings += extraKmEarnings;
          }

          earnings += orderEarnings;
        }

        // Restoran bazlı say
        String restaurantName = data['s_restaurantName'] ?? '';
        
        // ⭐ Eğer restoran adı boşsa, t_work'ten çek
        if (restaurantName.isEmpty) {
          final sWork = data['s_work'];
          if (sWork != null) {
            // Cache'de varsa kullan, yoksa 'Telefon Siparişi' yaz
            restaurantName = 'Restoran #$sWork';
          } else {
            restaurantName = 'Telefon Siparişi';
          }
        }
        
        restaurantCounts[restaurantName] = (restaurantCounts[restaurantName] ?? 0) + 1;
      }

      // ⭐ Telefon siparişleri için restoran adlarını güncelle
      await _loadRestaurantNamesForCounts(restaurantCounts);

      setState(() {
        _packageCount = count;
        _totalEarnings = earnings;
        _totalExtraKm = extraKmSum;
        _totalCash = cash;
        _totalCard = card;
        _totalOnline = online;
        _restaurantOrderCounts = restaurantCounts;
        _restaurantPricingEnabled = restaurantMode;
        _isLoading = false;
      });

      print('   ════════════════════════════════════');
      print('   ✅ MUTABAKAT SONUÇLARI:');
      print('      📦 Sipariş: $count');
      print('      💰 Kazanç: ${earnings.toStringAsFixed(2)}₺');
      print('      🛣️ Ekstra km: ${extraKmSum.toStringAsFixed(2)} km');
      print('      💵 Nakit: ${cash.toStringAsFixed(0)}₺');
      print('      💳 Kart: ${card.toStringAsFixed(0)}₺');
      print('      📱 Online: ${online.toStringAsFixed(0)}₺');
      print('   ════════════════════════════════════');
    } catch (e) {
      print('❌ Finans verileri yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Telefon siparişleri için restoran adlarını güncelle
  Future<void> _loadRestaurantNamesForCounts(Map<String, int> counts) async {
    try {
      // "Restoran #X" formatındaki anahtarları bul
      final keysToUpdate = counts.keys.where((key) => key.startsWith('Restoran #')).toList();
      
      for (var key in keysToUpdate) {
        final sWorkStr = key.replaceAll('Restoran #', '');
        final sWork = int.tryParse(sWorkStr);
        
        if (sWork != null) {
          // t_work'ten restoran adını çek
          final workQuery = await FirebaseFirestore.instance
              .collection('t_work')
              .where('s_id', isEqualTo: sWork)
              .limit(1)
              .get();

          if (workQuery.docs.isNotEmpty) {
            final workData = workQuery.docs.first.data();
            final workName = workData['s_name'] ?? 'Telefon Siparişi';
            
            // Eski anahtarı yeni anahtarla değiştir
            final oldCount = counts[key]!;
            counts.remove(key);
            counts[workName] = (counts[workName] ?? 0) + oldCount;
            
            print('      ✅ Restoran adı güncellendi: $key → $workName');
          }
        }
      }
    } catch (e) {
      print('   ❌ Restoran adları güncelleme hatası: $e');
    }
  }

  /// Başlangıç tarih seç
  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
    );

    if (picked != null) {
      setState(() => _startDate = picked);
      _loadFinanceData();
    }
  }

  /// Bitiş tarih seç
  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
    );

    if (picked != null) {
      setState(() => _endDate = picked);
      _loadFinanceData();
    }
  }

  /// Başlangıç saat seç
  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );

    if (picked != null) {
      setState(() => _startTime = picked);
      _loadFinanceData();
    }
  }

  /// Bitiş saat seç
  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );

    if (picked != null) {
      setState(() => _endTime = picked);
      _loadFinanceData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFinanceData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tarih ve saat seçici
                    _buildDateTimePicker(),
                    
                    const SizedBox(height: 10),
                    
                    // Toplam kazanç özeti
                    _buildGeneralSummary(),
                    
                    const SizedBox(height: 10),
                    
                    // Teslim edilmiş sipariş ödeme türü
                    _buildPaymentTypes(),
                    
                    const SizedBox(height: 10),
                    
                    // Restoran bazlı sipariş sayıları
                    _buildRestaurantOrders(),
                  ],
                ),
              ),
            ),
    );
  }

  /// Tarih ve saat seçici
  Widget _buildDateTimePicker() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📅 Tarih ve Saat Seçimi',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          
          // Başlangıç
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: _selectStartDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 14, color: Color(0xFF2196F3)),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('dd MMM', 'tr').format(_startDate),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: _selectStartTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: Color(0xFF2196F3)),
                        const SizedBox(width: 4),
                        Text(
                          '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 6),
          const Center(child: Icon(Icons.arrow_downward, size: 14, color: Colors.grey)),
          const SizedBox(height: 6),
          
          // Bitiş
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: _selectEndDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 14, color: Color(0xFFFF5722)),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('dd MMM', 'tr').format(_endDate),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: _selectEndTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: Color(0xFFFF5722)),
                        const SizedBox(width: 4),
                        Text(
                          '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Toplam kazanç özeti
  Widget _buildGeneralSummary() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2196F3).withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Toplam Kazancım',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (_restaurantPricingEnabled) ...[
            const SizedBox(height: 4),
            Text(
              'Restoran bazlı ücretlendirme aktif',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.92),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryItem('Sipariş', '$_packageCount', Icons.local_shipping),
              _summaryItem('Kazanç', '${_totalEarnings.toStringAsFixed(2)}₺', Icons.attach_money),
              _summaryItem('Ekstra km', '${_totalExtraKm.toStringAsFixed(2)} km', Icons.route),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  /// Teslim edilmiş sipariş ödeme türleri
  Widget _buildPaymentTypes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Teslim Edilmiş Sipariş Ödeme Türü',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _paymentTypeCard(
                'Online',
                _totalOnline,
                Icons.phone_android,
                const Color(0xFFFF9800),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _paymentTypeCard(
                'Kart',
                _totalCard,
                Icons.credit_card,
                const Color(0xFF2196F3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _paymentTypeCard(
                'Nakit',
                _totalCash,
                Icons.money,
                const Color(0xFF4CAF50),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _paymentTypeCard(String label, double amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${amount.toStringAsFixed(2)}₺',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// Restoran bazlı sipariş sayıları
  Widget _buildRestaurantOrders() {
    if (_restaurantOrderCounts.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sipariş sayısına göre sırala (çoktan aza)
    final sortedRestaurants = _restaurantOrderCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🍽️ Restoran Bazlı Siparişler',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        ...sortedRestaurants.map((entry) {
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF673AB7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.restaurant,
                    color: Color(0xFF673AB7),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${entry.value} Sipariş',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF673AB7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${entry.value}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

