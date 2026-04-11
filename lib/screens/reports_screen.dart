import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';

/// 📄 Raporlar Ekranı - Detaylı Sipariş Listesi
class ReportsScreen extends StatefulWidget {
  final int courierId;
  final String courierName;

  const ReportsScreen({
    super.key,
    required this.courierId,
    required this.courierName,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

DateTime _reportsDateOnlyNow() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

class _ReportsScreenState extends State<ReportsScreen> {
  /// Sadece takvim günü (saat yok). `late` kullanılmıyor — TabBarView/hot reload’da initState’ten önce build gelmesi crash’i önlenir.
  DateTime _startDate = _reportsDateOnlyNow();
  DateTime _endDate = _reportsDateOnlyNow();
  TimeOfDay _startTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 59);
  bool _isLoading = true;
  List<Map<String, dynamic>> _orders = [];
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _startDate = DateTime(n.year, n.month, n.day);
    _endDate = DateTime(n.year, n.month, n.day);
    _loadOrders();
  }

  static int? _parseStat(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// Siparişleri yükle
  /// Tek alanlı sorgu (s_courier) — bileşik Firestore indeksi gerekmez; filtre istemcide.
  Future<void> _loadOrders() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final rangeStart = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        _startTime.hour,
        _startTime.minute,
      );
      final rangeEnd = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        _endTime.hour,
        _endTime.minute,
        59,
      );

      // Firestore: teslim tarihi bu ay aralığında olanları çek (başlangıç–bitiş aylarını kapsar)
      final queryMonthStart = DateTime(rangeStart.year, rangeStart.month, 1);
      final queryMonthEnd =
          DateTime(rangeEnd.year, rangeEnd.month + 1, 0, 23, 59, 59);

      print('📄 [RAPORLAR] Yükleniyor...');
      print(
        '   📅 Aralık: ${DateFormat('dd.MM.yyyy HH:mm', 'tr').format(rangeStart)} → ${DateFormat('dd.MM.yyyy HH:mm', 'tr').format(rangeEnd)}',
      );
      print('   👤 Kurye ID: ${widget.courierId}');

      final monthStart = queryMonthStart;
      final monthEnd = queryMonthEnd;

