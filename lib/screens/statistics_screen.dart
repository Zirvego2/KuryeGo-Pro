import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/business_day_bounds.dart';

/// 📊 İstatistikler & Performans Ekranı
class StatisticsScreen extends StatefulWidget {
  final int courierId;
  final String courierName;

  const StatisticsScreen({
    super.key,
    required this.courierId,
    required this.courierName,
  });

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  String _selectedPeriod = 'daily'; // daily, weekly, monthly
  bool _isLoading = true;
  
  // İstatistikler
  int _todayDeliveries = 0;
  int _weeklyDeliveries = 0;
  int _monthlyDeliveries = 0;
  double _avgDeliveryTime = 0.0; // dakika cinsinden
  final double _totalDistance = 0.0; // km cinsinden
  List<int> _dailyData = List.filled(7, 0); // Son 7 gün
  
  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  /// İstatistikleri yükle
  Future<void> _loadStatistics() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final resetHour = prefs.getInt('daily_reset_hour') ?? 0;
      final dayBounds = getBusinessDayBounds(now, resetHour);

      final calendarTodayStart = DateTime(now.year, now.month, now.day);
      final weekStart = calendarTodayStart.subtract(Duration(days: now.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 7));
      final monthStart = DateTime(now.year, now.month, 1);

      // ⭐ TESLİM TARİHİNE GÖRE (s_ddate) - DOĞRU!
      // Index: s_courier + s_stat + s_ddate ✅
      final monthQuery = await FirebaseFirestore.instance
          .collection('t_orders')
          .where('s_courier', isEqualTo: widget.courierId)
          .where('s_stat', isEqualTo: 2) // ⭐ 2 = Teslim edildi
          .where('s_ddate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .get();

      print('📊 İSTATİSTİK: Ay başından beri ${monthQuery.docs.length} teslim edilmiş sipariş');

      // Client-side filtering (daha verimli - tek sorgu)
      _monthlyDeliveries = monthQuery.docs.length;
      
      _weeklyDeliveries = monthQuery.docs.where((doc) {
        final ddate = (doc.data()['s_ddate'] as Timestamp?)?.toDate();
        return isDateTimeInRange(ddate, weekStart, weekEnd);
      }).length;
      
      // Profil kartı ile aynı: günlük sıfırlama saati + [start, end)
      _todayDeliveries = monthQuery.docs.where((doc) {
        final ddate = (doc.data()['s_ddate'] as Timestamp?)?.toDate();
        return isDateTimeInRange(ddate, dayBounds.start, dayBounds.end);
      }).length;
      
      print('   📅 Bugün teslim: $_todayDeliveries');
      print('   📅 Bu hafta: $_weeklyDeliveries');
      print('   📅 Bu ay: $_monthlyDeliveries');

      // Son 7 günün günlük verilerini hesapla (s_ddate ile)
      _dailyData = List.filled(7, 0);
      for (int i = 0; i < 7; i++) {
        final dayStart = calendarTodayStart.subtract(Duration(days: 6 - i));
        final dayEnd = dayStart.add(const Duration(days: 1));
        
        final dayCount = monthQuery.docs.where((doc) {
          final ddate = (doc.data()['s_ddate'] as Timestamp?)?.toDate();
          return isDateTimeInRange(ddate, dayStart, dayEnd);
        }).length;
        
        _dailyData[i] = dayCount;
      }

      // Ortalama teslimat süresini hesapla (haftalık)
      final weekDocs = monthQuery.docs.where((doc) {
        final ddate = (doc.data()['s_ddate'] as Timestamp?)?.toDate();
        return isDateTimeInRange(ddate, weekStart, weekEnd);
      }).toList();
      
      if (weekDocs.isNotEmpty) {
        double totalMinutes = 0;
        int validCount = 0;
        
        for (var doc in weekDocs) {
          final data = doc.data();
          final adate = (data['s_adate'] as Timestamp?)?.toDate(); // Atama zamanı
          final ddate = (data['s_ddate'] as Timestamp?)?.toDate(); // Teslim zamanı
          
          if (adate != null && ddate != null) {
            final diff = ddate.difference(adate).inMinutes;
            if (diff > 0 && diff < 300) { // Mantıklı aralık (5 saate kadar)
              totalMinutes += diff;
              validCount++;
            }
          }
        }
        
        if (validCount > 0) {
          _avgDeliveryTime = totalMinutes / validCount;
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('❌ İstatistik yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatistics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Periyot seçimi
                    _buildPeriodSelector(),
                    
                    const SizedBox(height: 10),
                    
                    // Özet kartlar
                    _buildSummaryCards(),
                    
                    const SizedBox(height: 12),
                    
                    // Grafik
                    _buildChart(),
                    
                    const SizedBox(height: 12),
                    
                    // Performans metrikleri
                    _buildPerformanceMetrics(),
                  ],
                ),
              ),
            ),
    );
  }

  /// Periyot seçici
  Widget _buildPeriodSelector() {
    return Row(
      children: [
        Expanded(child: _periodButton('Günlük', 'daily')),
        const SizedBox(width: 6),
        Expanded(child: _periodButton('Haftalık', 'weekly')),
        const SizedBox(width: 6),
        Expanded(child: _periodButton('Aylık', 'monthly')),
      ],
    );
  }

  Widget _periodButton(String label, String value) {
    final isSelected = _selectedPeriod == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedPeriod = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2196F3).withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// Özet kartlar
  Widget _buildSummaryCards() {
    int deliveryCount;
    String period;

    switch (_selectedPeriod) {
      case 'daily':
        deliveryCount = _todayDeliveries;
        period = 'Bugün';
        break;
      case 'weekly':
        deliveryCount = _weeklyDeliveries;
        period = 'Bu Hafta';
        break;
      case 'monthly':
        deliveryCount = _monthlyDeliveries;
        period = 'Bu Ay';
        break;
      default:
        deliveryCount = _todayDeliveries;
        period = 'Bugün';
    }

    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            icon: Icons.local_shipping,
            title: 'Teslimat',
            value: deliveryCount.toString(),
            subtitle: period,
            color: const Color(0xFF4CAF50),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _summaryCard(
            icon: Icons.timer,
            title: 'Ort. Süre',
            value: '${_avgDeliveryTime.toStringAsFixed(0)} dk',
            subtitle: 'Bu Hafta',
            color: const Color(0xFFFFA726),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  /// Grafik
  Widget _buildChart() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
            '📊 Son 7 Gün',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (_dailyData.reduce((a, b) => a > b ? a : b) + 2).toDouble(),
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= 7) return const Text('');
                        
                        final date = DateTime.now().subtract(Duration(days: 6 - index));
                        final day = DateFormat('E', 'tr').format(date).substring(0, 2);
                        
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            day,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.black54,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= 7) return const Text('');
                        final count = _dailyData[index];
                        if (count == 0) return const Text(''); // 0 ise gösterme
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2196F3),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withOpacity(0.2),
                      strokeWidth: 1,
                    );
                  },
                ),
                barGroups: List.generate(
                  7,
                  (index) => BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: _dailyData[index].toDouble(),
                        color: const Color(0xFF2196F3),
                        width: 12,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Performans metrikleri
  Widget _buildPerformanceMetrics() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
            '⚡ Performans Metrikleri',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          _metricRow('Ortalama Teslimat Süresi', '${_avgDeliveryTime.toStringAsFixed(0)} dakika', Icons.timer),
          const Divider(height: 18),
          _metricRow('Bugünkü Teslimatlar', '$_todayDeliveries sipariş', Icons.today),
          const Divider(height: 18),
          _metricRow('Haftalık Teslimatlar', '$_weeklyDeliveries sipariş', Icons.calendar_today),
          const Divider(height: 18),
          _metricRow('Aylık Teslimatlar', '$_monthlyDeliveries sipariş', Icons.calendar_month),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: const Color(0xFF2196F3), size: 17),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2196F3),
          ),
        ),
      ],
    );
  }
}

