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

const _reasonLabels = {
  'kapida_iptal':   'Kapıya giden sipariş iptali',
  'bekleme_suresi': 'İşletmede fazla bekleme süresi',
  'uzak_mesafe':    'Uzak mesafe',
  'diger':          'Diğer',
};

class MyExternalOrdersScreen extends StatefulWidget {
  final int courierId;
  final int bayId;

  const MyExternalOrdersScreen({
    super.key,
    required this.courierId,
    required this.bayId,
  });

  @override
  State<MyExternalOrdersScreen> createState() => _MyExternalOrdersScreenState();
}

class _MyExternalOrdersScreenState extends State<MyExternalOrdersScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  String _statusFilter = 'all';
  String? _error;

  // t_work isim cache
  final Map<int, String> _workNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('t_external_orders')
          .where('s_courier', isEqualTo: widget.courierId)
          .where('s_bay', isEqualTo: widget.bayId)
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();

      final list = snap.docs.map((d) => {'_id': d.id, ...d.data()}).toList();

      // İşletme adlarını topla
      final workIds = list
          .map((o) => o['s_work'])
          .whereType<int>()
          .where((id) => id > 0)
          .toSet();
      await _fetchWorkNames(workIds);

      if (mounted) setState(() { _orders = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _fetchWorkNames(Set<int> ids) async {
    final missing = ids.where((id) => !_workNames.containsKey(id)).toList();
    if (missing.isEmpty) return;
    for (var i = 0; i < missing.length; i += 30) {
      final chunk = missing.sublist(i, (i + 30).clamp(0, missing.length));
      try {
        final snap = await FirebaseFirestore.instance
            .collection('t_work')
            .where('s_id', whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final d = doc.data();
          final rawId = d['s_id'];
          final sid = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
          if (sid != null) _workNames[sid] = d['s_name']?.toString() ?? '';
        }
      } catch (_) {}
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'all') return _orders;
    return _orders.where((o) => o['s_status'] == _statusFilter).toList();
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
          'Sistem Dışı Siparişlerim',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: 'Yenile',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(
            height: 3,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF60A5FA), Color(0xFF2563EB)]),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary, strokeWidth: 3))
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    _FilterBar(
                      selected: _statusFilter,
                      onChanged: (v) => setState(() => _statusFilter = v),
                      counts: {
                        'all':      _orders.length,
                        'pending':  _orders.where((o) => o['s_status'] == 'pending').length,
                        'approved': _orders.where((o) => o['s_status'] == 'approved').length,
                        'rejected': _orders.where((o) => o['s_status'] == 'rejected').length,
                      },
                    ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? _EmptyView(filter: _statusFilter)
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (ctx, i) => _OrderCard(
                                order: _filtered[i],
                                workName: _workNames[_filtered[i]['s_work']] ?? '',
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

// ── Filtre Barı ──
class _FilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  final Map<String, int> counts;

  const _FilterBar({required this.selected, required this.onChanged, required this.counts});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        _Chip(label: 'Tümü',      value: 'all',      count: counts['all']!,      selected: selected, onTap: onChanged, color: _kPrimary),
        const SizedBox(width: 6),
        _Chip(label: 'Bekleyen',  value: 'pending',  count: counts['pending']!,  selected: selected, onTap: onChanged, color: _kWarning),
        const SizedBox(width: 6),
        _Chip(label: 'Onaylı',    value: 'approved', count: counts['approved']!, selected: selected, onTap: onChanged, color: _kSuccess),
        const SizedBox(width: 6),
        _Chip(label: 'Reddedildi',value: 'rejected', count: counts['rejected']!, selected: selected, onTap: onChanged, color: _kDanger),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, value;
  final int count;
  final String selected;
  final ValueChanged<String> onTap;
  final Color color;

  const _Chip({
    required this.label, required this.value, required this.count,
    required this.selected, required this.onTap, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? color : color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Text('$count',
                style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14,
                  color: isSelected ? Colors.white : color,
                ),
              ),
              Text(label,
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sipariş Kartı ──
class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String workName;

  const _OrderCard({required this.order, required this.workName});

  @override
  Widget build(BuildContext context) {
    final status    = order['s_status'] as String? ?? 'pending';
    final reason    = order['s_reason'] as String? ?? '';
    final note      = order['s_note'] as String? ?? '';
    final count     = order['s_package_count'] ?? 0;
    final createTs  = order['createdAt'];
    final work      = order['s_work'];
    final rejReason = order['s_rejected_reason'] as String? ?? '';
    final displayWork = workName.isNotEmpty ? workName : (work != null ? 'İşletme #$work' : '-');

    final createDate = createTs is Timestamp
        ? createTs.toDate()
        : (createTs is DateTime ? createTs : null);
    final dateStr = createDate != null
        ? '${createDate.day.toString().padLeft(2,'0')}.${createDate.month.toString().padLeft(2,'0')}.${createDate.year}  ${createDate.hour.toString().padLeft(2,'0')}:${createDate.minute.toString().padLeft(2,'0')}'
        : '-';

    final (statusLabel, statusColor, statusIcon) = switch (status) {
      'approved' => ('Onaylandı', _kSuccess, Icons.check_circle_rounded),
      'rejected' => ('Reddedildi', _kDanger, Icons.cancel_rounded),
      _          => ('Bekliyor', _kWarning, Icons.hourglass_top_rounded),
    };

    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Başlık
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(children: [
              Icon(Icons.store_rounded, size: 15, color: _kPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(displayWork,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _kTextPrimary),
                  overflow: TextOverflow.ellipsis),
              ),
              Icon(statusIcon, size: 15, color: statusColor),
              const SizedBox(width: 4),
              Text(statusLabel,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor)),
            ]),
          ),
          // İçerik
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _InfoPill(icon: Icons.inventory_2_rounded, label: '$count paket', color: _kPrimary),
                  const SizedBox(width: 8),
                  _InfoPill(icon: Icons.schedule_rounded, label: dateStr, color: _kTextMuted),
                ]),
                const SizedBox(height: 8),
                if (reason.isNotEmpty)
                  _InfoRow(icon: Icons.help_outline_rounded, color: _kWarning,
                    label: _reasonLabels[reason] ?? reason),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _InfoRow(icon: Icons.notes_rounded, color: _kTextMuted, label: note),
                ],
                if (status == 'rejected' && rejReason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kDanger.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kDanger.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded, size: 14, color: _kDanger),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Red nedeni: $rejReason',
                        style: TextStyle(fontSize: 12, color: _kDanger, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _InfoRow({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: _kTextMuted))),
    ],
  );
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
  final String filter;
  const _EmptyView({required this.filter});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _kPrimary.withOpacity(0.08), shape: BoxShape.circle),
        child: const Icon(Icons.inbox_rounded, size: 48, color: _kPrimary),
      ),
      const SizedBox(height: 16),
      const Text('Kayıt Yok', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _kTextPrimary)),
      const SizedBox(height: 6),
      Text(
        filter == 'all' ? 'Henüz sistem dışı paket girişi yapmadınız.' : 'Bu filtrede kayıt bulunamadı.',
        style: const TextStyle(color: _kTextMuted, fontSize: 13),
      ),
    ]),
  );
}