      QuerySnapshot<Map<String, dynamic>> ordersQuery;
      const fetchLimit = 1000;
      try {
        ordersQuery = await FirebaseFirestore.instance
            .collection('t_orders')
            .where('s_courier', isEqualTo: widget.courierId)
            .where('s_stat', isEqualTo: 2)
            .where('s_ddate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
            .where('s_ddate', isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
            .get();
        print('   📦 Ay sorgusu (indeksli): ${ordersQuery.docs.length} belge');
      } on FirebaseException catch (fe) {
        if (fe.code == 'failed-precondition') {
          print('   ⚠️ Ay sorgusu indeks yok, yedek sorgu (s_courier + limit)...');
          ordersQuery = await FirebaseFirestore.instance
              .collection('t_orders')
              .where('s_courier', isEqualTo: widget.courierId)
              .limit(fetchLimit)
              .get();
          if (ordersQuery.docs.length >= fetchLimit) {
            print('   ⚠️ En fazla $fetchLimit sipariş okundu; çok yoğun hesaplarda bazı kayıtlar eksik kalabilir.');
          }
        } else {
          rethrow;
        }
      }

      if (!mounted) return;

      // Teslim (s_stat==2) + sorgu ay aralığı + seçili tarih/saat aralığı
      final filteredOrders = ordersQuery.docs.where((doc) {
        final data = doc.data();
        if (_parseStat(data['s_stat']) != 2) return false;

        final ddate = data['s_ddate'];
        DateTime? deliveryDate;
        if (ddate is Timestamp) {
          deliveryDate = ddate.toDate();
        } else if (ddate != null) {
          return false;
        }
        if (deliveryDate == null) return false;

        if (deliveryDate.isBefore(monthStart) || deliveryDate.isAfter(monthEnd)) {
          return false;
        }

        return deliveryDate.isAfter(rangeStart.subtract(const Duration(seconds: 1))) &&
            deliveryDate.isBefore(rangeEnd.add(const Duration(seconds: 1)));
      }).toList();

      print('   ✅ Seçili aralığa uyan teslim: ${filteredOrders.length} sipariş');

      _orders = filteredOrders.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();

      _orders.sort((a, b) {
        final ddateA = (a['s_ddate'] as Timestamp?)?.toDate();
        final ddateB = (b['s_ddate'] as Timestamp?)?.toDate();

        if (ddateA == null && ddateB == null) return 0;
        if (ddateA == null) return 1;
        if (ddateB == null) return -1;

        return ddateB.compareTo(ddateA);
      });

      await _loadRestaurantNames();

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = null;
      });
    } catch (e, stackTrace) {
      print('❌ [RAPORLAR] Yükleme hatası: $e');
      print('   Stack trace: $stackTrace');

      String? userMsg;
      if (e is FirebaseException && e.code == 'failed-precondition') {
        userMsg = 'Veri yüklenemedi (sunucu indeksi). Yöneticiye bildirin veya tekrar deneyin.';
      } else {
        userMsg = 'Raporlar yüklenirken hata oluştu. İnternet bağlantınızı kontrol edip yenileyin.';
      }

      if (!mounted) return;
      setState(() {
        _orders = [];
        _isLoading = false;
        _loadError = userMsg;
      });
    }
  }

  /// Telefon siparişleri için restoran adlarını yükle
  Future<void> _loadRestaurantNames() async {
    try {
      for (var order in _orders) {
        // Eğer s_restaurantName boş ise ve s_work varsa
        final restaurantName = order['s_restaurantName'] ?? '';
        final sWork = order['s_work'];

        if (restaurantName.isEmpty && sWork != null) {
          print('   🔍 Restoran adı eksik, t_work\'ten çekiliyor: s_work = $sWork');
          
          // t_work'ten restoran adını çek
          final workQuery = await FirebaseFirestore.instance
              .collection('t_work')
              .where('s_id', isEqualTo: sWork)
              .limit(1)
              .get();

          if (workQuery.docs.isNotEmpty) {
            final workData = workQuery.docs.first.data();
            final workName = workData['s_name'] ?? 'Telefon Siparişi';
            order['s_restaurantName'] = workName;
            print('      ✅ Restoran adı bulundu: $workName');
          } else {
            order['s_restaurantName'] = 'Telefon Siparişi';
            print('      ⚠️ t_work bulunamadı');
          }
        }
      }
    } catch (e) {
      print('   ❌ Restoran adları yükleme hatası: $e');
    }
  }

  /// Başlangıç saati seç
  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: 'Başlangıç Saati',
    );
    if (picked != null) {
      setState(() => _startTime = picked);
      _loadOrders();
    }
  }

  /// Bitiş saati seç
  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      helpText: 'Bitiş Saati',
    );
    if (picked != null) {
      setState(() => _endTime = picked);
      _loadOrders();
    }
  }

  /// Bugün, tam gün (00:00–23:59)
  void _resetToTodayFullDay() {
    final n = DateTime.now();
    setState(() {
      _startDate = DateTime(n.year, n.month, n.day);
      _endDate = DateTime(n.year, n.month, n.day);
      _startTime = const TimeOfDay(hour: 0, minute: 0);
      _endTime = const TimeOfDay(hour: 23, minute: 59);
    });
    _loadOrders();
  }

  /// Başlangıç tarihi
  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
      _loadOrders();
    }
  }

  /// Bitiş tarihi
  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
    );

    if (picked != null) {
      setState(() => _endDate = picked);
      _loadOrders();
    }
  }

  /// Ödeme türü metni
  String _getPaymentTypeText(int? payType) {
    switch (payType) {
      case 0: return 'Nakit';
      case 1: return 'Kredi Kartı';
      case 2: return 'Online';
      default: return 'Bilinmiyor';
    }
  }

  /// Ödeme türü ikonu
  IconData _getPaymentTypeIcon(int? payType) {
    switch (payType) {
      case 0: return Icons.money;
      case 1: return Icons.credit_card;
      case 2: return Icons.phone_android;
      default: return Icons.help_outline;
    }
  }

  /// Ödeme türü rengi
  Color _getPaymentTypeColor(int? payType) {
    switch (payType) {
      case 0: return Colors.green;
      case 1: return Colors.blue;
      case 2: return Colors.orange;
      default: return Colors.grey;
    }
  }

  List<Widget> _buildScrollHeaderSlivers() {
    return [
      if (_loadError != null)
        SliverToBoxAdapter(
          child: Material(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade800, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _loadError!,
                      style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _loadOrders,
                    child: const Text('Yenile', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ),
      SliverToBoxAdapter(child: _buildDateSelector()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ..._buildScrollHeaderSlivers(),
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_orders.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              _buildOrdersSliverList(),
          ],
        ),
      ),
    );
  }

  /// Başlangıç / bitiş tarih ve saat (varsayılan: bugün 00:00–23:59)
  Widget _buildDateSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF673AB7), Color(0xFF512DA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF673AB7).withOpacity(0.18),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tarih aralığı',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Başlangıç',
            style: TextStyle(fontSize: 10, color: Colors.white60),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildPurpleDateChip(
                  DateFormat('dd MMM yyyy', 'tr').format(_startDate),
                  _selectStartDate,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildTimeChip(_startTime.format(context), _selectStartTime),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Center(
            child: Icon(Icons.arrow_downward, size: 12, color: Colors.white54),
          ),
          const SizedBox(height: 4),
          const Text(
            'Bitiş',
            style: TextStyle(fontSize: 10, color: Colors.white60),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildPurpleDateChip(
                  DateFormat('dd MMM yyyy', 'tr').format(_endDate),
                  _selectEndDate,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildTimeChip(_endTime.format(context), _selectEndTime),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: _resetToTodayFullDay,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.today, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Bugün (24 saat)',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurpleDateChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(0.28)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 11, color: Colors.white),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Saat chip widget'ı
  Widget _buildTimeChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(0.28)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  /// Boş durum
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            'Sipariş Bulunamadı',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Seçili tarih ve saat aralığında teslim yok',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// Sipariş listesi (üstteki tarih alanı ile aynı kaydırma içinde)
  Widget _buildOrdersSliverList() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF673AB7).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.receipt_long,
                        color: Color(0xFF673AB7),
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_orders.length} Sipariş',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Teslim Edildi',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }
            final order = _orders[index - 1];
            return _buildOrderCard(order);
          },
          childCount: _orders.length + 1,
        ),
      ),
    );
  }

  /// Sipariş kartı
  Widget _buildOrderCard(Map<String, dynamic> order) {
    final customer = order['s_customer'] as Map<String, dynamic>?;
    final sPay = order['s_pay'] as Map<String, dynamic>?;
    final payType = sPay?['ss_paytype'] as int?;
    final amount = (sPay?['ss_paycount'] ?? 0).toDouble();
    final restaurantName = order['s_restaurantName'] ?? 'Restoran Adı Yok';
    final orderId = order['s_orderid'] ?? order['s_pid'] ?? 'N/A';
    
    // Zaman bilgileri
    final cdate = (order['s_cdate'] as Timestamp?)?.toDate();
    final ddate = (order['s_ddate'] as Timestamp?)?.toDate();
    
    // Müşteri bilgileri
    final customerName = customer?['ss_fullname'] ?? 'Müşteri Adı Yok';
    final customerAddress = customer?['ss_adres'] ?? 'Adres Yok';
    final customerPhone = customer?['ss_phone'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: _getPaymentTypeColor(payType).withOpacity(0.12),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showOrderDetails(order),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            children: [
              // Üst satır: Restoran + Tutar
              Row(
                children: [
                  // Restoran ikonu
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF673AB7).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Icon(
                      Icons.restaurant,
                      color: Color(0xFF673AB7),
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurantName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          customerName,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Tutar + Ödeme türü
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${amount.toStringAsFixed(0)}₺',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _getPaymentTypeColor(payType),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getPaymentTypeIcon(payType),
                            size: 10,
                            color: _getPaymentTypeColor(payType),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _getPaymentTypeText(payType),
                            style: TextStyle(
                              fontSize: 9,
                              color: _getPaymentTypeColor(payType),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 6),
              
              // Alt satır: Zaman + Sipariş No
              Row(
                children: [
                  Icon(Icons.access_time, size: 10, color: Colors.grey[500]),
                  const SizedBox(width: 2),
                  Text(
                    cdate != null ? DateFormat('HH:mm').format(cdate) : 'N/A',
                    style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 3),
                  const Text('→', style: TextStyle(fontSize: 8, color: Colors.grey)),
                  const SizedBox(width: 3),
                  Icon(Icons.check_circle, size: 10, color: Colors.green[600]),
                  const SizedBox(width: 2),
                  Text(
                    ddate != null ? DateFormat('HH:mm').format(ddate) : 'N/A',
                    style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#$orderId',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sipariş detayları göster
  void _showOrderDetails(Map<String, dynamic> order) {
    final customer = order['s_customer'] as Map<String, dynamic>?;
    final sPay = order['s_pay'] as Map<String, dynamic>?;
    final products = order['s_products'] as List?;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Başlık
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
              child: Row(
                children: [
                  const Text(
                    'Sipariş Detayları',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // İçerik
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Restoran
                    _detailRow('Restoran', order['s_restaurantName'] ?? 'N/A', Icons.restaurant),
                    const SizedBox(height: 10),
                    
                    // Müşteri
                    _detailRow('Müşteri', customer?['ss_fullname'] ?? 'N/A', Icons.person),
                    const SizedBox(height: 10),
                    
                    // Adres
                    _detailRow('Adres', customer?['ss_adres'] ?? 'N/A', Icons.location_on),
                    const SizedBox(height: 10),
                    
                    // Ödeme Türü
                    _detailRow('Ödeme Türü', _getPaymentTypeText(sPay?['ss_paytype']), Icons.payment),
                    const SizedBox(height: 10),
                    
                    // Tutar
                    _detailRow('Tutar', '${(sPay?['ss_paycount'] ?? 0)}₺', Icons.money),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Detay satırı
  Widget _detailRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF673AB7)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

