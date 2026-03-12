import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  /// Siparişleri yükle
  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);

    try {
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);

      print('📄 [RAPORLAR] Yükleniyor...');
      print('   📅 Seçili Tarih: ${DateFormat('dd MMMM yyyy', 'tr').format(_selectedDate)}');
      print('   ⏰ Başlangıç: $startOfDay');
      print('   ⏰ Bitiş: $endOfDay');
      print('   👤 Kurye ID: ${widget.courierId}');

      // ⭐ TESLİM TARİHİNE GÖRE (s_ddate) - DOĞRU!
      // Index: s_courier + s_stat + s_ddate ✅
      // Önce geniş bir aralık çek, sonra client-side filter (index sorunlarını önlemek için)
      final monthStart = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final monthEnd = DateTime(_selectedDate.year, _selectedDate.month + 1, 0, 23, 59, 59);

      final ordersQuery = await FirebaseFirestore.instance
          .collection('t_orders')
          .where('s_courier', isEqualTo: widget.courierId)
          .where('s_stat', isEqualTo: 2) // Teslim edilenler
          .where('s_ddate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('s_ddate', isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
          .get();

      print('   📦 Ay içinde toplam teslim edilmiş: ${ordersQuery.docs.length} sipariş');

      // Client-side filtering: Seçili güne ait siparişleri filtrele
      final filteredOrders = ordersQuery.docs.where((doc) {
        final data = doc.data();
        final ddate = data['s_ddate'] as Timestamp?;
        if (ddate == null) return false;
        
        final deliveryDate = ddate.toDate();
        // Seçili günün 00:00:00 - 23:59:59 aralığında mı?
        return deliveryDate.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
               deliveryDate.isBefore(endOfDay.add(const Duration(seconds: 1)));
      }).toList();

      print('   ✅ Seçili tarihe ait teslim edilmiş: ${filteredOrders.length} sipariş');

      // Map'le ve teslim tarihine göre sırala (en yeni önce)
      _orders = filteredOrders.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();

      // Teslim tarihine göre sırala (en yeni önce)
      _orders.sort((a, b) {
        final ddateA = (a['s_ddate'] as Timestamp?)?.toDate();
        final ddateB = (b['s_ddate'] as Timestamp?)?.toDate();
        
        if (ddateA == null && ddateB == null) return 0;
        if (ddateA == null) return 1;
        if (ddateB == null) return -1;
        
        return ddateB.compareTo(ddateA); // En yeni önce
      });

      print('   ✅ ${_orders.length} sipariş listeye eklendi (teslim tarihine göre sıralandı)');

      // ⭐ Telefon siparişleri için restoran adlarını çek
      await _loadRestaurantNames();

      setState(() => _isLoading = false);
    } catch (e, stackTrace) {
      print('❌ [RAPORLAR] Yükleme hatası: $e');
      print('   Stack trace: $stackTrace');
      
      // Hata durumunda boş liste göster
      setState(() {
        _orders = [];
        _isLoading = false;
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

  /// Tarih seç
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('tr', 'TR'),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // Tarih seçici (Kompakt)
          _buildDateSelector(),
          
          // Sipariş listesi (Daha fazla yer)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _orders.isEmpty
                    ? _buildEmptyState()
                    : _buildOrdersList(),
          ),
        ],
      ),
    );
  }

  /// Tarih seçici (Kompakt)
  Widget _buildDateSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF673AB7), Color(0xFF512DA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF673AB7).withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: Colors.white, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${DateFormat('dd MMM yyyy', 'tr').format(_selectedDate)} • ${DateFormat('EEEE', 'tr').format(_selectedDate)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          InkWell(
            onTap: _selectDate,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_calendar, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Değiştir',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Boş durum
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'Sipariş Bulunamadı',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Seçili tarihte teslim edilmiş sipariş yok',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// Sipariş listesi
  Widget _buildOrdersList() {
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: _orders.length + 1, // +1 for header
        itemBuilder: (context, index) {
          if (index == 0) {
            // Header (Kompakt)
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 4,
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
                      Icons.receipt_long,
                      color: Color(0xFF673AB7),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_orders.length} Sipariş',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Teslim Edildi',
                    style: TextStyle(
                      fontSize: 11,
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: _getPaymentTypeColor(payType).withOpacity(0.15),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => _showOrderDetails(order),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Üst satır: Restoran + Tutar
              Row(
                children: [
                  // Restoran ikonu
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF673AB7).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.restaurant,
                      color: Color(0xFF673AB7),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurantName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          customerName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Tutar + Ödeme türü
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${amount.toStringAsFixed(0)}₺',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _getPaymentTypeColor(payType),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getPaymentTypeIcon(payType),
                            size: 11,
                            color: _getPaymentTypeColor(payType),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _getPaymentTypeText(payType),
                            style: TextStyle(
                              fontSize: 10,
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
              
              const SizedBox(height: 10),
              
              // Alt satır: Zaman + Sipariş No
              Row(
                children: [
                  Icon(Icons.access_time, size: 11, color: Colors.grey[500]),
                  const SizedBox(width: 3),
                  Text(
                    cdate != null ? DateFormat('HH:mm').format(cdate) : 'N/A',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 4),
                  const Text('→', style: TextStyle(fontSize: 9, color: Colors.grey)),
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle, size: 11, color: Colors.green[600]),
                  const SizedBox(width: 3),
                  Text(
                    ddate != null ? DateFormat('HH:mm').format(ddate) : 'N/A',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#$orderId',
                      style: TextStyle(
                        fontSize: 9,
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
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Başlık
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'Sipariş Detayları',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            const Divider(),
            
            // İçerik
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Restoran
                    _detailRow('Restoran', order['s_restaurantName'] ?? 'N/A', Icons.restaurant),
                    const SizedBox(height: 16),
                    
                    // Müşteri
                    _detailRow('Müşteri', customer?['ss_fullname'] ?? 'N/A', Icons.person),
                    const SizedBox(height: 16),
                    
                    // Adres
                    _detailRow('Adres', customer?['ss_adres'] ?? 'N/A', Icons.location_on),
                    const SizedBox(height: 16),
                    
                    // Ödeme Türü
                    _detailRow('Ödeme Türü', _getPaymentTypeText(sPay?['ss_paytype']), Icons.payment),
                    const SizedBox(height: 16),
                    
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
        Icon(icon, size: 20, color: const Color(0xFF2196F3)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
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

