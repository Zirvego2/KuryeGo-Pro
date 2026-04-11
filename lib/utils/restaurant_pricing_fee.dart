// Restoran bazlı kurye ücreti — web lib/restaurantPricing.js calculateRestaurantPricingFee ile uyumlu.

class RestaurantWorkPricing {
  final double sabitUcret;
  final double? maxKm;
  final double kmBasiUcret;
  final double bonus;

  const RestaurantWorkPricing({
    required this.sabitUcret,
    this.maxKm,
    required this.kmBasiUcret,
    required this.bonus,
  });

  factory RestaurantWorkPricing.fromFirestore(Map<String, dynamic> data) {
    final maxRaw = data['max_km'];
    return RestaurantWorkPricing(
      sabitUcret: (data['sabit_ucret'] as num?)?.toDouble() ?? 0,
      maxKm: maxRaw == null ? null : (maxRaw as num?)?.toDouble(),
      kmBasiUcret: (data['km_basi_ucret'] as num?)?.toDouble() ?? 0,
      bonus: (data['bonus'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RestaurantPricingFeeResult {
  final double totalEarnings;
  final double baseEarnings;
  final double kmEarnings;
  final double extraKm;
  final double extraKmEarnings;

  const RestaurantPricingFeeResult({
    required this.totalEarnings,
    required this.baseEarnings,
    required this.kmEarnings,
    required this.extraKm,
    required this.extraKmEarnings,
  });
}

RestaurantPricingFeeResult calculateRestaurantPricingFee(
  RestaurantWorkPricing? pricing,
  double distance,
) {
  if (pricing == null) {
    return const RestaurantPricingFeeResult(
      totalEarnings: 0,
      baseEarnings: 0,
      kmEarnings: 0,
      extraKm: 0,
      extraKmEarnings: 0,
    );
  }

  final sabitUcret = pricing.sabitUcret;
  final kmBasiUcret = pricing.kmBasiUcret;
  final bonus = pricing.bonus;
  final maxKm = pricing.maxKm;

  final baseEarnings = sabitUcret + bonus;

  double kmEarnings = 0;
  double extraKm = 0;
  double extraKmEarnings = 0;

  if (distance > 0 && kmBasiUcret > 0) {
    if (maxKm != null && maxKm > 0) {
      if (distance > maxKm) {
        extraKm = distance - maxKm;
        extraKmEarnings = extraKm * kmBasiUcret;
        kmEarnings = 0;
      } else {
        kmEarnings = 0;
        extraKm = 0;
        extraKmEarnings = 0;
      }
    } else {
      kmEarnings = distance * kmBasiUcret;
      extraKm = 0;
      extraKmEarnings = 0;
    }
  }

  final totalEarnings = baseEarnings + kmEarnings + extraKmEarnings;

  return RestaurantPricingFeeResult(
    totalEarnings: totalEarnings,
    baseEarnings: baseEarnings,
    kmEarnings: kmEarnings,
    extraKm: extraKm,
    extraKmEarnings: extraKmEarnings,
  );
}

double parseOrderDistanceKm(Map<String, dynamic> data) {
  final distanceRaw = data['s_dinstance'];
  if (distanceRaw is String) {
    return double.tryParse(distanceRaw) ?? 0.0;
  }
  if (distanceRaw is num) {
    return distanceRaw.toDouble();
  }
  return 0.0;
}

int? parseWorkId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}

/// Web [pageCourierRestaurantEarnings] ile uyumlu: siparişte paket ücreti yedeği.
double parsePayCurPacketFromOrder(Map<String, dynamic> data) {
  final sPay = data['s_pay'];
  if (sPay is! Map) return 0;
  final raw = sPay['payCurPacket'];
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString()) ?? 0;
}
