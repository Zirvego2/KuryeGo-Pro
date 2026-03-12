import 'dart:ui';
import 'package:flutter/material.dart';

/// 🎨 Modern & Kurumsal Home Screen Header Widget
class HomeHeader extends StatefulWidget {
  final String userName;
  final int packageCount;
  final String statusText;
  final int courierStatus; // 0=Çalışmıyor, 1=Müsait, 2=Meşgul, 3=Mola, 4=Kaza
  final VoidCallback onFilterPressed;
  final VoidCallback onProfilePressed;

  const HomeHeader({
    super.key,
    required this.userName,
    required this.packageCount,
    required this.statusText,
    required this.courierStatus,
    required this.onFilterPressed,
    required this.onProfilePressed,
  });

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _lineAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _lineAnimation = Tween<double>(begin: -80, end: 80).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Color _getStatusColor() {
    switch (widget.courierStatus) {
      case 0:
        return const Color(0xFFFF7F00); // Çalışmıyor - Turuncu
      case 1:
        return const Color(0xFF9CE7AE); // Müsait - Yeşil
      case 2:
        return const Color(0xFF007BFF); // Meşgul - Mavi
      case 3:
        return const Color(0xFFF1C40F); // Mola - Sarı
      case 4:
        return Colors.black; // Kaza - Siyah
      default:
        return const Color(0xFF007BFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      left: 0,
      right: 0,
      child: Column(
        children: [
          // Ana bilgi kartı (İsim + Paket Sayısı)
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.55,
            height: 50,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // İsim
                      Expanded(
                        child: Text(
                          widget.userName.length > 9
                              ? '${widget.userName.substring(0, 9)}.'
                              : widget.userName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      // Paket sayısı kartı
                      Transform.translate(
                        offset: const Offset(40, 0),
                        child: Container(
                          width: 90,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007BFF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Stack(
                            children: [
                              // Animasyonlu çizgi
                              AnimatedBuilder(
                                animation: _lineAnimation,
                                builder: (context, child) {
                                  return Positioned(
                                    left: 0,
                                    top: _lineAnimation.value,
                                    child: Container(
                                      width: 5,
                                      height: 80,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                              ),
                              // Paket sayısı
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 20),
                                  child: Text(
                                    '${widget.packageCount}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 30),

          // Durum kartı (MÜSAİT/MEŞGUL/MOLA vb.)
          Container(
            width: 150,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // Sol renkli bölüm
                Container(
                  width: 15,
                  decoration: BoxDecoration(
                    color: _getStatusColor(),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                ),
                // Beyaz çizgi
                Container(
                  width: 5,
                  color: Colors.white,
                ),
                // Blur kart (durum metni)
                Expanded(
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: Colors.black.withOpacity(0.3),
                        child: Center(
                          child: Text(
                            widget.statusText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Beyaz çizgi
                Container(
                  width: 5,
                  color: Colors.white,
                ),
                // Sağ renkli bölüm
                Container(
                  width: 15,
                  decoration: BoxDecoration(
                    color: _getStatusColor(),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

