import 'package:flutter/material.dart';

import '../utils/zirvego_payment_groups.dart';

IconData _iconForOdemeId(int id) {
  switch (id) {
    case 5:
      return Icons.credit_card_rounded;
    case 7:
    case 27:
      return Icons.restaurant_menu_rounded;
    case 9:
    case 26:
      return Icons.account_balance_wallet_rounded;
    case 11:
    case 12:
      return Icons.lunch_dining_rounded;
    case 13:
    case 28:
      return Icons.style_rounded;
    case 15:
    case 29:
      return Icons.hub_rounded;
    case 16:
    case 31:
      return Icons.contactless_rounded;
    case 17:
    case 30:
      return Icons.payment_rounded;
    case 18:
      return Icons.memory_rounded;
    case 19:
      return Icons.card_membership_rounded;
    case 21:
      return Icons.smartphone_rounded;
    case 22:
      return Icons.point_of_sale_rounded;
    case 24:
      return Icons.fastfood_rounded;
    default:
      if (id >= 26 && id <= 31) return Icons.qr_code_2_rounded;
      return Icons.payments_rounded;
  }
}

/// Kapıda kart/çek türü — modern liste; `s_odeme_id` döner.
Future<int?> showKapidaOdemeTuruPickerDialog(
  BuildContext context, {
  required int currentId,
}) async {
  final items = ZirvegoPaymentGroups.kapidaKartPickerItems;
  final maxH = MediaQuery.sizeOf(context).height * 0.74;

  return showDialog<int>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 400,
          height: maxH.clamp(320.0, 620.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1D4ED8),
                      Color(0xFF2563EB),
                      Color(0xFF3B82F6),
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.category_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Kapıda ödeme türü',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Gerçek tahsilat türünü seçin',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                          tooltip: 'Kapat',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    indent: 76,
                    endIndent: 16,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (context, i) {
                    final e = items[i];
                    final selected = e.key == currentId;
                    final icon = _iconForOdemeId(e.key);

                    return Material(
                      color: selected
                          ? const Color(0xFFEFF6FF)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, e.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFF2563EB)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFF2563EB)
                                        : Colors.grey.shade300,
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: Icon(
                                  icon,
                                  size: 24,
                                  color: selected
                                      ? Colors.white
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.value,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade900,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'Kod ${e.key}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.grey.shade700,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons
                                        .radio_button_unchecked_rounded,
                                size: 26,
                                color: selected
                                    ? const Color(0xFF2563EB)
                                    : Colors.grey.shade400,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  'Seçtiğiniz tür sipariş kaydına yansıtılır.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
