import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'location_service.dart';

/// 🕐 Profesyonel Vardiya Yönetim Servisi
/// 
/// Özellikler:
/// - ✅ Vardiya giriş/çıkış kontrolü
/// - ✅ Gece vardiyası desteği (20:00 - 05:00)
/// - ✅ Otomatik mola yönetimi
/// - ✅ Gün değişiminde otomatik kapatma
/// - ✅ Bay bazında farklı vardiya tanımları
class ShiftService {
  static final ShiftService _instance = ShiftService._internal();
  factory ShiftService() => _instance;
  ShiftService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ⭐ Vardiya Durumları
  static const int STATUS_OFFLINE = 0; // Çalışmıyor
  static const int STATUS_AVAILABLE = 1; // Müsait
  static const int STATUS_BUSY = 2; // Meşgul
  static const int STATUS_BREAK = 3; // Molada
  static const int STATUS_EMERGENCY = 4; // Kaza

  /// 📅 Gün İsimleri (Firestore field isimleri)
  static const Map<int, String> dayNames = {
    0: 'ss_pazar',
    1: 'ss_pazartesi',
    2: 'ss_sali',
    3: 'ss_carsamba',
    4: 'ss_persembe',
    5: 'ss_cuma',
    6: 'ss_cumartesi',
  };

