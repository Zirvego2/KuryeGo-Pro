import 'package:flutter/material.dart';
import '../models/order_model.dart';

/// 🎨 Modern & Kurumsal Sipariş Kartı
class ModernOrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;

  const ModernOrderCard({
    super.key,
    required this.order,
    required this.onTap,
  });

  Color _getStatusBasedColor() {
    // ⭐ Platform bazlı renkler YOK - Durum bazlı renkler kullanılıyor
    final isPreparing = order.sStat == 4; // ⭐ Hazırlanıyor
    final isWaitingForApproval = order.sStat == 0 && 
        (order.sCourierAccepted == null || order.sCourierAccepted == false);
    final isApproved = order.sStat == 0 && order.sCourierAccepted == true;
    final isOnTheWay = order.sStat == 1;

    if (isPreparing) {
      return const Color(0xFFFF9800); // ⭐ Hazırlanıyor - TURUNCU
    } else if (isWaitingForApproval) {
      return const Color(0xFFFFC107); // Onay bekliyor - SARI
    } else if (isApproved) {
      return const Color(0xFF4CAF50); // Onaylandı - YEŞİL
    } else if (isOnTheWay) {
      return const Color(0xFF2196F3); // Yolda - MAVİ
    } else {
      return const Color(0xFF757575); // Diğer durumlar - GRİ
    }
  }

  IconData _getPlatformIcon() {
    switch (order.sOrderscr) {
      case 1:
        return Icons.delivery_dining;
      case 2:
        return Icons.restaurant;
      case 3:
        return Icons.shopping_bag;
      case 4:
        return Icons.shopping_cart;
      default:
        return Icons.local_shipping;
    }
  }

  String _getPlatformName() {
    switch (order.sOrderscr) {
      case 1:
        return 'Getir';
      case 2:
        return 'YemekSepeti';
      case 3:
        return 'Trendyol';
      case 4:
        return 'Migros';
      default:
        return 'Diğer';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 5. Düzeltme: Onay sistemi
    final isPreparing = order.sStat == 4; // ⭐ Hazırlanıyor
    final isWaitingForApproval = order.sStat == 0 && (order.sCourierAccepted == null || order.sCourierAccepted == false);
    final isWaitingForPickup = order.sStat == 0 && order.sCourierAccepted == true;
    final isOnDelivery = order.sStat == 1;
    final statusColor = _getStatusBasedColor(); // ⭐ Durum bazlı renk

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 165, // ⭐ 200 → 165 (Ekrana 2 kart sığacak)
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - Status Badge
            Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    statusColor,
                    statusColor.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Stack(
                children: [
                  // Onay badge (5. Düzeltme)
                  if (isWaitingForApproval)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.notifications_active,
                              size: 12,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'ONAY BEKLİYOR',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // Platform info
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _getPlatformIcon(),
                            color: statusColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 6. Düzeltme: Restoran ismi göster
                              Text(
                                order.sRestaurantName ?? order.sNameWork,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _getPlatformName(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Restoran
                    Row(
                      children: [
                        Icon(
                          Icons.store,
                          size: 16,
                          color: statusColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            // ⭐ Telefon siparişi için fallback
                            (order.sRestaurantName?.isEmpty ?? true) && (order.sNameWork.isEmpty)
                                ? (order.sOrderscr == 0 ? 'Telefon Siparişi' : 'Restoran')
                                : (order.sRestaurantName ?? order.sNameWork),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF212121),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Müşteri
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: Color(0xFF757575),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            order.ssFullname,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF424242),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Adres (⭐ s_stat=0 veya 4 ise gizle)
                    if (order.sStat != 0 && order.sStat != 4)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Color(0xFF757575),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                order.ssAdres,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF616161),
                                  height: 1.3,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Expanded(
                        child: Center(
                          child: Text(
                            order.sStat == 4 
                                ? '⏳ Hazırlanıyor...'
                                : '🔒 Onay Bekliyor',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9E9E9E),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 10),
                    
                    // Tutar & Saat
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.payments,
                                size: 14,
                                color: Color(0xFF4CAF50),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '₺${order.ssPaycount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4CAF50),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          order.sCdate != null
                              ? '${order.sCdate!.hour.toString().padLeft(2, '0')}:${order.sCdate!.minute.toString().padLeft(2, '0')}'
                              : '--:--',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Footer Button (5. Düzeltme: Onay → Teslim Al → Teslim Et)
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: isPreparing
                    ? const Color(0xFFFF9800) // ⭐ Turuncu - Hazırlanıyor
                    : isWaitingForApproval
                        ? const Color(0xFFFFC107) // Sarı - Onayla
                        : isWaitingForPickup
                            ? const Color(0xFF4CAF50) // Yeşil - Teslim Al
                            : const Color(0xFF2196F3), // Mavi - Teslim Et
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Center(
                child: Text(
                  isPreparing
                      ? 'SİPARİŞ HAZIRLANIYOR' // ⭐ Yeni durum
                      : isWaitingForApproval
                          ? 'ONAYLA'
                          : isWaitingForPickup
                              ? 'TESLİM AL'
                              : 'TESLİM ET',
                  style: TextStyle(
                    fontSize: isPreparing ? 11 : 14, // ⭐ Uzun text için küçük font
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

