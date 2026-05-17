import 'firestore_coercion.dart';
import 'zirvego_payment_groups.dart';

/// Teslim edilmiş siparişte işletmeye iade kapsamındaki nakit / kapıda kart tutarları.
/// [zirvego_payment_groups] ile `s_odeme_id` grupları; `s_pay` parçalı ödeme alanları.
class OrderHandoverAmounts {
  OrderHandoverAmounts._();

  static double _dbl(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  /// Firestore `t_orders` map — `cash` ve `card` kolonları (işletmeye teslim mahsubu).
  static Map<String, double> cashAndCardFromOrderMap(Map<String, dynamic> data) {
    final sPay = data['s_pay'] as Map<String, dynamic>?;
    final ssPaytype = coerceFirestoreInt(sPay?['ss_paytype'] ?? data['ss_paytype'] ?? 0);
    final total = _dbl(sPay?['ss_paycount'] ?? data['ss_paycount']);
    final payCash = _dbl(sPay?['payCash']);
    final payDiv = _dbl(sPay?['ss_paycountdiv']);

    double cash = 0;
    double card = 0;
    switch (ssPaytype) {
      case 0:
        cash = payCash > 0 ? payCash : total;
        break;
      case 1:
        card = total;
        break;
      case 2:
        break;
      case 3:
        cash = payCash > 0 ? payCash : (payDiv > 0 ? total - payDiv : 0);
        card = payDiv > 0 ? payDiv : (payCash > 0 ? total - payCash : 0);
        if (cash < 0) cash = 0;
        if (card < 0) card = 0;
        break;
      default:
        break;
    }

    final odemeId = coerceFirestoreInt(data['s_odeme_id'], 0);
    final hasOdeme = data['s_odeme_id'] != null &&
        data['s_odeme_id'].toString().trim().isNotEmpty &&
        odemeId > 0;

    if (hasOdeme) {
      if (ZirvegoPaymentGroups.isOnlineId(odemeId)) {
        return {'cash': 0, 'card': 0};
      }
      if (ZirvegoPaymentGroups.isDigerId(odemeId)) {
        return {'cash': 0, 'card': 0};
      }
      if (ZirvegoPaymentGroups.isNakitId(odemeId)) {
        return {'cash': cash + card, 'card': 0};
      }
      if (ZirvegoPaymentGroups.isKKartId(odemeId)) {
        final cardTotal = card > 0 ? card : (cash > 0 ? total - cash : total);
        return {'cash': cash, 'card': cardTotal};
      }
    }

    return {'cash': cash, 'card': card};
  }
}