  /// 🔐 Vardiya Giriş Kontrolü
  /// 
  /// Returns: {
  ///   allowed: bool,
  ///   message: String,
  ///   shiftStart: String?,
  ///   shiftEnd: String?
  /// }
  Future<Map<String, dynamic>> checkLogin(int courierId, int bayId) async {
    try {
      print('🔍 Vardiya giriş kontrolü: courierId=$courierId, bayId=$bayId');

      // 1️⃣ Kullanıcı bilgilerini al
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        return {
          'allowed': false,
          'message': '❌ Kullanıcı bulunamadı',
        };
      }

      final courierData = courierQuery.docs.first.data();
      
      // ⭐ Tip güvenli shiftId alma (String veya int olabilir)
      final shiftIdRaw = courierData['t_shift'];
      final int? shiftId = shiftIdRaw is int 
          ? shiftIdRaw 
          : (shiftIdRaw is String ? int.tryParse(shiftIdRaw) : null);

      if (shiftId == null) {
        return {
          'allowed': false,
          'message': '❌ Vardiya tanımı atanmamış',
        };
      }

      // ⭐ Kurye'nin gerçek bay ID'sini al
      final courierBayIdRaw = courierData['s_bay'];
      final int courierBayId = courierBayIdRaw is int 
          ? courierBayIdRaw 
          : (courierBayIdRaw is String ? int.tryParse(courierBayIdRaw) ?? bayId : bayId);
      
      print('👤 Kurye Bay ID: $courierBayId');

      // 2️⃣ Vardiya bilgilerini al (Kurye'nin bay ID'si ile)
      final shiftResult = await _getShiftInfo(shiftId, courierBayId);
      
      if (!shiftResult['success']) {
        return {
          'allowed': false,
          'message': shiftResult['message'],
        };
      }

      final shiftData = shiftResult['data'] as Map<String, dynamic>;

      // 3️⃣ Bugünün vardiya saatlerini al
      final todayShift = _getTodayShiftTimes(shiftData);

      if (!todayShift['hasShift']) {
        return {
          'allowed': false,
          'message': '📅 Bugün vardiya yok. Giriş yapamazsınız.',
        };
      }

      // 4️⃣ Zaman kontrolü
      final currentMinutes = _getCurrentTimeInMinutes();
      final startMinutes = todayShift['startMinutes'] as int;
      final endMinutes = todayShift['endMinutes'] as int;
      final isNightShift = endMinutes < startMinutes;

      if (isNightShift) {
        // 🌙 GECE VARDİYASI (örn: 20:00 - 05:00)
        // İçinde mi: (şimdi >= 20:00) VEYA (şimdi <= 05:00)
        // Dışında mı: (05:00 < şimdi < 20:00)
        if (currentMinutes > endMinutes && currentMinutes < startMinutes) {
          return {
            'allowed': false,
            'message': '⏰ Vardiya saati dışında.\n'
                'Bugünkü vardiya: ${todayShift['startTime']} - ${todayShift['endTime']}',
          };
        }

        return {
          'allowed': true,
          'message': '✅ Giriş başarılı (Gece vardiyası)',
          'shiftStart': todayShift['startTime'],
          'shiftEnd': todayShift['endTime'],
        };
      } else {
        // ☀️ NORMAL VARDİYA (örn: 09:00 - 18:00)
        if (currentMinutes < startMinutes) {
          final waitMinutes = startMinutes - currentMinutes;
          final waitHours = waitMinutes ~/ 60;
          final waitMins = waitMinutes % 60;

          return {
            'allowed': false,
            'message': '⏰ Vardiya başlangıcına ${waitHours > 0 ? '$waitHours saat ' : ''}$waitMins dakika var.',
          };
        }

        if (currentMinutes > endMinutes) {
          return {
            'allowed': false,
            'message': '⏰ Vardiya süresi dolmuş.',
          };
        }

        return {
          'allowed': true,
          'message': '✅ Giriş başarılı',
          'shiftStart': todayShift['startTime'],
          'shiftEnd': todayShift['endTime'],
        };
      }
    } catch (e) {
      print('❌ Vardiya giriş kontrolü hatası: $e');
      return {
        'allowed': false,
        'message': '❌ Giriş kontrolü yapılamadı',
      };
    }
  }

  /// 🚪 Vardiya Çıkış Kontrolü
  Future<Map<String, dynamic>> checkLogout(int courierId, int bayId) async {
    try {
      print('🔍 Vardiya çıkış kontrolü: courierId=$courierId, bayId=$bayId');

      // ⭐ 1. ÖNCE AKTİF SİPARİŞ KONTROLÜ (En önemli!)
      print('🔍 Aktif sipariş kontrolü yapılıyor...');
      final activeOrders = await _db
          .collection('t_orders')
          .where('s_courier', isEqualTo: courierId)
          .where('s_stat', whereIn: [0, 1]) // 0=Hazır, 1=Yolda
          .get();

      if (activeOrders.docs.isNotEmpty) {
        final orderCount = activeOrders.docs.length;
        print('❌ Aktif sipariş var: $orderCount adet');
        return {
          'allowed': false,
          'message': '📦 Aktif siparişiniz var! Önce ${orderCount == 1 ? 'siparişi' : '$orderCount siparişi'} teslim edin.',
        };
      }

      print('✅ Aktif sipariş yok');

      // ⭐ 2. VARDIAY SAAT KONTROLÜ (Otomatik çıkış için)
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        return {'allowed': false, 'message': '❌ Kullanıcı bulunamadı'};
      }

      final courierData = courierQuery.docs.first.data();
      
      // ⭐ Tip güvenli shiftId alma (String veya int olabilir)
      final shiftIdRaw = courierData['t_shift'];
      final int? shiftId = shiftIdRaw is int 
          ? shiftIdRaw 
          : (shiftIdRaw is String ? int.tryParse(shiftIdRaw) : null);

      if (shiftId == null) {
        // Vardiya tanımı yoksa direkt çıkabilir
        return {
          'allowed': true,
          'message': '✅ Çıkış başarılı',
          'autoLogout': false,
        };
      }

      // ⭐ Kurye'nin gerçek bay ID'sini al
      final courierBayIdRaw = courierData['s_bay'];
      final int courierBayId = courierBayIdRaw is int 
          ? courierBayIdRaw 
          : (courierBayIdRaw is String ? int.tryParse(courierBayIdRaw) ?? bayId : bayId);
      
      print('👤 Kurye Bay ID: $courierBayId');

      final shiftResult = await _getShiftInfo(shiftId, courierBayId);
      
      if (!shiftResult['success']) {
        return {
          'allowed': true,
          'message': '✅ Çıkış başarılı',
          'autoLogout': false,
        };
      }

      final shiftData = shiftResult['data'] as Map<String, dynamic>;
      final todayShift = _getTodayShiftTimes(shiftData);

      if (!todayShift['hasShift']) {
        return {
          'allowed': true,
          'message': '✅ Çıkış başarılı',
          'autoLogout': false,
        };
      }

      // Zaman kontrolü (sadece autoLogout için)
      final currentMinutes = _getCurrentTimeInMinutes();
      final startMinutes = todayShift['startMinutes'] as int;
      final endMinutes = todayShift['endMinutes'] as int;
      final isNightShift = endMinutes < startMinutes;

      bool shiftTimeEnded = false;

      if (isNightShift) {
        // 🌙 GECE VARDİYASI
        if (currentMinutes >= startMinutes) {
          // 20:00 veya sonrası - henüz bitmedi
          shiftTimeEnded = false;
        } else if (currentMinutes <= endMinutes) {
          // 00:00 - 05:00 arası - henüz bitmedi
          shiftTimeEnded = false;
        } else {
          // 05:00 - 20:00 arası - vardiya bitti
          shiftTimeEnded = true;
        }
      } else {
        // ☀️ NORMAL VARDİYA
        if (currentMinutes < endMinutes) {
          shiftTimeEnded = false;
        } else {
          shiftTimeEnded = true;
        }
      }

      // ⭐ Aktif sipariş yoksa HER ZAMAN çıkabilir (saat geçmese bile)
      return {
        'allowed': true,
        'message': shiftTimeEnded 
            ? '✅ Vardiya süreniz doldu, çıkış yapıldı'
            : '✅ Çıkış başarılı',
        'autoLogout': shiftTimeEnded, // Sadece saat geçtiyse otomatik çıkış
      };
    } catch (e) {
      print('❌ Vardiya çıkış kontrolü hatası: $e');
      return {'allowed': false, 'message': '❌ Çıkış kontrolü yapılamadı'};
    }
  }

  /// 🕐 Mola Başlatma
  Future<Map<String, dynamic>> startBreak(int courierId) async {
    try {
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        return {'success': false, 'message': '❌ Kullanıcı bulunamadı'};
      }

      final courierDoc = courierQuery.docs.first;
      final courierData = courierDoc.data();
      // ⭐ s_break_duration field'ından oku
      final breakDurationRaw = courierData['s_break_duration'];
      int breakDuration = 60; // Default
      if (breakDurationRaw is int) {
        breakDuration = breakDurationRaw;
      } else if (breakDurationRaw is String) {
        breakDuration = int.tryParse(breakDurationRaw) ?? 60;
      } else if (breakDurationRaw != null) {
        breakDuration = (breakDurationRaw as num).toInt();
      }

      await courierDoc.reference.update({
        's_breaktime': Timestamp.now(),
        's_stat': STATUS_BREAK,
      });

      // 💾 Cache'i invalidate et
      LocationService.invalidateStatusCache();

      return {
        'success': true,
        'message': '☕ Mola başladı. $breakDuration dakika sonra otomatik müsait olacaksınız.',
        'breakDuration': breakDuration,
      };
    } catch (e) {
      print('❌ Mola başlatma hatası: $e');
      return {'success': false, 'message': '❌ Mola başlatılamadı'};
    }
  }

  /// 🔄 Mola Durumu Kontrolü (Otomatik)
  Future<Map<String, dynamic>> checkBreakStatus(int courierId) async {
    try {
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        return {'success': false, 'onBreak': false};
      }

      final courierDoc = courierQuery.docs.first;
      final courierData = courierDoc.data();

      // Molada değilse kontrol gereksiz
      if (courierData['s_stat'] != STATUS_BREAK) {
        return {'success': true, 'onBreak': false};
      }

      final breakStartTime = (courierData['s_breaktime'] as Timestamp?)?.toDate();
      // ⭐ s_break_duration field'ından oku
      final breakDurationRaw = courierData['s_break_duration'];
      int breakDuration = 60; // Default
      if (breakDurationRaw is int) {
        breakDuration = breakDurationRaw;
      } else if (breakDurationRaw is String) {
        breakDuration = int.tryParse(breakDurationRaw) ?? 60;
      } else if (breakDurationRaw != null) {
        breakDuration = (breakDurationRaw as num).toInt();
      }

      if (breakStartTime == null) {
        return {'success': true, 'onBreak': false};
      }

      final now = DateTime.now();
      final elapsedMinutes = now.difference(breakStartTime).inMinutes;

      // Mola süresi dolmuşsa otomatik müsait yap
      if (elapsedMinutes >= breakDuration) {
        // Guard: Kurye OFFLINE ise AVAILABLE yapma
        try {
          final fresh = await courierDoc.reference.get();
          final freshData = fresh.data() as Map<String, dynamic>? ?? {};
          final currentStat = freshData['s_stat'] as int? ?? STATUS_OFFLINE;
          if (currentStat != STATUS_OFFLINE) {
            await courierDoc.reference.update({'s_stat': STATUS_AVAILABLE});
          } else {
            print('ℹ️ Guard: Kurye OFFLINE, s_stat AVAILABLE yapılmadı (checkBreakStatus).');
          }
        } catch (e) {
          print('⚠️ Guard kontrolü sırasında hata (checkBreakStatus): $e');
          // Güvenli tarafta kal: statüyü değiştirme
        }

        // 💾 Cache'i invalidate et
        LocationService.invalidateStatusCache();

        return {
          'success': true,
          'onBreak': false,
          'message': '✅ Mola süresi doldu. Artık müsaitsiniz.',
          'autoActivated': true,
        };
      }

      // Hala molada
      final remainingMinutes = breakDuration - elapsedMinutes;
      return {
        'success': true,
        'onBreak': true,
        'remainingMinutes': remainingMinutes,
      };
    } catch (e) {
      print('❌ Mola kontrolü hatası: $e');
      return {'success': false, 'message': '❌ Mola kontrolü yapılamadı'};
    }
  }

  /// 🛑 Mola Sonlandırma (Manuel)
  Future<Map<String, dynamic>> endBreak(int courierId) async {
    try {
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        return {'success': false, 'message': '❌ Kullanıcı bulunamadı'};
      }

      await courierQuery.docs.first.reference.update({'s_stat': STATUS_AVAILABLE});

      // 💾 Cache'i invalidate et
      LocationService.invalidateStatusCache();

      return {'success': true, 'message': '✅ Mola sonlandırıldı. Artık müsaitsiniz.'};
    } catch (e) {
      print('❌ Mola bitirme hatası: $e');
      return {'success': false, 'message': '❌ Mola bitirilemedi'};
    }
  }

  /// 📅 Gün Değişimi Kontrolü ve Otomatik Kapatma
  Future<Map<String, dynamic>> checkAndHandleDayChange(int courierId, int currentStatus) async {
    try {
      print('🔍 Gün değişimi kontrolü başlatıldı...');

      // Vardiya kapalıysa kontrol gereksiz
      if (currentStatus == STATUS_OFFLINE) {
        print('✅ Vardiya zaten kapalı');
        return {'closed': false, 'reason': 'already_closed'};
      }

      final prefs = await SharedPreferences.getInstance();
      final lastShiftDate = prefs.getString('shift_start_date_$courierId');
      final today = _getTodayString();

      print('📅 Son vardiya tarihi: $lastShiftDate');
      print('📅 Bugünün tarihi: $today');

      // Tarih kaydı yoksa (ilk kez açılıyor)
      if (lastShiftDate == null) {
        print('ℹ️ İlk vardiya açılışı, tarih kaydediliyor');
        await prefs.setString('shift_start_date_$courierId', today);
        return {'closed': false, 'reason': 'first_time'};
      }

      // Tarih değişmiş mi kontrol et
      if (lastShiftDate != today) {
        print('🚨 GÜN DEĞİŞTİ! Vardiya otomatik kapatılıyor...');

        final success = await _autoCloseShift(courierId);

        if (success) {
          await prefs.setString('shift_start_date_$courierId', today);

          return {
            'closed': true,
            'reason': 'day_changed',
            'oldDate': lastShiftDate,
            'newDate': today,
          };
        } else {
          return {'closed': false, 'reason': 'close_failed'};
        }
      } else {
        print('✅ Aynı gün, vardiya devam ediyor');
        return {'closed': false, 'reason': 'same_day'};
      }
    } catch (e) {
      print('❌ Gün değişimi kontrolü hatası: $e');
      return {'closed': false, 'reason': 'error'};
    }
  }

  /// 📝 Vardiya Başlangıcını Kaydet
  Future<void> recordShiftStart(int courierId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _getTodayString();
      await prefs.setString('shift_start_date_$courierId', today);
      await prefs.setInt('shift_start_time_$courierId', DateTime.now().millisecondsSinceEpoch);
      print('📅 Vardiya başlangıcı kaydedildi: $today');
    } catch (e) {
      print('❌ Vardiya başlangıç kaydetme hatası: $e');
    }
  }

  /// 🔒 Otomatik Vardiya Kapatma
  Future<bool> _autoCloseShift(int courierId) async {
    try {
      print('🔄 Otomatik vardiya kapatma başlatıldı');

      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        print('❌ Kullanıcı Firestore\'da bulunamadı');
        return false;
      }

      await courierQuery.docs.first.reference.update({
        's_stat': STATUS_OFFLINE,
        'last_auto_close': Timestamp.now(),
      });

      // 💾 Cache'i invalidate et
      LocationService.invalidateStatusCache();

      print('✅ Vardiya otomatik kapatıldı');
      return true;
    } catch (e) {
      print('❌ Otomatik vardiya kapatma hatası: $e');
      return false;
    }
  }

  /// 🔍 Vardiya Bilgilerini Getir (Private)
  Future<Map<String, dynamic>> _getShiftInfo(int shiftId, int bayId) async {
    try {
      print('🔍 Vardiya bilgisi sorgulanıyor:');
      print('   Shift ID: $shiftId');
      print('   Bay ID: $bayId');
      
      final shiftQuery = await _db
          .collection('t_shift')
          .where('s_id', isEqualTo: shiftId)
          .where('s_bay', isEqualTo: bayId)
          .limit(1)
          .get();

      if (shiftQuery.docs.isEmpty) {
        print('❌ Vardiya bulunamadı! (s_id=$shiftId, s_bay=$bayId)');
        return {
          'success': false,
          'message': '❌ Vardiya tanımı bulunamadı (ID: $shiftId, Bay: $bayId)',
        };
      }

      final shiftData = shiftQuery.docs.first.data();
      print('✅ Vardiya bulundu: ${shiftData['s_name']}');
      print('   Shifts: ${shiftData['s_shifts']}');

      return {
        'success': true,
        'data': shiftData,
      };
    } catch (e) {
      print('❌ Vardiya bilgisi alma hatası: $e');
      return {
        'success': false,
        'message': '❌ Vardiya bilgisi alınamadı: $e',
      };
    }
  }

  /// 📅 Bugünün Vardiya Saatlerini Al (Private)
  Map<String, dynamic> _getTodayShiftTimes(Map<String, dynamic> shiftData) {
    final today = DateTime.now().weekday % 7; // 0: Pazar, 1: Pazartesi, ...
    final dayName = dayNames[today] ?? 'ss_pazartesi';
    
    print('📅 Bugünün vardiya kontrolü:');
    print('   Bugün: $dayName (${DateTime.now().weekday})');
    
    final shifts = shiftData['s_shifts'] as Map<String, dynamic>?;
    if (shifts == null || !shifts.containsKey(dayName)) {
      print('❌ Bugün için vardiya tanımı yok');
      return {'hasShift': false};
    }

    final todayTimes = shifts[dayName] as List<dynamic>;
    final startTime = todayTimes[0] as String;
    final endTime = todayTimes[1] as String;

    print('   Vardiya saatleri: $startTime - $endTime');

    // ["00:00", "00:00"] = Kapalı gün
    if (startTime == "00:00" && endTime == "00:00") {
      print('❌ Bugün kapalı gün (00:00 - 00:00)');
      return {'hasShift': false};
    }

    print('✅ Bugün vardiya var!');
    return {
      'hasShift': true,
      'startTime': startTime,
      'endTime': endTime,
      'startMinutes': _timeToMinutes(startTime),
      'endMinutes': _timeToMinutes(endTime),
    };
  }

  /// ⏰ Şu Anki Zamanı Dakikaya Çevir (Private)
  int _getCurrentTimeInMinutes() {
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    print('⏰ Şu anki saat: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ($minutes dakika)');
    return minutes;
  }

  /// 🕐 Saat String'ini Dakikaya Çevir (Private)
  int _timeToMinutes(String timeString) {
    final parts = timeString.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    return hours * 60 + minutes;
  }

  /// 📅 Bugünün Tarihini String Olarak Al (Private)
  String _getTodayString() {
    final today = DateTime.now();
    return '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  }

  /// 🎨 Durum Rengini Al
  static String getStatusColor(int status) {
    switch (status) {
      case STATUS_OFFLINE:
        return '#FF9800'; // Turuncu
      case STATUS_AVAILABLE:
        return '#4CAF50'; // Yeşil
      case STATUS_BUSY:
        return '#2196F3'; // Mavi
      case STATUS_BREAK:
        return '#FFC107'; // Sarı
      case STATUS_EMERGENCY:
        return '#000000'; // Siyah
      default:
        return '#9E9E9E'; // Gri
    }
  }

  /// 📝 Durum Metnini Al
  static String getStatusText(int status) {
    switch (status) {
      case STATUS_OFFLINE:
        return 'ÇALIŞMIYOR';
      case STATUS_AVAILABLE:
        return 'MÜSAİT';
      case STATUS_BUSY:
        return 'MEŞGUL';
      case STATUS_BREAK:
        return 'MOLADA';
      case STATUS_EMERGENCY:
        return 'KAZA';
      default:
        return 'BİLİNMİYOR';
    }
  }
}

