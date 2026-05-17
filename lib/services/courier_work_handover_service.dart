import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/order_handover_amounts.dart';

/// İşletme bazlı kurye teslim bildirimleri — [t_courier_work_handovers].
class CourierWorkHandoverService {
  CourierWorkHandoverService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String collectionName = 't_courier_work_handovers';

  /// Onay bekleyen veya onaylanmış teslim kayıtlarındaki sipariş doc id'leri.
  /// [rejected] hariç — reddedilen kayıttaki siparişler yeniden teslime dahil edilir.
  static Future<Set<String>> _reservedOrderDocIds({
    required int courierId,
    required int bayId,
  }) async {
    final snap = await _db
        .collection(collectionName)
        .where('courier_id', isEqualTo: courierId)
        .where('bay_id', isEqualTo: bayId)
        .where('status', whereIn: ['submitted', 'approved'])
        .limit(500)
        .get();
    final out = <String>{};
    for (final d in snap.docs) {
      final ids = d.data()['order_ids'];
      if (ids is List) {
        for (final id in ids) {
          out.add(id.toString());
        }
      }
    }
    return out;
  }

  /// Tarih aralığında teslim edilmiş siparişleri işletmeye göre grupla;
  /// bekleyen veya onaylı teslim bildiriminde yer alan siparişler hariç.
  static Future<List<WorkHandoverAggregate>> aggregateByWork({
    required int courierId,
    required int bayId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final reserved = await _reservedOrderDocIds(courierId: courierId, bayId: bayId);
    final start = Timestamp.fromDate(periodStart);
    final end = Timestamp.fromDate(periodEnd);
    const pageSize = 200;

    final Map<int, _Agg> map = {};
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
    for (;;) {
      Query<Map<String, dynamic>> q = _db
          .collection('t_orders')
          .where('s_bay', isEqualTo: bayId)
          .where('s_courier', isEqualTo: courierId)
          .where('s_stat', isEqualTo: 2)
          .where('s_ddate', isGreaterThanOrEqualTo: start)
          .where('s_ddate', isLessThanOrEqualTo: end)
          .orderBy('s_ddate')
          .limit(pageSize);
      if (cursor != null) {
        q = q.startAfterDocument(cursor);
      }
      final snap = await q.get();
      if (snap.docs.isEmpty) break;

      for (final doc in snap.docs) {
        if (reserved.contains(doc.id)) continue;
        final data = doc.data();
        final work = (data['s_work'] is int)
            ? data['s_work'] as int
            : int.tryParse('${data['s_work'] ?? 0}') ?? 0;
        final parts = OrderHandoverAmounts.cashAndCardFromOrderMap(data);
        final c = parts['cash'] ?? 0;
        final k = parts['card'] ?? 0;
        if (c <= 0 && k <= 0) continue;

        final name = (data['s_nameWork'] ?? data['s_restaurantName'] ?? 'İşletme $work')
            .toString();
        map.putIfAbsent(work, () => _Agg(workName: name));
        final a = map[work]!;
        a.cash += c;
        a.card += k;
        a.orderDocIds.add(doc.id);
        if (name.isNotEmpty && a.workName.startsWith('İşletme ')) {
          a.workName = name;
        }
      }

      if (snap.docs.length < pageSize) break;
      cursor = snap.docs.last;
    }

    final list = map.entries
        .map((e) => WorkHandoverAggregate(
              workId: e.key,
              workName: e.value.workName,
              cash: e.value.cash,
              card: e.value.card,
              orderDocIds: List<String>.from(e.value.orderDocIds),
            ))
        .toList()
      ..sort((a, b) => a.workId.compareTo(b.workId));
    return _enrichWorkNamesFromTWork(list, bayId);
  }

  /// [t_work]: `isletme_name` veya `s_name` (web ile uyumlu).
  static Future<List<WorkHandoverAggregate>> _enrichWorkNamesFromTWork(
    List<WorkHandoverAggregate> list,
    int bayId,
  ) async {
    final out = <WorkHandoverAggregate>[];
    for (final row in list) {
      if (row.workId <= 0) {
        out.add(row.copyWith(
          workName: row.workName.isEmpty ? 'İşletme atanmamış' : row.workName,
        ));
        continue;
      }
      var name = row.workName;
      try {
        final snap = await _db
            .collection('t_work')
            .where('s_id', isEqualTo: row.workId)
            .limit(25)
            .get();
        Map<String, dynamic>? d;
        if (snap.docs.length == 1) {
          d = snap.docs.first.data();
        } else {
          for (final doc in snap.docs) {
            final sb = doc.data()['s_bay'];
            final bid = sb is int ? sb : int.tryParse('$sb');
            if (bid == bayId) {
              d = doc.data();
              break;
            }
          }
          d ??= snap.docs.isNotEmpty ? snap.docs.first.data() : null;
        }
        if (d != null) {
          final fromWork = (d['isletme_name'] ?? d['s_name'] ?? '').toString().trim();
          if (fromWork.isNotEmpty) name = fromWork;
        }
      } catch (_) {}
      out.add(row.copyWith(workName: name));
    }
    return out;
  }

  static Future<void> submitHandover({
    required int bayId,
    required int courierId,
    required int workId,
    required String workName,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double computedCash,
    required double computedCard,
    required double declaredCash,
    required double declaredCard,
    required List<String> orderDocIds,
  }) async {
    await _db.collection(collectionName).add({
      'bay_id': bayId,
      'courier_id': courierId,
      'work_id': workId,
      'work_name': workName,
      'period_start': Timestamp.fromDate(periodStart),
      'period_end': Timestamp.fromDate(periodEnd),
      'computed_cash': computedCash,
      'computed_card': computedCard,
      'declared_cash': declaredCash,
      'declared_card': declaredCard,
      'status': 'submitted',
      'submitted_at': FieldValue.serverTimestamp(),
      'order_ids': orderDocIds,
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMyHandovers({
    required int courierId,
    required int bayId,
  }) {
    return _db
        .collection(collectionName)
        .where('courier_id', isEqualTo: courierId)
        .where('bay_id', isEqualTo: bayId)
        .orderBy('submitted_at', descending: true)
        .limit(100)
        .snapshots();
  }
}

class WorkHandoverAggregate {
  final int workId;
  final String workName;
  final double cash;
  final double card;
  final List<String> orderDocIds;

  const WorkHandoverAggregate({
    required this.workId,
    required this.workName,
    required this.cash,
    required this.card,
    required this.orderDocIds,
  });

  WorkHandoverAggregate copyWith({
    String? workName,
    double? cash,
    double? card,
    List<String>? orderDocIds,
  }) {
    return WorkHandoverAggregate(
      workId: workId,
      workName: workName ?? this.workName,
      cash: cash ?? this.cash,
      card: card ?? this.card,
      orderDocIds: orderDocIds ?? this.orderDocIds,
    );
  }
}

class _Agg {
  String workName;
  double cash = 0;
  double card = 0;
  final List<String> orderDocIds = [];

  _Agg({required this.workName});
}
