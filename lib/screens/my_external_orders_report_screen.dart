import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// Brand colors
const _kPrimary     = Color(0xFF2563EB);
const _kSurface     = Color(0xFFF8FAFC);
const _kCardBg      = Color(0xFFFFFFFF);
const _kBorder      = Color(0xFFE2E8F0);
const _kTextPrimary = Color(0xFF111827);
const _kTextMuted   = Color(0xFF6B7280);
const _kSuccess     = Color(0xFF10B981);
const _kDanger      = Color(0xFFEF4444);
const _kWarning     = Color(0xFFF59E0B);

class MyExternalOrdersReportScreen extends StatefulWidget {
  final int courierId;
  final int bayId;

  const MyExternalOrdersReportScreen({
    super.key,
    required this.courierId,
    required this.bayId,
  });

  @override
  State<MyExternalOrdersReportScreen> createState() =>
      _MyExternalOrdersReportScreenState();
}

class _MyExternalOrdersReportScreenState
    extends State<MyExternalOrdersReportScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  // Tarih aralığı (varsayılan: son 30 gün)
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _endDate   = DateTime.now();
    _startDate = _endDate.subtract(const Duration(days: 29));
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final start = Timestamp.fromDate(
          DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0));
      final end   = Timestamp.fromDate(
          DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59));

      final snap = await FirebaseFirestore.instance
          .collection('t_external_orders')
          .where('s_courier', isEqualTo: widget.courierId)
          .where('s_bay', isEqualTo: widget.bayId)
          .where('createdAt', isGreaterThanOrEqualTo: start)
          .where('createdAt', isLessThanOrEqualTo: end)
          .orderBy('createdAt', descending: true)
          .get();

      final list = snap.docs.map((d) => {'_id': d.id, ...d.data()}).toList();
      if (mounted) setState(() { _orders = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Tarih → "YYYY-MM-DD" key
  String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';

  /// Tarihe göre grupla
  Map<String, _DayStats> get _grouped {
    final map = <String, _DayStats>{};
    for (final o in _orders) {
      final ts = o['createdAt'];
      DateTime dt;
      if (ts is Timestamp) {
        dt = ts.toDate();
      } else {
        continue;
      }
      final key = _dayKey(dt);
      map.putIfAbsent(key, () => _DayStats(date: DateTime(dt.year, dt.month, dt.day)));
      map[key]!.add(o);
    }
    // Tarihe göre azalan sırala
    final sorted = map.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Map.fromEntries(sorted);
  }

  // Özet istatistikler
  int get _totalRecords  => _orders.length;
  int get _totalPackages => _orders.fold(0, (s, o) => s + ((o['s_package_count'] as int?) ?? 0));
  int get _approved      => _orders.where((o) => o['s_status'] == 'approved').length;
  int get _rejected      => _orders.where((o) => o['s_status'] == 'rejected').length;
  int get _pending       => _orders.where((o) => o['s_status'] == 'pending').length;
  double get _approvalRate => _totalRecords == 0 ? 0 : _approved / _totalRecords;

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _kPrimary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { _startDate = picked.start; _endDate = picked.end; });
      _load();
    }
  }

  String _formatDay(DateTime dt) {
    const months = ['Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara'];
    const days   = ['Pzt','Sal','Çar','Per','Cum','Cmt','Paz'];
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Sistem Dışı Raporlarım',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF60A5FA), Color(0xFF2563EB)]),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Tarih seçici
          _DateRangeBar(
            start: _startDate,
            end: _endDate,
            onTap: _pickDateRange,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 3))
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _load)
                    : _orders.isEmpty
                        ? _EmptyView(start: _startDate, end: _endDate)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                            children: [
                              // Özet kartlar
                              _SummaryGrid(
                                totalRecords: _totalRecords,
                                totalPackages: _totalPackages,
                                approved: _approved,
                                rejected: _rejected,
                                pending: _pending,
                                approvalRate: _approvalRate,
                              ),
                              const SizedBox(height: 16),
                              // Günlük listesi
                              const Padding(
                                padding: EdgeInsets.only(left: 2, bottom: 10),
                                child: Text('Günlük Dağılım',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _kTextPrimary)),
                              ),
                              ..._grouped.values.map((stats) => _DayCard(stats: stats, formatDay: _formatDay)),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Tarih Aralığı Barı ──
class _DateRangeBar extends StatelessWidget {
  final DateTime start, end;
  final VoidCallback onTap;
  const _DateRangeBar({required this.start, required this.end, required this.onTap});

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2,'0')}.${dt.month.toString().padLeft(2,'0')}.${dt.year}';

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kPrimary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kPrimary.withOpacity(0.2)),
        ),
        child: Row(children: [
          const Icon(Icons.date_range_rounded, color: _kPrimary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${_fmt(start)}  →  ${_fmt(end)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _kPrimary)),
          ),
          const Icon(Icons.expand_more_rounded, color: _kPrimary, size: 20),
        ]),
      ),
    ),
  );
}

