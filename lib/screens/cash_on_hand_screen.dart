import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// 💰 Üzerimdeki Nakit Ekranı
/// Kuryenin teslim etmediği nakitleri gösterir
class CashOnHandScreen extends StatefulWidget {
  final int courierId;
  final int bayId;

  const CashOnHandScreen({
    super.key,
    required this.courierId,
    required this.bayId,
  });

  @override
  State<CashOnHandScreen> createState() => _CashOnHandScreenState();
}

class _CashOnHandScreenState extends State<CashOnHandScreen> {
  bool _isLoading = true;
  
  // Nakit bilgileri
  double _newCash = 0.0;
  double _previousRemaining = 0.0;
  double _totalDebt = 0.0;
  int _orderCount = 0;
  DateTime? _lastSettlementDate;

  @override
  void initState() {
    super.initState();
    _loadCashData();
  }

  /// Nakit verilerini yükle
  Future<void> _loadCashData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Son hesap tarihini bul
      final cashHistoryQuery = FirebaseFirestore.instance
          .collection('t_courier_cash_history')
          .where('courier_id', isEqualTo: widget.courierId)
          .where('bay_id', isEqualTo: widget.bayId)
          .orderBy('settlement_date', descending: true)
          .limit(1);

      final historySnapshot = await cashHistoryQuery.get();

      DateTime? lastSettlementDate;
      double previousRemaining = 0.0;

      if (historySnapshot.docs.isNotEmpty) {
        final lastRecord = historySnapshot.docs.first.data();
        final settlementDateTimestamp = lastRecord['settlement_date'];
        if (settlementDateTimestamp != null) {
          lastSettlementDate = (settlementDateTimestamp as Timestamp).toDate();
        }
        previousRemaining = (lastRecord['remaining_amount'] ?? 0).toDouble();
      }

      // 2. Başlangıç tarihini belirle
      final endDate = DateTime.now();
      final startDate = lastSettlementDate != null
          ? lastSettlementDate.add(const Duration(minutes: 1)) // Son hesap + 1 dakika
          : DateTime(2020, 1, 1);

      // 3. Son hesaptan sonraki nakit işlemlerini çek
      final startTimestamp = Timestamp.fromDate(startDate);
      final endTimestamp = Timestamp.fromDate(endDate);

      final transactionsQuery = FirebaseFirestore.instance
          .collection('t_courier_cash_transactions')
          .where('bay_id', isEqualTo: widget.bayId)
          .where('courier_id', isEqualTo: widget.courierId)
          .where('transaction_date', isGreaterThanOrEqualTo: startTimestamp)
          .where('transaction_date', isLessThanOrEqualTo: endTimestamp)
          .orderBy('transaction_date', descending: true);

      final transactionsSnapshot = await transactionsQuery.get();

      // 4. Toplam nakit tutarını hesapla
      double newCashAmount = 0.0;
      int orderCount = 0;

      for (var doc in transactionsSnapshot.docs) {
        final transaction = doc.data();
        final cashAmount = (transaction['cash_amount'] ?? 0).toDouble();
        if (cashAmount > 0) {
          newCashAmount += cashAmount;
          orderCount += 1;
        }
      }

      // 5. Toplam borç = Yeni nakit + Önceki kalan
      final totalDebt = newCashAmount + previousRemaining;

      if (mounted) {
        setState(() {
          _newCash = newCashAmount;
          _previousRemaining = previousRemaining;
          _totalDebt = totalDebt;
          _orderCount = orderCount;
          _lastSettlementDate = lastSettlementDate;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Nakit veri yükleme hatası: $e');
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

  /// Para formatı (TRY)
  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    ).format(amount);
  }

  /// Tarih formatı
  String _formatDate(DateTime? date) {
    if (date == null) return 'Hesap yapılmamış';
    return DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          ' Nakit Hesaplarım',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCashData,
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toplam Borç Kartı (Büyük)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue[600]!,
                          Colors.blue[800]!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
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
                        const Text(
                          'Toplam Borç',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatCurrency(_totalDebt),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Detaylar
                  _buildSectionTitle('📊 Detaylar'),
                  const SizedBox(height: 12),

                  // Yeni Nakit
                  _buildInfoCard(
                    icon: Icons.attach_money,
                    iconColor: Colors.green,
                    title: 'Yeni Nakit',
                    subtitle: 'Son hesaptan sonraki dönemden gelen nakit',
                    value: _formatCurrency(_newCash),
                    valueColor: Colors.green[700]!,
                  ),

                  const SizedBox(height: 12),

                  // Sipariş Sayısı
                  _buildInfoCard(
                    icon: Icons.shopping_bag,
                    iconColor: Colors.orange,
                    title: 'Sipariş Sayısı',
                    subtitle: 'Nakit işlemi yapılan sipariş sayısı',
                    value: '$_orderCount adet',
                    valueColor: Colors.orange[700]!,
                  ),

                  // Önceki Kalan (varsa)
                  if (_previousRemaining > 0) ...[
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      icon: Icons.history,
                      iconColor: Colors.amber,
                      title: 'Önceki Kalan',
                      subtitle: 'Son hesaptan kalan tutar',
                      value: _formatCurrency(_previousRemaining),
                      valueColor: Colors.amber[800]!,
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Son Hesap Tarihi
                  _buildSectionTitle('📅 Hesap Bilgileri'),
                  const SizedBox(height: 12),

                  _buildInfoCard(
                    icon: Icons.calendar_today,
                    iconColor: Colors.purple,
                    title: 'Son Hesap Tarihi',
                    subtitle: 'En son hesap yapılan tarih',
                    value: _formatDate(_lastSettlementDate),
                    valueColor: Colors.purple[700]!,
                  ),

                  const SizedBox(height: 32),

                  // Bilgilendirme
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
                            'Bu tutar, teslim etmeniz gereken toplam nakit miktarıdır. '
                            'Hesap yapıldığında bu tutar sıfırlanır.',
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
            ),
    );
  }

  /// Bölüm başlığı
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
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
  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String value,
    required Color valueColor,
  }) {
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
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
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
