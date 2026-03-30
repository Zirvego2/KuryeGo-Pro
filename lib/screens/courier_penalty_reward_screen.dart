import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Kuryenin kendisine tanımlanan ceza ve ödül kayıtları (t_courier_penalty_reward)
class CourierPenaltyRewardScreen extends StatefulWidget {
  final int courierId;
  final int bayId;

  const CourierPenaltyRewardScreen({
    super.key,
    required this.courierId,
    required this.bayId,
  });

  @override
  State<CourierPenaltyRewardScreen> createState() =>
      _CourierPenaltyRewardScreenState();
}

class _CourierPenaltyRewardScreenState
    extends State<CourierPenaltyRewardScreen> {
  bool _loading = true;
  String? _error;
  /// Seçilen günün tüm kayıtları (ceza + ödül); sekme ile süzülür
  List<Map<String, dynamic>> _items = [];

  /// Takvim günü (yerel saat, saat bilgisi yok sayılır)
  late DateTime _selectedDay;

  /// true: ceza, false: ödül
  bool _showPenalty = true;

  static final _df = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');
  static final _dayFmt = DateFormat('d MMMM yyyy', 'tr_TR');

  @override
  void initState() {
    super.initState();
    _selectedDay = _dateOnly(DateTime.now());
    _load();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDay = _dateOnly(picked));
      _load();
    }
  }

  void _shiftDay(int delta) {
    setState(() {
      _selectedDay = _dateOnly(_selectedDay.add(Duration(days: delta)));
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final start = _selectedDay;
      final end = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        23,
        59,
        59,
        999,
      );
      final startTs = Timestamp.fromDate(start);
      final endTs = Timestamp.fromDate(end);

      final snap = await FirebaseFirestore.instance
          .collection('t_courier_penalty_reward')
          .where('s_bay', isEqualTo: widget.bayId)
          .where('s_courier', isEqualTo: widget.courierId)
          .where('createdAt', isGreaterThanOrEqualTo: startTs)
          .where('createdAt', isLessThanOrEqualTo: endTs)
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();

      final list = snap.docs
          .map((d) => <String, dynamic>{'_docId': d.id, ...d.data()})
          .toList();
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visible {
    final type = _showPenalty ? 'penalty' : 'reward';
    return _items.where((e) => e['entry_type'] == type).toList();
  }

  int _countVisible() => _visible.length;

  int _sumPacketVisible() {
    return _visible.fold<int>(
      0,
      (s, e) => s + ((e['packet_delta'] as num?)?.toInt() ?? 0),
    );
  }

  String _ts(dynamic v) {
    if (v == null) return '—';
    if (v is Timestamp) return _df.format(v.toDate());
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Ödül & Ceza',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ceza | Ödül
                Row(
                  children: [
                    Expanded(
                      child: _kindButton(
                        label: 'Ceza',
                        selected: _showPenalty,
                        color: Colors.red,
                        onTap: () {
                          if (!_showPenalty) {
                            setState(() => _showPenalty = true);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _kindButton(
                        label: 'Ödül',
                        selected: !_showPenalty,
                        color: Colors.green,
                        onTap: () {
                          if (_showPenalty) {
                            setState(() => _showPenalty = false);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Tarih: seçilen günün 00:00–23:59
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _loading
                            ? null
                            : () => _shiftDay(-1),
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Önceki gün',
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: _loading ? null : _pickDate,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                Text(
                                  _dayFmt.format(_selectedDay),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'Bu günün kayıtları (24 saat)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _loading ||
                                _dateOnly(_selectedDay) ==
                                    _dateOnly(DateTime.now())
                            ? null
                            : () => _shiftDay(1),
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Sonraki gün',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 48, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _load,
                                child: const Text('Tekrar dene'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            _buildSummary(),
                            const SizedBox(height: 16),
                            if (visible.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 48),
                                child: Column(
                                  children: [
                                    Icon(Icons.inbox_outlined,
                                        size: 56, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      _showPenalty
                                          ? 'Bu gün için ceza kaydı yok.'
                                          : 'Bu gün için ödül kaydı yok.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ...visible.map(_buildCard),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _kindButton({
    required String label,
    required bool selected,
    required MaterialColor color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? color.shade600 : Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: selected ? 2 : 0,
        shadowColor: color.withValues(alpha: 0.35),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color.shade700 : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: selected ? Colors.white : color.shade800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final n = _countVisible();
    final sum = _sumPacketVisible();
    final isPen = _showPenalty;
    final sumLabel = isPen ? '$sum paket' : '+$sum paket';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _miniStat(
              'Kayıt',
              '$n',
              isPen ? Colors.red.shade700 : Colors.green.shade700,
            ),
          ),
          Container(width: 1, height: 36, color: Colors.grey.shade200),
          Expanded(
            child: _miniStat(
              'Paket',
              sumLabel,
              isPen ? Colors.orange.shade900 : Colors.teal.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String title, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> row) {
    final isPenalty = row['entry_type'] == 'penalty';
    final badgeBg = isPenalty ? Colors.red.shade50 : Colors.green.shade50;
    final badgeFg = isPenalty ? Colors.red.shade800 : Colors.green.shade800;
    final label = isPenalty ? 'CEZA' : 'ÖDÜL';
    final delta = (row['packet_delta'] as num?)?.toInt();
    String deltaStr;
    if (delta == null) {
      deltaStr = '—';
    } else if (delta > 0) {
      deltaStr = '+$delta paket';
    } else {
      deltaStr = '$delta paket';
    }

    String? lateLine;
    if (isPenalty &&
        row['late_value'] != null &&
        (row['late_value'] is num) &&
        (row['late_value'] as num) > 0) {
      final u = row['late_unit'] == 'hours' ? 'saat' : 'dk';
      lateLine = 'Geç kalma: ${row['late_value']} $u';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeFg,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                deltaStr,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isPenalty ? Colors.red.shade700 : Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            row['description']?.toString() ?? '—',
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 10),
          Text(
            'Kayıt: ${_ts(row['createdAt'])}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (isPenalty && row['incident_at'] != null) ...[
            const SizedBox(height: 4),
            Text(
              'Olay zamanı: ${_ts(row['incident_at'])}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          if (lateLine != null) ...[
            const SizedBox(height: 4),
            Text(
              lateLine,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
          if (row['created_by_name'] != null &&
              row['created_by_name'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Kaydeden: ${row['created_by_name']}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}
