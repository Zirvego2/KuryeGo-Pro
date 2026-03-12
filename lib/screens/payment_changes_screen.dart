import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// 💳 Ödeme Değişiklikleri Ekranı
class PaymentChangesScreen extends StatefulWidget {
  final int courierId;
  final String courierName;

  const PaymentChangesScreen({
    super.key,
    required this.courierId,
    required this.courierName,
  });

  @override
  State<PaymentChangesScreen> createState() => _PaymentChangesScreenState();
}

class _PaymentChangesScreenState extends State<PaymentChangesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _changes = [];

  @override
  void initState() {
    super.initState();
    _loadPaymentChanges();
  }

  /// Ödeme değişikliklerini yükle
  Future<void> _loadPaymentChanges() async {
    setState(() => _isLoading = true);

    try {
      print('💳 Ödeme değişiklikleri yükleniyor...');
      print('   Kurye ID: ${widget.courierId}');

      // payment_changes koleksiyonundan kurye ID'ye göre çek
      final changesQuery = await FirebaseFirestore.instance
          .collection('payment_changes')
          .where('changed_by_courier_id', isEqualTo: widget.courierId)
          .orderBy('changed_at', descending: true)
          .limit(100) // Son 100 değişiklik
          .get();

      _changes = changesQuery.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();

      print('   ✅ ${_changes.length} ödeme değişikliği yüklendi');

      setState(() => _isLoading = false);
    } catch (e) {
      print('❌ Ödeme değişiklikleri yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Ödeme Değişikliklerim'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _changes.isEmpty
              ? _buildEmptyState()
              : _buildChangesList(),
    );
  }

  /// Boş durum
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz ödeme değişikliği yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Yaptığınız ödeme değişiklikleri burada görünecek',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Değişiklik listesi
  Widget _buildChangesList() {
    return RefreshIndicator(
      onRefresh: _loadPaymentChanges,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _changes.length + 1, // +1 for header
        itemBuilder: (context, index) {
          if (index == 0) {
            // Header
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                      color: const Color(0xFFFF9800).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.swap_horiz,
                      color: Color(0xFFFF9800),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_changes.length} Değişiklik',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }

          final change = _changes[index - 1];
          return _buildChangeCard(change);
        },
      ),
    );
  }

  /// Değişiklik kartı
  Widget _buildChangeCard(Map<String, dynamic> change) {
    // Veriler
    final restaurantName = change['restaurant_name'] ?? 'Restoran Adı Yok';
    final customerName = change['customer_name'] ?? 'Müşteri Adı Yok';
    final orderId = change['order_id']?.toString() ?? 'N/A';
    
    final originalPaymentType = change['original_payment_type_name'] ?? 'Bilinmiyor';
    final newPaymentType = change['new_payment_type_name'] ?? 'Bilinmiyor';
    
    final originalTotal = (change['original_total'] ?? 0).toDouble();
    final newTotal = (change['new_total'] ?? 0).toDouble();
    
    final changedAt = change['changed_at'] as Timestamp?;
    final changeDate = changedAt?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFFF9800).withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst satır: Restoran + Tarih
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
                // Tarih
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      changeDate != null
                          ? DateFormat('dd MMM', 'tr').format(changeDate)
                          : 'N/A',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      changeDate != null
                          ? DateFormat('HH:mm').format(changeDate)
                          : 'N/A',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Ödeme değişikliği
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF9800).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // Eski ödeme
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Eski Ödeme',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          originalPaymentType,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          '${originalTotal.toStringAsFixed(0)}₺',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Ok
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward,
                      color: Color(0xFFFF9800),
                      size: 20,
                    ),
                  ),
                  
                  // Yeni ödeme
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yeni Ödeme',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          newPaymentType,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFF9800),
                          ),
                        ),
                        Text(
                          '${newTotal.toStringAsFixed(0)}₺',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFF9800),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 10),
            
            // Alt bilgi: Sipariş No
            Row(
              children: [
                Icon(Icons.receipt, size: 12, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  'Sipariş No:',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '#$orderId',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