// ── Özet Grid ──
class _SummaryGrid extends StatelessWidget {
  final int totalRecords, totalPackages, approved, rejected, pending;
  final double approvalRate;

  const _SummaryGrid({
    required this.totalRecords, required this.totalPackages,
    required this.approved, required this.rejected, required this.pending,
    required this.approvalRate,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(children: [
        Expanded(child: _StatCard(label: 'Toplam Kayıt', value: '$totalRecords', icon: Icons.list_alt_rounded, color: _kPrimary)),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Toplam Paket', value: '$totalPackages', icon: Icons.inventory_2_rounded, color: const Color(0xFF7C3AED))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatCard(label: 'Onaylanan', value: '$approved', icon: Icons.check_circle_rounded, color: _kSuccess)),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Reddedilen', value: '$rejected', icon: Icons.cancel_rounded, color: _kDanger)),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Bekleyen', value: '$pending', icon: Icons.hourglass_top_rounded, color: _kWarning)),
      ]),
      const SizedBox(height: 10),
      _ApprovalRateBar(rate: approvalRate, approved: approved, total: totalRecords),
    ],
  );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kBorder),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: _kTextMuted, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

class _ApprovalRateBar extends StatelessWidget {
  final double rate;
  final int approved, total;
  const _ApprovalRateBar({required this.rate, required this.approved, required this.total});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kBorder),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Onay Oranı', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kTextPrimary)),
          Text('${(rate * 100).toStringAsFixed(0)}%   ($approved / $total)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kSuccess)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: rate,
            minHeight: 8,
            backgroundColor: _kBorder,
            valueColor: const AlwaysStoppedAnimation(_kSuccess),
          ),
        ),
      ],
    ),
  );
}

// ── Günlük Kart ──
class _DayCard extends StatelessWidget {
  final _DayStats stats;
  final String Function(DateTime) formatDay;
  const _DayCard({required this.stats, required this.formatDay});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kBorder),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        // Tarih
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _kPrimary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Text('${stats.date.day}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _kPrimary)),
                Text(['Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara'][stats.date.month - 1],
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kPrimary)),
              ]),
            ),
          ],
        ),
        const SizedBox(width: 14),
        // İstatistikler
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatDay(stats.date),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _kTextPrimary)),
              const SizedBox(height: 6),
              Row(children: [
                _MiniStat(count: stats.totalPackages, label: 'paket', color: _kPrimary),
                const SizedBox(width: 8),
                _MiniStat(count: stats.approved, label: 'onay', color: _kSuccess),
                const SizedBox(width: 8),
                _MiniStat(count: stats.rejected, label: 'red', color: _kDanger),
                const SizedBox(width: 8),
                if (stats.pending > 0)
                  _MiniStat(count: stats.pending, label: 'bekl.', color: _kWarning),
              ]),
            ],
          ),
        ),
        // Kayıt sayısı
        Column(
          children: [
            Text('${stats.count}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _kTextPrimary)),
            const Text('kayıt', style: TextStyle(fontSize: 11, color: _kTextMuted)),
          ],
        ),
      ]),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  const _MiniStat({required this.count, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text('$count $label',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
  );
}

// ── Günlük İstatistik Modeli ──
class _DayStats {
  final DateTime date;
  int count = 0;
  int totalPackages = 0;
  int approved = 0;
  int rejected = 0;
  int pending  = 0;

  _DayStats({required this.date});

  void add(Map<String, dynamic> order) {
    count++;
    totalPackages += (order['s_package_count'] as int?) ?? 0;
    final status = order['s_status'] as String? ?? 'pending';
    if (status == 'approved')      approved++;
    else if (status == 'rejected') rejected++;
    else                           pending++;
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 52, color: Colors.red.shade300),
        const SizedBox(height: 12),
        Text('Hata oluştu', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade700)),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _kTextMuted, fontSize: 13)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Tekrar Dene'),
        ),
      ]),
    ),
  );
}

class _EmptyView extends StatelessWidget {
  final DateTime start, end;
  const _EmptyView({required this.start, required this.end});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _kPrimary.withOpacity(0.08), shape: BoxShape.circle),
        child: const Icon(Icons.bar_chart_rounded, size: 48, color: _kPrimary),
      ),
      const SizedBox(height: 16),
      const Text('Kayıt Bulunamadı', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _kTextPrimary)),
      const SizedBox(height: 6),
      const Text('Seçili tarih aralığında giriş bulunamadı.',
        style: TextStyle(color: _kTextMuted, fontSize: 13)),
    ]),
  );
}
