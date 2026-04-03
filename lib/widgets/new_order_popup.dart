import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/order_model.dart';

/// 🎨 Profesyonel Yeni Sipariş Popup Dialog
/// Yeni sipariş geldiğinde otomatik açılır
class NewOrderPopup extends StatefulWidget {
  final OrderModel order;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final int? remainingSeconds; // Countdown süresi (opsiyonel)
  final int pendingOrderCount; // ⭐ Bekleyen sipariş sayısı (kuyruk)

  const NewOrderPopup({
    super.key,
    required this.order,
    required this.onAccept,
    required this.onReject,
    this.remainingSeconds,
    this.pendingOrderCount = 0,
  });

  @override
  State<NewOrderPopup> createState() => _NewOrderPopupState();
}

class _NewOrderPopupState extends State<NewOrderPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  int? _currentRemainingSeconds;
  Timer? _countdownTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    
    _currentRemainingSeconds = widget.remainingSeconds;
    
    // 🎬 Animasyon kontrolleri
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _animationController.forward();
    
    // 🔊 Ses çal - Popup açıldığında
    _playNotificationSound();
    
    // ⏰ Countdown timer başlat (varsa)
    if (_currentRemainingSeconds != null && _currentRemainingSeconds! > 0) {
      _startCountdown();
    }
  }

  /// 🔊 Bildirim sesini çal
  Future<void> _playNotificationSound() async {
    try {
      print('🔊 Yeni sipariş popup sesi çalınıyor: definite.mp3');
      
      // ⭐ AudioPlayer ayarları - Önce mevcut çalan sesi durdur (varsa)
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(1.0); // Maksimum ses seviyesi
      await _audioPlayer.setReleaseMode(ReleaseMode.release); // Ses bitince kaynakları serbest bırak
      
      // ⭐ AssetSource path: Önce root'taki dosyayı dene (definite.mp3 root'ta)
      // AssetSource'ta 'assets/' prefix'i OLMAMALI
      await _audioPlayer.play(
        AssetSource('definite.mp3'), // ⭐ Root'taki dosya (pubspec.yaml'da tanımlı)
        mode: PlayerMode.mediaPlayer, // ⭐ MediaPlayer modu (bildirim için)
        volume: 1.0,
      );
      
      print('✅ Ses çalma başarılı: definite.mp3 (root)');
    } catch (e, stackTrace) {
      print('❌ Ses çalma hatası (definite.mp3 root): $e');
      print('❌ Stack trace: $stackTrace');
      
      // ⭐ Hata durumunda alternatif path'leri dene
      try {
        print('🔄 Alternatif path 1 deneniyor: sounds/definite.mp3');
        await _audioPlayer.stop(); // Önce durdur
        await _audioPlayer.setVolume(1.0);
        await _audioPlayer.setReleaseMode(ReleaseMode.release);
        await _audioPlayer.play(
          AssetSource('sounds/definite.mp3'), // assets/sounds/ klasöründeki dosya
          mode: PlayerMode.mediaPlayer,
          volume: 1.0,
        );
        print('✅ Alternatif path 1 ile ses çalma başarılı: sounds/definite.mp3');
      } catch (e2) {
        print('❌ Alternatif path 1 başarısız: $e2');
        
        // Son deneme: lowLatency modu ile
        try {
          print('🔄 Alternatif mod deneniyor: lowLatency + definite.mp3');
          await _audioPlayer.stop();
          await _audioPlayer.setVolume(1.0);
          await _audioPlayer.setReleaseMode(ReleaseMode.release);
          await _audioPlayer.play(
            AssetSource('definite.mp3'),
            mode: PlayerMode.lowLatency, // LowLatency modu dene
            volume: 1.0,
          );
          print('✅ LowLatency modu ile ses çalma başarılı: definite.mp3');
        } catch (e3) {
          print('❌ LowLatency modu da başarısız: $e3');
          print('⚠️ Ses dosyası çalınamadı - Tüm denemeler başarısız');
          print('   Kontrol edin: pubspec.yaml\'da asset tanımlı mı?');
          print('   Asset path\'leri: definite.mp3, sounds/definite.mp3');
        }
      }
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        if (_currentRemainingSeconds != null && _currentRemainingSeconds! > 0) {
          _currentRemainingSeconds = _currentRemainingSeconds! - 1;
        } else {
          timer.cancel();
          // ⏰ Timeout - Otomatik reddet (callback zaten popup'ı kapatacak)
          Future.microtask(() {
            if (mounted) {
              widget.onReject(); // Bu callback popup'ı kapatacak
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _audioPlayer.dispose(); // ⭐ Audio player'ı temizle
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Back butonunu devre dışı bırak
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            ),
          );
        },
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🎨 Header - Gradient Background
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.shade600,
                        Colors.blue.shade400,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.notifications_active,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Yeni Sipariş',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Onaylamak ister misiniz?',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // 📋 İçerik
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // ⭐ Bekleyen Sipariş Sayısı Badge (varsa)
                      if (widget.pendingOrderCount > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.purple.shade200,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.queue,
                                color: Colors.purple.shade700,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.pendingOrderCount == 1
                                    ? '1 sipariş bekliyor'
                                    : '${widget.pendingOrderCount} sipariş bekliyor',
                                style: TextStyle(
                                  color: Colors.purple.shade900,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // İşletme Adı
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.shade200,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.store,
                              color: Colors.blue.shade600,
                              size: 32,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              widget.order.sNameWork.isNotEmpty
                                  ? widget.order.sNameWork
                                  : 'İşletme',
                              style: TextStyle(
                                color: Colors.blue.shade900,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Countdown Timer (varsa ve güncelleniyor)
                      if (_currentRemainingSeconds != null &&
                          _currentRemainingSeconds! > 0) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _currentRemainingSeconds! <= 10
                                ? Colors.red.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _currentRemainingSeconds! <= 10
                                  ? Colors.red.shade200
                                  : Colors.orange.shade200,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                color: _currentRemainingSeconds! <= 10
                                    ? Colors.red.shade700
                                    : Colors.orange.shade700,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$_currentRemainingSeconds saniye',
                                style: TextStyle(
                                  color: _currentRemainingSeconds! <= 10
                                      ? Colors.red.shade900
                                      : Colors.orange.shade900,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 🔘 Action Buttons
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    children: [
                      // Reddet Butonu
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onReject,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.close,
                                color: Colors.grey.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Reddet',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Kabul Et Butonu
                      Expanded(
                        child: ElevatedButton(
                          onPressed: widget.onAccept,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Kabul Et',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
