import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 📅 İzin Günüm Ekranı
/// Kuryenin haftalık izin planını gösterir
class LeavePlanScreen extends StatefulWidget {
  final int courierId;
  final int bayId;

  const LeavePlanScreen({
    super.key,
    required this.courierId,
    required this.bayId,
  });

  @override
  State<LeavePlanScreen> createState() => _LeavePlanScreenState();
}

class _LeavePlanScreenState extends State<LeavePlanScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _leavePlan;

  // Gün isimleri (0=Pazartesi, 6=Pazar)
  static const List<Map<String, dynamic>> DAYS_OF_WEEK = [
    {'id': 0, 'label': 'Pazartesi', 'short': 'Pzt'},
    {'id': 1, 'label': 'Salı', 'short': 'Sal'},
    {'id': 2, 'label': 'Çarşamba', 'short': 'Çar'},
    {'id': 3, 'label': 'Perşembe', 'short': 'Per'},
    {'id': 4, 'label': 'Cuma', 'short': 'Cum'},
    {'id': 5, 'label': 'Cumartesi', 'short': 'Cmt'},
    {'id': 6, 'label': 'Pazar', 'short': 'Paz'},
  ];

  @override
  void initState() {
    super.initState();
    _loadLeavePlan();
  }

  /// İzin planını Firebase'den yükle
  Future<void> _loadLeavePlan() async {
    setState(() => _isLoading = true);

    try {
      final leavePlansQuery = FirebaseFirestore.instance
          .collection('t_courier_weekly_leave_plans')
          .where('courier_id', isEqualTo: widget.courierId)
          .where('bay_id', isEqualTo: widget.bayId)
          .where('is_active', isEqualTo: true)
          .limit(1);

      final snapshot = await leavePlansQuery.get();

      if (snapshot.docs.isNotEmpty) {
        final plan = snapshot.docs.first.data();
        if (mounted) {
          setState(() {
            _leavePlan = plan;
            _isLoading = false;
          });
        }
        print('✅ İzin planı yüklendi: ${plan['plan_name'] ?? 'İsimsiz'}');
      } else {
        if (mounted) {
          setState(() {
            _leavePlan = null;
            _isLoading = false;
          });
        }
        print('ℹ️ Aktif izin planı bulunamadı');
      }
    } catch (e) {
      print('❌ İzin planı yükleme hatası: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Veri yüklenirken hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// İzin günlerini gün isimlerine çevir
  String _getLeaveDaysLabels(List<dynamic>? leaveDays) {
    if (leaveDays == null || leaveDays.isEmpty) {
      return 'İzin günü yok';
    }

    // Gün ID'lerini sırala ve isimlere çevir
    final sortedDays = leaveDays.map((d) => d is int ? d : int.tryParse(d.toString()) ?? -1).where((d) => d >= 0 && d <= 6).toList()..sort();

    if (sortedDays.isEmpty) {
      return 'İzin günü yok';
    }

    return sortedDays.map((dayId) {
      final day = DAYS_OF_WEEK.firstWhere(
        (d) => d['id'] == dayId,
        orElse: () => {'id': dayId, 'label': 'Bilinmeyen', 'short': '?'},
      );
      return day['label'] as String;
    }).join(', ');
  }

  /// Bugün izinli mi kontrolü
  bool _isOnLeaveToday() {
    if (_leavePlan == null) return false;

    final leaveDays = _leavePlan!['leave_days'] as List<dynamic>?;
    if (leaveDays == null || leaveDays.isEmpty) return false;

    // JavaScript'te Pazar 0, ama bizim sistemimizde Pazartesi 0
    // Bu yüzden dönüşüm yapmalıyız
    final today = DateTime.now().weekday; // 1=Pazartesi, 7=Pazar
    final dayIndex = today == 7 ? 6 : today - 1; // Pazar için 6, diğerleri için -1

    return leaveDays.contains(dayIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          '📅 İzin Günüm',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeavePlan,
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _leavePlan == null
              ? _buildNoPlanView()
              : _buildPlanView(),
    );
  }

  /// Plan yoksa gösterilecek görünüm
  Widget _buildNoPlanView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              'Henüz İzin Planınız Yok',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'İzin planınız henüz oluşturulmamış.\nYöneticinizle iletişime geçin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Plan varsa gösterilecek görünüm
  Widget _buildPlanView() {
    final leaveDays = _leavePlan!['leave_days'] as List<dynamic>? ?? [];
    final planName = _leavePlan!['plan_name'] as String? ?? 'İzin Planı';
    final notes = _leavePlan!['notes'] as String?;
    final isTodayLeave = _isOnLeaveToday();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bugün izinli mi kartı
          if (isTodayLeave)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green[400]!,
                    Colors.green[600]!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.celebration,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bugün İzinlisiniz!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'İyi tatiller dileriz 🎉',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Plan kartı
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan adı
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF673AB7).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.calendar_month,
                        color: Color(0xFF673AB7),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        planName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // İzinli günler başlığı
                const Text(
                  'İzinli Günler:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),

                const SizedBox(height: 12),

                // Günler grid
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: DAYS_OF_WEEK.map((day) {
                    final dayId = day['id'] as int;
                    final isLeaveDay = leaveDays.contains(dayId);
                    final dayShort = day['short'] as String;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isLeaveDay
                            ? const Color(0xFF673AB7)
                            : Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLeaveDay
                              ? const Color(0xFF673AB7)
                              : Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        dayShort,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isLeaveDay ? Colors.white : Colors.grey[700],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // İzinli günler metni
                if (leaveDays.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getLeaveDaysLabels(leaveDays),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[900],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Notlar (varsa)
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Notlar:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      notes,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Bilgilendirme kartı
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'İzin planınız yönetici tarafından belirlenmiştir. '
                    'Değişiklik için yöneticinizle iletişime geçin.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue[900],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
