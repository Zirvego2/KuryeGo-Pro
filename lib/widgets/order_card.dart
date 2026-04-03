import 'package:flutter/material.dart';
import '../models/order_model.dart';

/// Sipariş Kartı Widget
/// React Native home_Footer.js card tasarımı karşılığı
class OrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;
  final String? dynamicWorkName;

  const OrderCard({
    super.key,
    required this.order,
    required this.onTap,
    this.dynamicWorkName,
  });

  @override
  Widget build(BuildContext context) {
    final isPreparing = order.sStat == 4; // ⭐ Hazırlanıyor
    final isWaitingForPickup = order.sStat == 0 && order.sCourierAccepted == true; // ⭐ Düzeltildi
    final isPendingApproval = order.sStat == 0 && 
        (order.sCourierAccepted == null || order.sCourierAccepted == false);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        height: 250,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFBFDFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.19),
              offset: const Offset(0, 10),
              blurRadius: 20,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header (Gradient + Rounded)
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isPreparing
                      ? [const Color(0xFFFF9800), const Color(0xFFFF9800)] // ⭐ Turuncu - Hazırlanıyor
                      : isWaitingForPickup
                          ? [const Color(0xFFFF0019), const Color(0xFFFF0019)] // Kırmızı - Teslim Al
                          : [const Color(0xFF107BFF), const Color(0xFF63AEFF)], // Mavi - Teslim Et
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(100),
                ),
              ),
              child: Stack(
                children: [
                  // ⭐ HAZIRLANIYOR Badge
                  if (isPreparing)
                    Positioned(
                      top: 5,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.restaurant,
                                size: 12, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'HAZIRLANIYOR',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // ONAY BEKLİYOR Badge
                  if (isPendingApproval)
                    Positioned(
                      top: 5,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_active,
                                size: 12, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'ONAY BEKLİYOR',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // İçerik
                  Padding(
                    padding: const EdgeInsets.only(left: 10, top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        // Restoran adı
                        _buildInfoRow(
                          icon: Icons.restaurant_menu,
                          text: (dynamicWorkName != null && dynamicWorkName!.isNotEmpty)
                              ? dynamicWorkName!
                              : (order.sNameWork.isEmpty ? 'İşletme' : order.sNameWork),
                          fontSize: 14,
                        ),
                        const SizedBox(height: 8),
                        // Müşteri adı
                        _buildInfoRow(
                          icon: Icons.person,
                          text: order.ssFullname,
                          fontSize: 12,
                        ),
                        const SizedBox(height: 8),
                        // Saat
                        _buildInfoRow(
                          icon: Icons.schedule,
                          text: order.sCdate != null
                              ? '${order.sCdate!.hour.toString().padLeft(2, '0')}:${order.sCdate!.minute.toString().padLeft(2, '0')}'
                              : '00:00',
                          fontSize: 11,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Adres bölümü
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFFE0E0E0), width: 2),
                  ),
                ),
                child: Text(
                  order.ssAdres,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black87,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Alt butonlar
            Container(
              height: 50,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE0E0E0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  // Teslim al/et butonu
                  Expanded(
                    child: Center(
                      child: Text(
                        isPreparing
                            ? 'SİPARİŞ HAZIRLANIYOR' // ⭐ Yeni durum
                            : isPendingApproval
                                ? 'ONAYLA'
                                : isWaitingForPickup
                                    ? 'TESLİM AL'
                                    : 'TESLİM ET',
                        style: TextStyle(
                          fontSize: isPreparing ? 10 : 12, // ⭐ Uzun text için küçük font
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF007BFF),
                        ),
                      ),
                    ),
                  ),
                  // Dikey çizgi
                  Container(
                    width: 1,
                    height: 50,
                    color: const Color(0xFFE0E0E0),
                  ),
                  // Konum butonu
                  SizedBox(
                    width: 50,
                    child: Center(
                      child: Icon(
                        Icons.location_on,
                        color: Colors.white.withOpacity(0.8),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String text,
    required double fontSize,
  }) {
    return Row(
      children: [
        // Icon container
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: fontSize + 2,
            color: const Color(0xFF007BFF),
          ),
        ),
        const SizedBox(width: 6),
        // Text
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

