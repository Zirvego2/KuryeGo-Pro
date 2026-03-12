import 'package:flutter/material.dart';
import '../services/shift_log_service.dart';

/// 🎨 Modern & Kurumsal Header Widget
class ModernHeader extends StatefulWidget {
  final String userName;
  final int packageCount;
  final String statusText;
  final int courierStatus;
  final int courierId; // ⭐ Vardiya bilgisi için
  final VoidCallback onShiftPressed; // ⭐ Vardiya menüsü için
  final VoidCallback onProfilePressed;

  const ModernHeader({
    super.key,
    required this.userName,
    required this.packageCount,
    required this.statusText,
    required this.courierStatus,
    required this.courierId, // ⭐ Eklendi
    required this.onShiftPressed, // ⭐ Değişti
    required this.onProfilePressed,
  });

  @override
  State<ModernHeader> createState() => _ModernHeaderState();
}

class _ModernHeaderState extends State<ModernHeader> {
  final ShiftLogService _shiftLogService = ShiftLogService();
  Map<String, dynamic>? _shiftInfo;
  
  @override
  void initState() {
    super.initState();
    _loadShiftInfo();
  }

  Future<void> _loadShiftInfo() async {
    try {
      final shiftInfo = await _shiftLogService.getTodayShiftInfo(widget.courierId);
      if (mounted) {
        setState(() {
          _shiftInfo = shiftInfo;
        });
      }
    } catch (e) {
      print('❌ Vardiya bilgisi yükleme hatası: $e');
    }
  }

  Color _getStatusColor() {
    // ⭐ Kurye statusu (t_courier.s_stat)
    // 0=Çalışmıyor, 1=Müsait, 2=Meşgul, 3=Mola, 4=Kaza
    switch (widget.courierStatus) {
      case 0:
        return const Color(0xFF757575); // Çalışmıyor - Gri
      case 1:
        return const Color(0xFF4CAF50); // Müsait - Yeşil
      case 2:
        return const Color(0xFFFF9800); // Meşgul - Turuncu
      case 3:
        return const Color(0xFF2196F3); // Mola - Mavi
      case 4:
        return const Color(0xFFE53935); // Kaza - Kırmızı
      default:
        return const Color(0xFF4CAF50); // Default: Müsait
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Üst Bar - Butonlar ve İsim
            Row(
              crossAxisAlignment: CrossAxisAlignment.start, // ⭐ Üst hizalama
              children: [
                // Sol Buton (Vardiya Yönetimi)
                _buildIconButton(
                  icon: Icons.access_time,
                  onPressed: widget.onShiftPressed,
                  backgroundColor: _getStatusColor(), // ⭐ Durum rengine göre
                  iconColor: Colors.white,
                ),
                
                const SizedBox(width: 12),
                
                // İsim & Paket Sayısı Kartı
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2196F3).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              // İsim (1. Düzeltme: "Merhaba" kaldırıldı)
                              Expanded(
                                child: Center(
                                  child: Text(
                                    widget.userName.length > 15
                                        ? '${widget.userName.substring(0, 15)}...'
                                        : widget.userName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              
                              // Paket Sayısı Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.local_shipping_outlined,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${widget.packageCount}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // ⭐ Durum kartı (İsmin altında)
                      const SizedBox(height: 8),
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(width: 12),
                            // Durum İndikatörü
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _getStatusColor(),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Durum Metni
                            Text(
                              widget.statusText,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _getStatusColor(),
                                letterSpacing: 0.8,
                              ),
                            ),
                            // ⭐ Vardiya bilgisi (sadece Müsait durumunda ve vardiya varsa)
                            if (widget.courierStatus == 1 && 
                                _shiftInfo != null && 
                                _shiftInfo!['hasShift'] == true &&
                                _shiftInfo!['startTime'] != null &&
                                _shiftInfo!['endTime'] != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${_shiftInfo!['startTime']} - ${_shiftInfo!['endTime']}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // ⭐ Sağ Buton (Profil)
                _buildIconButton(
                  icon: Icons.person_rounded,
                  onPressed: widget.onProfilePressed,
                  backgroundColor: Colors.white,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    Color? iconColor, // ⭐ İkon rengi opsiyonel
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Icon(
            icon,
            color: iconColor ?? const Color(0xFF2196F3), // ⭐ Varsayılan mavi
            size: 24,
          ),
        ),
      ),
    );
  }
}

