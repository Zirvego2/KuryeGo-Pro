import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/shift_service.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';
import '../services/shift_log_service.dart';
import '../services/break_service.dart';
import '../services/sms_service.dart';
import '../models/courier_daily_log.dart';

/// 🕐 Vardiya Yönetim Menüsü
/// Bottom Sheet olarak gösterilen profesyonel vardiya menüsü
class ShiftMenuSheet extends StatefulWidget {
  final int courierId;
  final int bayId;
  final int currentStatus;
  final Function(int) onStatusChanged;

  const ShiftMenuSheet({
    super.key,
    required this.courierId,
    required this.bayId,
    required this.currentStatus,
    required this.onStatusChanged,
  });

  @override
  State<ShiftMenuSheet> createState() => _ShiftMenuSheetState();
}

class _ShiftMenuSheetState extends State<ShiftMenuSheet> {
  final ShiftService _shiftService = ShiftService();
  final ShiftLogService _shiftLogService = ShiftLogService();
  final BreakService _breakService = BreakService();
  bool _isProcessing = false;
  
  CourierDailyLog? _activeLog;
  StreamSubscription<CourierDailyLog?>? _logSubscription;
  StreamSubscription<int>? _courierStatusSubscription; // ⭐ t_courier.s_stat stream'i
  Timer? _refreshTimer;
  Map<String, dynamic>? _currentBreakInfo;
  Map<String, dynamic>? _todayShiftInfo; // ⭐ Bugünün vardiya bilgisi
  int? _currentCourierStatus; // ⭐ Stream'den gelen güncel kurye statüsü (buton görünürlüğü için)
  
  @override
  void initState() {
    super.initState();
    _loadActiveShift();
    _loadTodayShiftInfo(); // ⭐ Bugünün vardiya bilgilerini yükle
    _startRefreshTimer();
    _watchCourierStatus(); // ⭐ t_courier.s_stat stream'ini dinle (admin tarafından kapatılma kontrolü için)
    // ⭐ NOT: Otomatik popup kontrolü sadece _watchCourierStatus içinde yapılıyor (s_stat değiştiğinde)
  }
  
