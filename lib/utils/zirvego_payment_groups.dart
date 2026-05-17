/// Zirvego ödeme kovaları — `app/utils/paymentMap.js` içindeki
/// `ZIRVEGO_PAYMENT_IDS` ve `PAYMENT_GROUPS` ile senkron tutulmalı.
class ZirvegoPaymentGroups {
  ZirvegoPaymentGroups._();

  /// s_odeme_id → görünen ad (paymentMap.js `ZIRVEGO_PAYMENT_IDS`)
  static const Map<int, String> idToDisplayName = {
    4: 'Nakit',
    5: 'Kredi Kartı',
    6: 'Online',
    7: 'Ticket',
    8: 'Ticket Online',
    9: 'Multinet',
    10: 'Multinet Online',
    11: 'Sodexo',
    12: 'Sodexo Online',
    13: 'SetCard',
    14: 'SetCard Online',
    15: 'Metropol',
    16: 'TokenFlex',
    17: 'Paye',
    18: 'CIO',
    19: 'Pluxee',
    20: 'Pluxee Online',
    21: 'IWallet',
    22: 'Winwin POS',
    23: 'Cüzdan',
    24: 'Yemekmatik',
    25: 'Iyzico Online',
    26: 'Multinet QR Kod',
    27: 'Ticket QR Kod',
    28: 'SetCard QR Kod',
    29: 'Metropol QR Kod',
    30: 'Paye QR Kod',
    31: 'TokenFlex QR Kod',
  };

  /// Grup anahtarı → o gruptaki Zirvego `s_odeme_id` listesi (paymentMap.js `PAYMENT_GROUPS`)
  static const Map<String, List<int>> groupIds = {
    'nakit': [4],
    'kKart': [
      5,
      7,
      9,
      11,
      13,
      15,
      16,
      17,
      18,
      19,
      21,
      22,
      24,
      26,
      27,
      28,
      29,
      30,
      31,
    ],
    'online': [6, 8, 10, 12, 14, 20, 25],
    'diger': [23],
  };

  static final Map<int, String> _idToGroupKey = _buildIdToGroupKey();

  static Map<int, String> _buildIdToGroupKey() {
    final m = <int, String>{};
    groupIds.forEach((key, ids) {
      for (final id in ids) {
        m[id] = key;
      }
    });
    return m;
  }

  /// Bilinmeyen id için `null`.
  static String? groupKeyForOdemeId(int? id) {
    if (id == null) return null;
    return _idToGroupKey[id];
  }

  static bool isNakitId(int id) => groupKeyForOdemeId(id) == 'nakit';

  static bool isKKartId(int id) => groupKeyForOdemeId(id) == 'kKart';

  static bool isOnlineId(int id) => groupKeyForOdemeId(id) == 'online';

  static bool isDigerId(int id) => groupKeyForOdemeId(id) == 'diger';

  /// Kapıda kart / yemek çeki / POS kanalı — seçim listesi (ada göre sıralı).
  static List<MapEntry<int, String>> get kapidaKartPickerItems {
    final ids = groupIds['kKart']!;
    final list = ids
        .map((id) => MapEntry(id, idToDisplayName[id] ?? 'ID $id'))
        .toList();
    list.sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return list;
  }

  /// `ss_paytype`: 0 nakit, 1 kapıda kart/çek, 2 online. Karma (3) veya bilinmeyen → null.
  /// Kapıda kartta [kKartOdemeId] `kKart` grubundan olmalı; aksi halde 5 (Kredi Kartı).
  static Map<String, dynamic>? firestoreOdemeFieldsForSsPaytype(
    int ssPaytype, {
    int? kKartOdemeId,
  }) {
    switch (ssPaytype) {
      case 0:
        return {
          's_odeme_id': 4,
          's_odeme_adi': idToDisplayName[4] ?? 'Nakit',
        };
      case 1:
        final id = (kKartOdemeId != null && isKKartId(kKartOdemeId))
            ? kKartOdemeId
            : 5;
        return {
          's_odeme_id': id,
          's_odeme_adi': idToDisplayName[id] ?? 'Kredi Kartı',
        };
      case 2:
        return {
          's_odeme_id': 6,
          's_odeme_adi': idToDisplayName[6] ?? 'Online',
        };
      case 3:
        if (kKartOdemeId != null &&
            isKKartId(kKartOdemeId)) {
          return {
            's_odeme_id': kKartOdemeId,
            's_odeme_adi': idToDisplayName[kKartOdemeId] ?? 'Kredi Kartı',
          };
        }
        return null;
      default:
        return null;
    }
  }
}
