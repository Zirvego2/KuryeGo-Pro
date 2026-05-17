import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/courier_work_handover_service.dart';
import '../services/firebase_service.dart';
import 'work_handover_my_balance_screen.dart';

/// İşletme bazlı nakit / kart teslim bildirimi (bayi ayarı açıksa).
class WorkHandoverScreen extends StatefulWidget {
  final int courierId;
  final int bayId;

  const WorkHandoverScreen({
    super.key,
    required this.courierId,
    required this.bayId,
  });

  @override
  State<WorkHandoverScreen> createState() => _WorkHandoverScreenState();
}

class _WorkHandoverScreenState extends State<WorkHandoverScreen> {
  static const Color _accent = Color(0xFF7C3AED);
  static const Color _surface = Color(0xFFF8FAFC);

  DateTime _periodStart = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
  DateTime _periodEnd = DateTime.now().copyWith(hour: 23, minute: 59, second: 59, millisecond: 999);
  List<WorkHandoverAggregate> _rows = [];
  bool _loadingAgg = false;
  String? _aggError;
  bool _featureEnabled = false;
  bool _checkingFlag = true;

  @override
  void initState() {
    super.initState();
    _checkFeature();
  }

  Future<void> _checkFeature() async {
    final on = await FirebaseService.isCourierWorkHandoverEnabledForBay(widget.bayId);
    if (!mounted) return;
    setState(() {
      _featureEnabled = on;
      _checkingFlag = false;
    });
  }

  Future<void> _loadAggregate() async {
    setState(() {
      _loadingAgg = true;
      _aggError = null;
    });
    try {
      final list = await CourierWorkHandoverService.aggregateByWork(
        courierId: widget.courierId,
        bayId: widget.bayId,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
      );
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loadingAgg = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aggError = e.toString();
        _loadingAgg = false;
      });
    }
  }

  String _fmt(double v) => NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2).format(v);

  Future<void> _submitDialog(WorkHandoverAggregate row) async {
    final cashCtrl = TextEditingController(text: row.cash.toStringAsFixed(2));
    final cardCtrl = TextEditingController(text: row.card.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.local_shipping_outlined, color: _accent),
            const SizedBox(width: 8),
            Expanded(child: Text('Teslim et — ${row.workName}', style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hesaplanan tutarlar', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Text('Nakit ${_fmt(row.cash)} · Kart ${_fmt(row.card)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${row.orderDocIds.length} sipariş', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: cashCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Teslim — Nakit',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cardCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Teslim — Kart',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final dc = double.tryParse(cashCtrl.text.replaceAll(',', '.')) ?? row.cash;
    final dk = double.tryParse(cardCtrl.text.replaceAll(',', '.')) ?? row.card;

    try {
      await CourierWorkHandoverService.submitHandover(
        bayId: widget.bayId,
        courierId: widget.courierId,
        workId: row.workId,
        workName: row.workName,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        computedCash: row.cash,
        computedCard: row.card,
        declaredCash: dc,
        declaredCard: dk,
        orderDocIds: row.orderDocIds,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text('Teslim kaydı gönderildi. İşletme onayı bekleniyor.'),
        ),
      );
      await _loadAggregate();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Widget _dateChip({required String label, required DateTime date, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 15, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.1)),
                    Text(
                      DateFormat('dd.MM.yyyy').format(date),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.15),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _businessCard(WorkHandoverAggregate r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _accent.withValues(alpha: 0.12),
                  child: Icon(Icons.storefront_outlined, color: _accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.workName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _amountChip(icon: Icons.payments_outlined, label: 'Nakit', value: _fmt(r.cash), color: const Color(0xFF059669)),
                _amountChip(icon: Icons.credit_card_outlined, label: 'Kart', value: _fmt(r.card), color: const Color(0xFF2563EB)),
                Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: Icon(Icons.receipt_long_outlined, size: 14, color: Colors.grey.shade700),
                  label: Text('${r.orderDocIds.length} sipariş', style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.grey.shade100,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.only(right: 6),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _submitDialog(r),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: const Text('Teslim Et', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.85), height: 1)),
              Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color, height: 1.15)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingFlag) {
      return const Scaffold(
        backgroundColor: _surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_featureEnabled) {
      return Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(title: const Text('İşletme teslim'), elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 56, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Bu özellik bayiniz için kapalı.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Yönetim paneli → Genel Ayarlar → İşletme–kurye teslim bildirimi ile açılabilir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('İşletme bazlı teslim', style: TextStyle(fontSize: 17)),
        elevation: 0,
        toolbarHeight: 48,
        backgroundColor: _surface,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Teslim ettiğim bakiye',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => WorkHandoverMyBalanceScreen(
                    courierId: widget.courierId,
                    bayId: widget.bayId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accent, _accent.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dönem seçin',
                  style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.1),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _dateChip(
                        label: 'Başlangıç',
                        date: _periodStart,
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _periodStart,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (d != null) {
                            setState(() {
                              _periodStart = d.copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dateChip(
                        label: 'Bitiş',
                        date: _periodEnd,
                        onTap: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _periodEnd,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (d != null) {
                            setState(() {
                              _periodEnd = d.copyWith(hour: 23, minute: 59, second: 59, millisecond: 999);
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loadingAgg ? null : _loadAggregate,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _accent,
                      disabledBackgroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      minimumSize: const Size(0, 38),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _loadingAgg
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                          )
                        : const Icon(Icons.sync_rounded, size: 18),
                    label: Text(
                      _loadingAgg ? 'Yükleniyor…' : 'Toplamları yükle',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_aggError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_aggError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          Expanded(
            child: _rows.isEmpty && !_loadingAgg
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Bu tarih aralığında teslime tabi tutar yok',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tarihi değiştirip "Toplamları yükle"ye dokunun.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: _rows.length,
                    itemBuilder: (ctx, i) => _businessCard(_rows[i]),
                  ),
          ),
        ],
      ),
    );
  }
}