  @override
  void dispose() {
    _logSubscription?.cancel();
    _courierStatusSubscription?.cancel(); // ⭐ Stream'i iptal et
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  /// Aktif vardiyayı yükle ve dinle
  Future<void> _loadActiveShift() async {
    // ⭐ Önce tek seferlik yükle (fallback mekanizması ile)
    // ⭐ NOT: getActiveShift() t_courier.s_stat kontrolü yapıyor (s_stat=0 ise null döner)
    final activeLog = await _shiftLogService.getActiveShift(widget.courierId);
    if (mounted) {
      setState(() {
        // ⭐ KRİTİK: getActiveShift() null dönerse (önetici tarafından kapatılmış olabilir)
        // Mevcut _activeLog'u temizle
        if (activeLog == null && _activeLog != null) {
          print('⚠️ ⚠️ ⚠️ getActiveShift() null döndü - Vardiya kapatılmış olabilir (önetici tarafından)');
          print('   Önceki log: ${_activeLog!.docId}, isClosed: ${_activeLog!.isClosed}');
        }
        _activeLog = activeLog; // null ise null yap, varsa güncelle
      });
      _updateBreakInfo();
      
      if (activeLog == null) {
        print('✅ Vardiya log temizlendi (aktif vardiya yok)');
      } else {
        print('✅ Aktif vardiya yüklendi: docId=${activeLog.docId}, status=${activeLog.status}, isClosed=${activeLog.isClosed}');
      }
    }
    
    // ⭐ Sonra real-time stream'i dinle (vardiya değişikliklerini yakalamak için)
    _logSubscription = _shiftLogService
        .watchActiveShift(widget.courierId)
        .listen(
      (log) {
        if (mounted) {
          setState(() {
            // ⭐ KRİTİK DÜZELTME: Stream null döndüğünde mevcut log'u da null yap!
            // (Admin tarafından vardiya kapatılmışsa stream null döner, UI'ı güncellememiz gerekir)
            if (log != null) {
              // Stream'den aktif vardiya geldi
              _activeLog = log;
            } else {
              // ⭐ Stream null döndü - vardiya kapatılmış olabilir (admin tarafından isClosed=true yapılmış)
              // Direkt null yap (stream isClosed=false filtreliyor, null dönerse kapatılmış demektir)
              if (_activeLog != null) {
                _activeLog = null; // ⭐ Vardiya kapatılmış, log'u temizle
              }
            }
          });
          _updateBreakInfo();
          // ⭐ Vardiya durumu değiştiğinde bugünün vardiya bilgisini yeniden yükle
          _loadTodayShiftInfo();
        }
      },
      onError: (error) {
        print('❌ watchActiveShift stream hatası: $error');
        // ⭐ Hata durumunda yeniden yükle
        _shiftLogService.getActiveShift(widget.courierId).then((refreshedLog) {
          if (mounted) {
            setState(() {
              _activeLog = refreshedLog;
            });
            _updateBreakInfo();
          }
        });
      },
    );
  }

  /// ⭐ t_courier.s_stat stream'ini dinle (admin tarafından vardiya kapatılma kontrolü için)
  void _watchCourierStatus() {
    // ⭐ İlk değeri widget.currentStatus'tan al
    _currentCourierStatus = widget.currentStatus;
    
    _courierStatusSubscription = FirebaseService
        .watchCourierStatus(widget.courierId)
        .listen(
      (status) {
        print('👤 Kurye statüsü güncellendi (ShiftMenuSheet): $status');
        
        // ⭐ KRİTİK: Stream'den gelen statüyü yerel state'e kaydet (buton görünürlüğü için)
        if (mounted) {
          setState(() {
            _currentCourierStatus = status;
            // BREAK disindaki durumlarda stale sayaç kalmasin.
            if (status != ShiftService.STATUS_BREAK) {
              _currentBreakInfo = null;
            }
          });
        }
        
        // ⭐ Eğer kurye statüsü OFFLINE (0) ise, vardiya kapatılmış demektir (admin tarafından)
        if (status == 0) {
          print('⚠️ ⚠️ ⚠️ KRİTİK: Kurye statüsü OFFLINE (s_stat=0) - Vardiya kapatılmış!');
          
          if (mounted && _activeLog != null) {
            setState(() {
              _activeLog = null; // ⭐ Vardiya log'unu temizle
            });
            _updateBreakInfo();
            // ⭐ Vardiya kapatıldığında bugünün vardiya bilgisini yeniden yükle
            _loadTodayShiftInfo();
            print("✅ ✅ ✅ Vardiya log'u temizlendi (admin tarafından kapatılmış)");
          }
        } else if (status > 0 && _activeLog == null) {
          // ⭐ Eğer statü aktif ama vardiya log'u null ise
          // 1. Önce aktif vardiya var mı kontrol et
          _shiftLogService.getActiveShift(widget.courierId).then((refreshedLog) {
            if (mounted) {
              if (refreshedLog != null) {
                setState(() {
                  _activeLog = refreshedLog;
                });
                _updateBreakInfo();
                // ⭐ Vardiya yeniden yüklendiğinde bugünün vardiya bilgisini yeniden yükle
                _loadTodayShiftInfo();
                print("✅ Vardiya log'u yeniden yüklendi (statü aktif)");
              }
            }
          });
        }
      },
      onError: (error) {
        print('❌ Kurye statü stream hatası (ShiftMenuSheet): $error');
      },
    );
  }
  
  /// Anlık mola bilgisini güncelle
  Future<void> _updateBreakInfo() async {
    if (_activeLog?.status == 'BREAK') {
      final info = await _breakService.getCurrentBreakInfo(widget.courierId);
      if (mounted) {
        setState(() {
          _currentBreakInfo = info;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _currentBreakInfo = null;
        });
      }
    }
  }
  
  /// ⭐ Bugünün vardiya bilgilerini yükle
  Future<void> _loadTodayShiftInfo() async {
    try {
      final shiftInfo = await _shiftLogService.getTodayShiftInfo(widget.courierId);
      if (mounted) {
        setState(() {
          _todayShiftInfo = shiftInfo;
        });
      }
    } catch (e) {
      print('❌ Bugünün vardiya bilgisi yükleme hatası: $e');
      // ⭐ Hata durumunda bile _todayShiftInfo'yu null yapma, varsayılan değerlerle doldur
      if (mounted && _todayShiftInfo == null) {
        setState(() {
          _todayShiftInfo = {
            'hasShift': false,
            'startTime': '00:00',
            'endTime': '00:00',
            'startMinutes': 0,
            'endMinutes': 0,
          };
          print('⚠️ Hata durumunda varsayılan _todayShiftInfo ayarlandı');
        });
      }
    }
  }

  /// Her saniye yenile (anlık sayaç için)
  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_activeLog?.status == 'BREAK') {
        _updateBreakInfo();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ KRİTİK DEĞİŞİKLİK: Vardiya durumu tamamen s_stat'a bağlı!
    // s_stat = 0 → OFF, s_stat = 1 → ACTIVE, s_stat = 2 → ACTIVE, s_stat = 3 → BREAK, s_stat = 4 → EMERGENCY
    final currentStatus = _currentCourierStatus ?? widget.currentStatus;
    String shiftStatus = 'OFF';
    
    if (currentStatus == 0) {
      // OFFLINE - Vardiya kapalı
      shiftStatus = 'OFF';
      
      // ⭐ Özel durum: Vardiya saatleri 00:00 - 00:00 ise "READY" göster (giriş yapılabilir)
      if (_todayShiftInfo != null) {
        final startTime = _todayShiftInfo!['startTime'] as String?;
        final endTime = _todayShiftInfo!['endTime'] as String?;
        if (startTime == "00:00" && endTime == "00:00") {
          shiftStatus = 'READY';
        }
      }
    } else if (currentStatus == 1) {
      // AVAILABLE - Vardiya açık, müsait
      shiftStatus = 'ACTIVE';
    } else if (currentStatus == 2) {
      // BUSY - Vardiya açık, meşgul
      shiftStatus = 'ACTIVE';
    } else if (currentStatus == 3) {
      // BREAK - Vardiya açık, molada
      shiftStatus = 'BREAK';
    } else if (currentStatus == 4) {
      // EMERGENCY - Vardiya açık, kaza
      shiftStatus = 'EMERGENCY';
    }
    
    final breakAllowed = _activeLog?.breakAllowedMinutes ?? 0;
    final breakUsed = _activeLog?.breakUsedMinutes ?? 0;
    final breakRemaining = _activeLog?.breakRemainingMinutes ?? 0;
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Üst Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _getGradientColors(shiftStatus),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_getStatusIcon(shiftStatus), color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vardiya Yönetimi',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Durum: ${_getStatusText(shiftStatus)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 12,
                          ),
                        ),
                        // ⭐ Bugünün vardiya saatleri (vardiya açık değilse göster) - Geçici olarak yorum satırına alındı
                        // if (shiftStatus == 'OFF' && 
                        //     _todayShiftInfo != null && 
                        //     _todayShiftInfo!['hasShift'] == true)
                        //   Padding(
                        //     padding: const EdgeInsets.only(top: 2),
                        //     child: Text(
                        //       '📅 Bugün: ${_todayShiftInfo!['startTime']} - ${_todayShiftInfo!['endTime']}',
                        //       style: TextStyle(
                        //         color: Colors.white.withOpacity(0.85),
                        //         fontSize: 11,
                        //       ),
                        //     ),
                        //   ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Vardiya & Mola Bilgileri (Sadece vardiya açıksa - s_stat != 0)
            if (currentStatus != 0) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.free_breakfast,
                            color: Colors.blue[600],
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Mola Bilgileri',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildBreakInfo('Toplam', '$breakAllowed dk', Colors.blue),
                          _buildBreakInfo('Kullanılan', '$breakUsed dk', Colors.orange),
                          _buildBreakInfo('Kalan', '$breakRemaining dk', breakRemaining > 0 ? Colors.green : Colors.red),
                        ],
                      ),
                      
                      // BREAK durumunda anlık sayaç - ClipRect ile zıplama önleniyor
                      ClipRect(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: shiftStatus == 'BREAK' && _currentBreakInfo != null
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.blue.shade200),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Geçen',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _currentBreakInfo!['elapsedFormatted'] as String,
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            width: 1,
                                            height: 35,
                                            color: Colors.blue.shade200,
                                          ),
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Kalan',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _currentBreakInfo!['remainingFormatted'] as String,
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: breakRemaining > 0 ? Colors.green[700] : Colors.red[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Menü Seçenekleri
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Vardiya Giriş/Çıkış
                  // ⭐ s_stat = 0 ise giriş yapılabilir, s_stat != 0 ise çıkış yapılabilir
                  if (currentStatus == 0)
                    _buildMenuItem(
                      icon: Icons.login,
                      title: 'Vardiyaya Başla',
                      subtitle: _getShiftStartSubtitle(),
                      color: const Color(0xFF4CAF50),
                      onTap: _canStartShift() ? _openShift : null, // ⭐ Vardiya saati kontrolü
                      enabled: _canStartShift(), // ⭐ Butonu disable et
                    )
                  else
                    _buildMenuItem(
                      icon: Icons.logout,
                      title: 'Vardiyayı Bitir',
                      subtitle: _getShiftEndSubtitle(), // ⭐ Dinamik subtitle (kalan süre veya "Çalışmayı bitir")
                      color: const Color(0xFFE53935),
                      onTap: _canEndShift() ? _closeShift : null, // ⭐ Vardiya bitiş saati kontrolü
                      enabled: _canEndShift(), // ⭐ Butonu disable et
                    ),

                  const SizedBox(height: 10),

                  // ⭐ Vardiya açıksa (s_stat != 0) butonlar görünmeli
                  if (currentStatus != 0) ...[
                    // ⭐ Mola butonları - AnimatedSwitcher ile kayma önleniyor (sadece fade, size yok)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                        return Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      child: shiftStatus == 'ACTIVE' && breakRemaining > 0
                          ? _buildMenuItem(
                              key: const ValueKey('break_start'),
                              icon: Icons.free_breakfast,
                              title: 'Molaya Çık',
                              subtitle: 'Mola hakkı: $breakRemaining dk',
                              color: const Color(0xFF2196F3),
                              onTap: _startBreak,
                            )
                          : shiftStatus == 'BREAK'
                              ? _buildMenuItem(
                                  key: const ValueKey('break_end'),
                                  icon: Icons.stop,
                                  title: 'Molayı Bitir',
                                  subtitle: 'Çalışmaya devam et',
                                  color: const Color(0xFF4CAF50),
                                  onTap: _endBreak,
                                )
                              : const SizedBox.shrink(key: ValueKey('break_empty')),
                    ),

                    // Boşluk (Mola butonu varsa)
                    if ((shiftStatus == 'ACTIVE' && breakRemaining > 0) || shiftStatus == 'BREAK')
                      const SizedBox(height: 10),

                    // Kaza Durumu (Sadece vardiya açıksa ve kaza durumunda değilse)
                    // ⭐ KRİTİK: _currentCourierStatus kullan (stream'den gelen güncel değer)
                    if ((_currentCourierStatus ?? widget.currentStatus) != ShiftService.STATUS_EMERGENCY)
                      _buildMenuItem(
                        icon: Icons.warning_amber_rounded,
                        title: 'Kaza Bildirimi',
                        subtitle: 'Acil durum bildirimi',
                        color: const Color(0xFFFF5722),
                        onTap: _reportEmergency,
                      ),
                  ],

                  // Kaza Durumundan Çık
                  // ⭐ KRİTİK: _currentCourierStatus kullan (stream'den gelen güncel değer)
                  // ⭐ NOT: Vardiya açık olmasa bile kaza durumundan çıkılabilir
                  if ((_currentCourierStatus ?? widget.currentStatus) == ShiftService.STATUS_EMERGENCY)
                    _buildMenuItem(
                      icon: Icons.check_circle,
                      title: 'Kaza Durumu Bitti',
                      subtitle: 'Normal duruma dön',
                      color: const Color(0xFF4CAF50),
                      onTap: _endEmergency,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBreakInfo(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
  
  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'ACTIVE':
        return Icons.check_circle;
      case 'BREAK':
        return Icons.free_breakfast;
      case 'READY':
        return Icons.play_circle_outline; // ⭐ Android mantığı: Giriş yapılabilir durumu
      case 'OFF':
      default:
        return Icons.access_time;
    }
  }
  
  String _getStatusText(String status) {
    switch (status) {
      case 'ACTIVE':
        return 'AKTİF';
      case 'BREAK':
        return 'MOLADA';
      case 'READY':
        return 'HAZIR'; // ⭐ Android mantığı: Vardiya tanımlı değil ama giriş yapılabilir
      case 'OFF':
      default:
        return 'KAPALI';
    }
  }

  /// ⭐ Vardiyaya başlanabilir mi kontrolü
  /// ⭐ NOT: Vardiya saatinden ÖNCE veya SONRA giriş yapılabilir (her zaman true döner)
  /// Geç kalma süresi startShift() içinde hesaplanıp kaydediliyor
  bool _canStartShift() {
    // ⭐ Her zaman izin ver (vardiya saatinden önce veya sonra giriş yapılabilir)
    // Geç kalma süresi startShift() içinde hesaplanıp lateStartMinutes field'ına kaydediliyor
    return true;
  }

  /// ⭐ Vardiyaya başla butonu subtitle'ı
  String _getShiftStartSubtitle() {
    // ⭐ Vardiya saatleri geçici olarak yorum satırına alındı
    return 'Çalışmaya başla';
    
    // if (_todayShiftInfo == null) {
    //   return 'Yükleniyor...';
    // }

    // if (_todayShiftInfo!['hasShift'] != true) {
    //   // ⭐ Vardiya saatleri 00:00 - 00:00 olsa bile giriş yapılabilir
    //   final startTime = _todayShiftInfo!['startTime'] as String?;
    //   final endTime = _todayShiftInfo!['endTime'] as String?;
    //   
    //   if (startTime == "00:00" && endTime == "00:00") {
    //     return 'Bugün vardiya tanımlı değil - Giriş yapabilirsiniz';
    //   }
    //   return 'Bugün vardiya yok - Giriş yapabilirsiniz';
    // }

    // final startTime = _todayShiftInfo!['startTime'] as String?;
    // final endTime = _todayShiftInfo!['endTime'] as String?;

    // if (startTime == null || endTime == null) {
    //   return 'Çalışmaya başla';
    // }

    // // ⭐ Vardiya saatinden önce veya sonra giriş yapılabilir
    // final now = DateTime.now();
    // final currentMinutes = now.hour * 60 + now.minute;
    // final startMinutes = _todayShiftInfo!['startMinutes'] as int?;
    // final endMinutes = _todayShiftInfo!['endMinutes'] as int?;

    // if (startMinutes != null && endMinutes != null) {
    //   final isNightShift = endMinutes < startMinutes;
    //   
    //   if (isNightShift) {
    //     // 🌙 GECE VARDİYASI
    //     if (currentMinutes >= startMinutes || currentMinutes <= endMinutes) {
    //       // Vardiya saati içinde
    //       if (currentMinutes > startMinutes) {
    //         // Vardiya başladıktan sonra giriş (geç kalma olabilir)
    //         final lateMinutes = currentMinutes - startMinutes;
    //         return 'Vardiya: $startTime - $endTime ($lateMinutes dk geç giriş)';
    //       } else {
    //         return 'Vardiya: $startTime - $endTime';
    //       }
    //     } else {
    //       // Vardiya dışı saat
    //       return 'Vardiya: $startTime - $endTime (Giriş yapabilirsiniz)';
    //     }
    //   } else {
    //     // ☀️ NORMAL VARDİYA
    //     if (currentMinutes < startMinutes) {
    //       // Vardiya başlamadan önce
    //       final waitMinutes = startMinutes - currentMinutes;
    //       final waitHours = waitMinutes ~/ 60;
    //       final waitMins = waitMinutes % 60;
    //       return 'Vardiya: $startTime - $endTime (${waitHours > 0 ? '$waitHours saat ' : ''}$waitMins dk sonra başlıyor)';
    //     } else if (currentMinutes >= startMinutes && currentMinutes <= endMinutes) {
    //       // Vardiya saati içinde
    //       if (currentMinutes > startMinutes) {
    //         // Vardiya başladıktan sonra giriş (geç kalma)
    //         final lateMinutes = currentMinutes - startMinutes;
    //         return 'Vardiya: $startTime - $endTime ($lateMinutes dk geç giriş)';
    //       } else {
    //         return 'Vardiya: $startTime - $endTime';
    //       }
    //     } else {
    //       // Vardiya bitiş saatinden sonra
    //       return 'Vardiya: $startTime - $endTime (Giriş yapabilirsiniz)';
    //     }
    //   }
    // }

    // return 'Vardiya: $startTime - $endTime';
  }

  /// ⭐ Vardiyayı bitirebilir mi kontrolü (Vardiya bitiş saatinden önce çıkış yapılamaz!)
  bool _canEndShift() {
    // ⭐ Saat kontrolü kaldırıldı - sadece aktif sipariş kontrolü backend'de yapılıyor
    // Her zaman true döndür (aktif sipariş varsa backend hata döndürür)
    return true;
  }

  /// ⭐ Vardiyayı bitir butonu subtitle'ı
  String _getShiftEndSubtitle() {
    // ⭐ Vardiya saatleri geçici olarak yorum satırına alındı
    return 'Çalışmayı bitir';
    
    // ⭐ Saat kontrolü kaldırıldı - sadece vardiya saatlerini göster
    // if (_todayShiftInfo == null || _todayShiftInfo!['hasShift'] != true) {
    //   return 'Çalışmayı bitir';
    // }

    // final startTime = _todayShiftInfo!['startTime'] as String?;
    // final endTime = _todayShiftInfo!['endTime'] as String?;

    // if (startTime != null && endTime != null) {
    //   return 'Vardiya: $startTime - $endTime';
    // }

    // return 'Çalışmayı bitir';
  }

  /// Menü Elemanı Oluştur
  Widget _buildMenuItem({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap, // ⭐ Nullable olarak değiştirildi
    bool enabled = true, // ⭐ Enabled/disabled kontrolü
  }) {
    final isDisabled = !enabled || _isProcessing || onTap == null;
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(isDisabled ? 0.05 : 0.1), // ⭐ Disabled durumunda daha açık
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(isDisabled ? 0.15 : 0.3), width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDisabled ? Colors.grey : color, // ⭐ Disabled durumunda gri
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDisabled ? Colors.grey : color, // ⭐ Disabled durumunda gri
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isDisabled ? Colors.grey[400] : Colors.grey[600], // ⭐ Disabled durumunda daha açık
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isProcessing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Vardiya Aç
  Future<void> _openShift() async {
    setState(() => _isProcessing = true);

    try {
      // breakAllowedMinutes değerini al
      final breakAllowed = await _shiftLogService.getBreakAllowedMinutes(widget.courierId);
      
      // ShiftLogService ile vardiya başlat
      final result = await _shiftLogService.startShift(widget.courierId, breakAllowed);
      
      
      if (result['success'] == true) {
        // ⭐ NOT: s_stat zaten ShiftLogService.startShift() içinde güncellendi
        // Duplicate güncelleme yapmaya gerek yok!

        // ⭐ KONUM SERVİSİNİ BAŞLAT (Vardiya açıldı)
        print('📍 Vardiya açıldı - Konum servisi başlatılıyor...');
        await LocationService.startService(widget.courierId);
        print('✅ Konum servisi başlatıldı!');

        String message = result['message'] as String;
        message = message.replaceAll('✅', '').replaceAll('❌', '').replaceAll('☕', '').replaceAll('⚠️', '').trim();
        _showMessage(message, 'success');
        widget.onStatusChanged(ShiftService.STATUS_AVAILABLE);
        
        // ⭐ Vardiyayı yeniden yükle (stream güncellenmesi için kısa bir bekleme)
        // Log oluşturulduktan sonra stream güncellenecek
        await Future.delayed(const Duration(milliseconds: 300)); // ⭐ Stream güncellenmesi için bekle
        await _loadActiveShift(); // Vardiyayı yeniden yükle
      } else {
        String errorMsg = result['message'] as String;
        errorMsg = errorMsg.replaceAll('✅', '').replaceAll('❌', '').replaceAll('☕', '').replaceAll('⚠️', '').trim();
        _showMessage(errorMsg, 'error');
      }
    } catch (e) {
      print('❌ Vardiya açma hatası: $e');
      _showMessage('Vardiya açılamadı: $e', 'error');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Vardiya Kapat
  Future<void> _closeShift() async {
    // ⭐ KRİTİK: Vardiya durumu s_stat'a bağlı, log kontrolü yapma!
    // Log varsa paket sayısını sorgula, yoksa 0 göster
    setState(() => _isProcessing = true);
    int deliveredCount = 0;
    
    // ⭐ Log varsa paket sayısını sorgula (opsiyonel)
    final shiftStartAt = _activeLog?.shiftStartAt;
    if (shiftStartAt != null) {
      try {
        final shiftEndAt = DateTime.now();
        deliveredCount = await FirebaseService.getDeliveredOrdersCountInShift(
          widget.courierId,
          shiftStartAt,
          shiftEndAt,
        );
      } catch (e) {
        print('⚠️ Vardiya süresince paket sayısı sorgulama hatası: $e');
        // Hata olsa bile devam et
      }
    } else {
      print('ℹ️ Vardiya log bulunamadı, paket sayısı sorgulanmayacak (opsiyonel)');
    }
    
    setState(() => _isProcessing = false);

    // Onay dialog göster (paket sayısı ile)
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vardiyayı Bitir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vardiyayı bitirmek istediğinizden emin misiniz?'),
            if (deliveredCount > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Bu vardiyada teslim edilen paket: $deliveredCount',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Bitir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    try {
      // ShiftLogService ile vardiya bitir (s_stat otomatik olarak 0 yapılacak)
      final result = await _shiftLogService.endShift(widget.courierId);
      
      if (result['success'] == true) {
        // ⭐ NOT: endShift() zaten s_stat'ı 0 yapıyor, tekrar güncellemeye gerek yok

        // ⭐ KONUM SERVİSİNİ DURDUR (Vardiya kapandı)
        print('🛑 Vardiya kapandı - Konum servisi durduruluyor...');
        LocationService.stopService();
        print('✅ Konum servisi durduruldu!');

        // ⭐ Başarı mesajında paket sayısını göster
        String successMessage = result['message'] as String;
        successMessage = successMessage.replaceAll('✅', '').replaceAll('❌', '').replaceAll('☕', '').replaceAll('⚠️', '').trim();
        if (deliveredCount > 0) {
          successMessage += '\nBu vardiyada teslim edilen paket: $deliveredCount';
        }
        
        _showMessage(successMessage, 'success');
        widget.onStatusChanged(ShiftService.STATUS_OFFLINE);
        await _loadActiveShift(); // Vardiyayı yeniden yükle
        // Bottom sheet açık kalmalı - kullanıcı durumu görebilmeli
      } else {
        String errorMsg = result['message'] as String;
        errorMsg = errorMsg.replaceAll('✅', '').replaceAll('❌', '').replaceAll('☕', '').replaceAll('⚠️', '').trim();
        _showMessage(errorMsg, 'error');
      }
    } catch (e) {
      print('❌ Vardiya kapatma hatası: $e');
      _showMessage('Vardiya kapatılamadı: $e', 'error');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Mola Başlat
  Future<void> _startBreak() async {
    setState(() => _isProcessing = true);

    try {
      // ⭐ ÖNCE s_stat kontrolü yap (vardiya durumu s_stat'a bağlı!)
      final currentStatus = _currentCourierStatus ?? widget.currentStatus;
      
      if (currentStatus == ShiftService.STATUS_BREAK) {
        setState(() => _isProcessing = false);
        _showMessage('⚠️ Zaten moladasınız!', 'error');
        return;
      }

      if (currentStatus == ShiftService.STATUS_OFFLINE) {
        setState(() => _isProcessing = false);
        _showMessage('⚠️ Aktif vardiya bulunamadı! Önce vardiyaya başlayın.', 'error');
        return;
      }

      // BreakService ile mola başlat
      final result = await _breakService.startBreak(widget.courierId);

      if (result['success'] == true) {
        // ⭐ NOT: BreakService.startBreak() zaten s_stat'ı BREAK (3) yapıyor
        
        String message = result['message'] as String;
        message = message.replaceAll('✅', '').replaceAll('❌', '').replaceAll('☕', '').replaceAll('⚠️', '').trim();
        _showMessage(message, 'warning');
        widget.onStatusChanged(ShiftService.STATUS_BREAK);
        
        // ⭐ Vardiyayı yeniden yükle (breakUsedMinutes ve breakRemainingMinutes güncellenmesi için)
        await Future.delayed(const Duration(milliseconds: 300)); // Stream güncellenmesi için bekle
        await _loadActiveShift(); // Vardiyayı yeniden yükle
        
        // ⭐ Mola bilgilerini güncelle (anlık sayaç için)
        await _updateBreakInfo();
      } else {
        String errorMsg = result['message'] as String;
        errorMsg = errorMsg.replaceAll('✅', '').replaceAll('❌', '').replaceAll('☕', '').replaceAll('⚠️', '').trim();
        _showMessage(errorMsg, 'error');
      }
    } catch (e) {
      print('❌ Mola başlatma hatası: $e');
      _showMessage('Mola başlatılamadı: $e', 'error');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Mola Bitir
  Future<void> _endBreak() async {
    setState(() => _isProcessing = true);

    try {
      // BreakService ile mola bitir
      final result = await _breakService.endBreak(widget.courierId);

      if (result['success'] == true) {
        // ⭐ NOT: BreakService.endBreak() zaten s_stat'ı AVAILABLE (1) yapıyor
        
        String message = result['message'] as String;
        message = message.replaceAll('✅', '').replaceAll('❌', '').replaceAll('☕', '').replaceAll('⚠️', '').trim();
        _showMessage(message, 'success');
        widget.onStatusChanged(ShiftService.STATUS_AVAILABLE);
        
        // ⭐ Mola bilgilerini güncelle
        await _updateBreakInfo();
      } else {
        String errorMsg = result['message'] as String;
        errorMsg = errorMsg.replaceAll('✅', '').replaceAll('❌', '').replaceAll('☕', '').replaceAll('⚠️', '').trim();
        _showMessage(errorMsg, 'error');
      }
    } catch (e) {
      print('❌ Mola bitirme hatası: $e');
      _showMessage('Mola bitirilemedi: $e', 'error');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Kaza Bildirimi
  Future<void> _reportEmergency() async {
    // Onay dialog göster
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Kaza Bildirimi'),
        content: const Text(
          'Kaza durumu bildirmek istediğinizden emin misiniz?\n\n'
          'Yöneticiniz bilgilendirilecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Bildir'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    try {
      // 1. Kurye statüsünü güncelle
      await FirebaseService.updateCourierStatus(
        widget.courierId,
        ShiftService.STATUS_EMERGENCY,
      );

      // ⭐ KRİTİK: Yerel state'i hemen güncelle (UI anında güncellenir)
      if (mounted) {
        setState(() {
          _currentCourierStatus = ShiftService.STATUS_EMERGENCY;
        });
      }

      // 2. t_bay collection'ından s_phone field'ını çek ve SMS gönder
      SmsService.sendAccidentSMS(widget.courierId, widget.bayId).then((success) {
        if (success) {
          print('✅ Kaza bildirimi SMS başarıyla gönderildi');
        } else {
          print('⚠️ Kaza bildirimi SMS gönderilemedi (arka planda hata)');
        }
      }).catchError((error) {
        print('❌ Kaza bildirimi SMS gönderim hatası: $error');
      });

      _showMessage('Kaza durumu bildirildi', 'warning');
      widget.onStatusChanged(ShiftService.STATUS_EMERGENCY);
      // Bottom sheet açık kalmalı
    } catch (e) {
      _showMessage('Bildirim gönderilemedi', 'error');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Kaza Durumundan Çık
  Future<void> _endEmergency() async {
    setState(() => _isProcessing = true);

    try {
      await FirebaseService.updateCourierStatus(
        widget.courierId,
        ShiftService.STATUS_AVAILABLE,
      );

      // ⭐ KRİTİK: Yerel state'i hemen güncelle (UI anında güncellenir)
      if (mounted) {
        setState(() {
          _currentCourierStatus = ShiftService.STATUS_AVAILABLE;
        });
      }

      _showMessage('Normal duruma dönüldü', 'success');
      widget.onStatusChanged(ShiftService.STATUS_AVAILABLE);
      // Bottom sheet açık kalmalı
    } catch (e) {
      _showMessage('Durum güncellenemedi', 'error');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// Mesaj Göster (Yukarıda Sağda)
  /// type: 'success' (yeşil), 'error' (kırmızı), 'warning' (sarı)
  void _showMessage(String message, String type) {
    if (!mounted) return;

    // Duruma göre arka plan rengi (opak)
    Color backgroundColor;
    Color textColor;
    
    switch (type) {
      case 'success':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'error':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
      case 'warning':
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        break;
      default:
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
    }

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 300),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset((1 - value) * 100, 0),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: textColor.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // 2 saniye sonra kaldır
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  /// Gradient Renkleri (Duruma göre)
  List<Color> _getGradientColors(String status) {
    switch (status) {
      case 'ACTIVE':
        return [const Color(0xFF4CAF50), const Color(0xFF2E7D32)];
      case 'BREAK':
        return [const Color(0xFF2196F3), const Color(0xFF1565C0)];
      case 'READY':
        return [const Color(0xFF9C27B0), const Color(0xFF7B1FA2)]; // ⭐ Android mantığı: Mor renk (hazır durumu)
      case 'OFF':
      default:
        return [const Color(0xFF757575), const Color(0xFF616161)];
    }
  }
}