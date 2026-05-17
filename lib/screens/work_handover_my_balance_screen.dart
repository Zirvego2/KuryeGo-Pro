import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/courier_work_handover_service.dart';
import '../services/firebase_service.dart';

/// Kuryenin işletmelere gönderdiği teslim bildirimleri (onay bekleyen / onaylı / red).
class WorkHandoverMyBalanceScreen extends StatefulWidget {
  final int courierId;
  final int bayId;

  const WorkHandoverMyBalanceScreen({
    super.key,
    required this.courierId,
    required this.bayId,
  });

  @override
  State<WorkHandoverMyBalanceScreen> createState() => _WorkHandoverMyBalanceScreenState();
}

class _WorkHandoverMyBalanceScreenState extends State<WorkHandoverMyBalanceScreen> {
  static const Color _surface = Color(0xFFF8FAFC);

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

  String _fmt(double v) => NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2).format(v);

  double _num(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;

  String _statusTr(String s) {
    switch (s.toLowerCase()) {
      case 'submitted':
        return 'Bekliyor';
      case 'approved':
        return 'Onaylandı';
      case 'rejected':
        return 'Reddedildi';
      default:
        return s;
    }
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
        appBar: AppBar(
          title: const Text('Teslim ettiğim bakiye'),
          elevation: 0,
          backgroundColor: _surface,
          foregroundColor: Colors.black87,
          surfaceTintColor: Colors.transparent,
        ),
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
        title: const Text('Teslim ettiğim bakiye', style: TextStyle(fontSize: 17)),
        elevation: 0,
        toolbarHeight: 48,
        backgroundColor: _surface,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Gönderdiğiniz nakit ve kart beyanlarının durumu. İşletme onayı veya red bilgisi burada görünür.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.35),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: CourierWorkHandoverService.watchMyHandovers(
                courierId: widget.courierId,
                bayId: widget.bayId,
              ),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Liste yüklenemedi: ${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz teslim bildiriminiz yok.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'İşletme bazlı teslim ekranından bildirim gönderebilirsiniz.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final d = docs[i].data();
                    final st = d['status']?.toString() ?? '';
                    final wn = d['work_name']?.toString() ?? '';
                    final ts = d['submitted_at'];
                    String tss = '-';
                    if (ts is Timestamp) {
                      tss = DateFormat('dd.MM.yyyy HH:mm').format(ts.toDate());
                    }
                    final stLabel = _statusTr(st);
                    final ok = st.toLowerCase() == 'approved';
                    final wait = st.toLowerCase() == 'submitted';
                    final bad = st.toLowerCase() == 'rejected';
                    return Material(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minLeadingWidth: 36,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: ok
                              ? Colors.green.shade100
                              : bad
                                  ? Colors.red.shade100
                                  : Colors.amber.shade100,
                          child: Icon(
                            ok ? Icons.check : bad ? Icons.close : Icons.schedule,
                            size: 18,
                            color: ok ? Colors.green.shade800 : bad ? Colors.red.shade800 : Colors.amber.shade900,
                          ),
                        ),
                        title: Text(
                          wn.isEmpty ? 'İşletme' : wn,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${_fmt(_num(d['declared_cash']))} nakit · ${_fmt(_num(d['declared_card']))} kart · $tss',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: wait ? Colors.amber.shade50 : ok ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            stLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: wait ? Colors.amber.shade900 : ok ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
