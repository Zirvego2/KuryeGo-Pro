import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/courier_daily_log.dart';
import 'break_service.dart';

/// Vardiya Log Servisi
/// Vardiya açma/kapama işlemlerini yönetir
/// ⭐ t_shift collection'ından gerçek vardiya tanımlarını kullanır
class ShiftLogService {
  static final ShiftLogService _instance = ShiftLogService._internal();
  factory ShiftLogService() => _instance;
  ShiftLogService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collectionName = 'courier_daily_logs';

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

  /// Vardiyaya başla
  /// 
  /// - Aktif vardiya yoksa yeni kayıt oluşturur
  /// - breakAllowedMinutes değerini kurye profilinden yükler
  /// - Gece vardiyası (12:00-02:00) tek kayıt olarak kalır (00:00'da bölünmez)
  Future<Map<String, dynamic>> startShift(int courierId, int breakAllowedMinutes) async {
    try {
      print('🔄 Vardiya başlatılıyor: courierId=$courierId, breakAllowed=$breakAllowedMinutes dk');

      // ⭐ 1. Önce aktif vardiya var mı kontrol et
      final activeLog = await getActiveShift(courierId);
      if (activeLog != null && !activeLog.isClosed) {
        return {
          'success': false,
          'message': '⚠️ Zaten aktif bir vardiyanız var!',
          'log': activeLog,
        };
      }

      // ⭐ 2. Vardiya tarihi: Her zaman bugünün tarihi kullanılır
      final now = DateTime.now();
      final shiftDate = _formatDate(now);

      // ⭐ 4. Kurye referansını al (s_stat güncellemesi için)
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        return {
          'success': false,
          'message': '❌ Kurye bulunamadı!',
        };
      }

      final courierDocRef = courierQuery.docs.first.reference;
      final oldStatus = courierQuery.docs.first.data()['s_stat'] as int? ?? 0;

      // ⭐ 5. ÖNCE vardiya logu oluştur (s_stat güncellemeden önce!)
      // Bu sayede log oluşturulduktan sonra s_stat güncellenir ve race condition önlenir
      // ⭐ HER VARDİYA BAŞLATILDIĞINDA MOLA HAKLARI SIFIRDAN BAŞLAR
      // - breakAllowedMinutes: Kurye profilinden alınan değer (s_break_duration)
      // - breakUsedMinutes: 0 (sıfırdan başlar)
      // - breakRemainingMinutes: breakAllowedMinutes (tam hakkı kadar)
      final newLog = CourierDailyLog(
        courierId: courierId,
        shiftStartAt: now,
        shiftDate: shiftDate,
        status: 'ACTIVE',
        breakAllowedMinutes: breakAllowedMinutes,
        breakUsedMinutes: 0, // ⭐ Her vardiya için sıfırdan başlar
        breakRemainingMinutes: breakAllowedMinutes, // ⭐ Tam hakkı kadar
        breaks: [], // ⭐ Boş liste (yeni vardiya)
        isClosed: false,
        earlyStartMinutes: null,
        lateStartMinutes: null,
      );
      
      print('✅ Yeni vardiya logu oluşturuluyor:');
      print('   breakAllowedMinutes: $breakAllowedMinutes dk');
      print('   breakUsedMinutes: 0 dk (sıfırdan başlıyor)');
      print('   breakRemainingMinutes: $breakAllowedMinutes dk (tam hakkı kadar)');

      DocumentReference? docRef;
      try {
        docRef = await _db.collection(_collectionName).add(newLog.toFirestore());
        print('✅ Vardiya logu oluşturuldu: Doc ID = ${docRef.id}, Tarih = $shiftDate');
      } catch (logError) {
        print('❌ Vardiya logu oluşturma hatası: $logError');
        // Log oluşturulamadı, hata döndür (s_stat henüz güncellenmedi)
        return {
          'success': false,
          'message': '❌ Vardiya logu oluşturulamadı: $logError',
        };
      }

      // ⭐ 6. Log başarıyla oluşturulduktan sonra s_stat'ı güncelle
      try {
        await courierDocRef.update({
          's_stat': 1, // AVAILABLE - Vardiya açık
        });
        print('✅ Kurye statüsü güncellendi: s_stat=1 (AVAILABLE)');
      } catch (statusError) {
        print('❌ ❌ ❌ KRİTİK HATA: Log oluşturuldu ama s_stat güncellenemedi: $statusError');
        // ⭐ ROLLBACK: Log oluşturuldu ama s_stat güncellenemedi, log'u sil
        try {
          await docRef.delete();
          print('✅ Rollback: Vardiya logu silindi (s_stat güncellenemedi)');
        } catch (deleteError) {
          print('❌ ❌ ❌ Rollback hatası: Log silinemedi: $deleteError');
        }
        return {
          'success': false,
          'message': '❌ Vardiya başlatılamadı: Statü güncellenemedi',
        };
      }
      
      print('✅ Vardiya başlatıldı: Doc ID = ${docRef.id}, Tarih = $shiftDate');

      return {
        'success': true,
        'message': '✅ Vardiya başlatıldı',
        'log': newLog.copyWith(docId: docRef.id),
      };
    } catch (e, stackTrace) {
      print('❌ Vardiya başlatma hatası: $e');
      print('Stack trace: $stackTrace');
      
      // ⭐ ROLLBACK: Hata durumunda s_stat'ı geri al (eğer güncellenmişse)
      try {
        final courierQuery = await _db
            .collection('t_courier')
            .where('s_id', isEqualTo: courierId)
            .limit(1)
            .get();
        
        if (courierQuery.docs.isNotEmpty) {
          final currentStatus = courierQuery.docs.first.data()['s_stat'] as int? ?? 0;
          // Eğer s_stat = 1 ise (vardiya açık), geri al
          if (currentStatus == 1) {
            await courierQuery.docs.first.reference.update({
              's_stat': 0, // OFFLINE - Vardiya kapalı
            });
            print('✅ Rollback: s_stat geri alındı (OFFLINE)');
          }
        }
      } catch (rollbackError) {
        print('❌ Rollback hatası: $rollbackError');
      }
      
      return {
        'success': false,
        'message': '❌ Vardiya başlatılamadı: $e',
      };
    }
  }

  /// Vardiyayı bitir
  /// 
  /// - ⭐ Önce aktif sipariş kontrolü yapar
  /// - BREAK durumundaysa önce aktif mola oturumunu kapatır
  /// - shiftEndAt ve closedAt doldurur
  /// - isClosed = true yapar
  Future<Map<String, dynamic>> endShift(int courierId) async {
    try {
      print('🔄 Vardiya bitiriliyor: courierId=$courierId');

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
          'success': false,
          'message': '📦 Aktif siparişiniz var! Önce ${orderCount == 1 ? 'siparişi' : '$orderCount siparişi'} teslim edin.',
        };
      }

      print('✅ Aktif sipariş yok');

      // ⭐ 2. s_stat kontrolü yap (vardiya durumu s_stat'a bağlı!)
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        return {
          'success': false,
          'message': '❌ Kurye bulunamadı!',
        };
      }

      final courierData = courierQuery.docs.first.data();
      final courierStatus = courierData['s_stat'] as int? ?? 0;

      // ⭐ Eğer zaten OFFLINE ise, vardiya zaten kapalı
      if (courierStatus == 0) {
        return {
          'success': false,
          'message': '⚠️ Vardiya zaten kapalı!',
        };
      }

      // ⭐ 3. s_stat != 0 ise vardiya açık demektir, bitirilebilir
      print('✅ Vardiya açık (s_stat=$courierStatus) - Vardiya bitirilebilir');
      final now = DateTime.now();

      // ⭐ 4. ÖNCE log'u güncelle (s_stat güncellenmeden önce!)
      // ⭐ KRİTİK: getActiveShift() s_stat kontrolü yapıyor, bu yüzden s_stat güncellenmeden önce log'u almalıyız
      final activeLog = await getActiveShift(courierId);
      if (activeLog != null && !activeLog.isClosed) {
        try {
          // Log bulundu, güncelle
          final updatedBreaks = List<BreakSession>.from(activeLog.breaks);
          int finalBreakUsed = activeLog.breakUsedMinutes;

          // Eğer BREAK durumundaysa aktif mola oturumunu kapat
          if (activeLog.status == 'BREAK') {
            final activeBreakIndex = updatedBreaks.indexWhere((b) => b.isActive);
            if (activeBreakIndex != -1) {
              final activeBreak = updatedBreaks[activeBreakIndex];
              final breakMinutes = _calculateBreakMinutes(activeBreak.startAt, now);
              updatedBreaks[activeBreakIndex] = activeBreak.copyWith(
                endAt: now,
                minutes: breakMinutes,
              );
              finalBreakUsed += breakMinutes;
              print('🔚 Aktif mola oturumu kapatıldı: $breakMinutes dk');
            }
          }

          final finalBreakRemaining = (activeLog.breakAllowedMinutes - finalBreakUsed).clamp(0, double.infinity).toInt();

          // ⭐ Vardiya log'unu kapat ve durumu güncelle
          final updateData = {
            'shiftEndAt': Timestamp.fromDate(now),
            'status': 'OFF', // ⭐ Vardiya durumu: OFF (kapalı)
            'isClosed': true, // ⭐ Vardiya kapatıldı
            'closedAt': Timestamp.fromDate(now), // ⭐ Kapanma zamanı
            'breakUsedMinutes': finalBreakUsed, // ⭐ Toplam kullanılan mola
            'breakRemainingMinutes': finalBreakRemaining, // ⭐ Kalan mola
            'breaks': updatedBreaks.map((b) => b.toMap()).toList(), // ⭐ Mola listesi
          };
          
          await _db.collection(_collectionName).doc(activeLog.docId).update(updateData);
          
          print('✅ Vardiya log durumu güncellendi: ${activeLog.docId}');
          print('   status: ${activeLog.status} → OFF');
          print('   isClosed: ${activeLog.isClosed} → true');
          print('   shiftEndAt: ${now.toString()}');
          print('   breakUsedMinutes: ${activeLog.breakUsedMinutes} → $finalBreakUsed dk');
          print('   breakRemainingMinutes: ${activeLog.breakRemainingMinutes} → $finalBreakRemaining dk');
        } catch (logError) {
          // Log güncelleme hatası kritik - vardiya durumu güncellenmedi
          print('❌ ❌ ❌ KRİTİK HATA: Vardiya log güncellenemedi: $logError');
          return {
            'success': false,
            'message': '❌ Vardiya bitirilemedi: Log güncellenemedi',
          };
        }
      } else {
        print('ℹ️ Vardiya log bulunamadı (opsiyonel - sadece s_stat güncellenecek)');
      }

      // ⭐ 5. SONRA t_courier.s_stat'ı OFFLINE (0) yap (vardiya durumu s_stat'a bağlı!)
      // ⭐ ÖNEMLİ: Log güncellendikten sonra s_stat'ı güncelle
      final courierDocRef = courierQuery.docs.first.reference;
      try {
        await courierDocRef.update({
          's_stat': 0, // OFFLINE - Vardiya kapalı
        });
        print('✅ Kurye statüsü güncellendi: s_stat=0 (OFFLINE)');

        // ⭐ Ek güvenlik: Mola timer'ını durdur (otomatik 1'e çekmeyi önle)
        try {
          BreakService().stopAutoEndTimer(courierId);
        } catch (e) {
          print('⚠️ Mola timer durdurma uyarısı: $e');
        }
      } catch (statusError) {
        print('❌ ❌ ❌ KRİTİK HATA: s_stat güncellenemedi: $statusError');
        // ⭐ ROLLBACK: Log güncellendi ama s_stat güncellenemedi - log'u geri al
        if (activeLog != null && !activeLog.isClosed) {
          try {
            await _db.collection(_collectionName).doc(activeLog.docId).update({
              'status': activeLog.status, // Eski status'a geri al
              'isClosed': false, // Eski isClosed'a geri al
            });
            print('✅ Rollback: Log durumu geri alındı');
          } catch (rollbackError) {
            print('❌ Rollback hatası: $rollbackError');
          }
        }
        return {
          'success': false,
          'message': '❌ Vardiya bitirilemedi: Statü güncellenemedi',
        };
      }

      return {
        'success': true,
        'message': '✅ Vardiya bitirildi',
      };
    } catch (e, stackTrace) {
      print('❌ Vardiya bitirme hatası: $e');
      print('Stack trace: $stackTrace');
      
      // ⭐ ROLLBACK: Hata durumunda s_stat'ı kontrol et ve gerekirse geri al
      try {
        final courierQuery = await _db
            .collection('t_courier')
            .where('s_id', isEqualTo: courierId)
            .limit(1)
            .get();
        
        if (courierQuery.docs.isNotEmpty) {
          final currentStatus = courierQuery.docs.first.data()['s_stat'] as int? ?? 0;
          // Eğer s_stat = 0 ise (vardiya kapalı) ama hata oluştu, durumu kontrol et
          // Bu durumda s_stat zaten güncellenmiş olabilir, bu normal
          print('ℹ️ Rollback kontrolü: Mevcut s_stat = $currentStatus');
        }
      } catch (rollbackError) {
        print('❌ Rollback kontrolü hatası: $rollbackError');
      }
      
      return {
        'success': false,
        'message': '❌ Vardiya bitirilemedi: $e',
      };
    }
  }

  /// Aktif vardiya logunu getir
  /// 
  /// ⭐ KRİTİK DEĞİŞİKLİK: Vardiya durumu tamamen t_courier.s_stat'a bağlı!
  /// - s_stat = 0 (OFFLINE) → Vardiya kapalı, null döndür
  /// - s_stat != 0 → Vardiya açık, en son log'u döndür (kayıt amaçlı)
  /// - Log'lar sadece kayıt amaçlı, durum kontrolü için kullanılmaz
  Future<CourierDailyLog?> getActiveShift(int courierId) async {
    try {
      // ⭐ ÖNCE t_courier.s_stat kontrolü yap (önetici tarafından kapatılmış mı?)
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        print('⚠️ Kurye bulunamadı: $courierId');
        return null;
      }

      final courierData = courierQuery.docs.first.data();
      final courierStatus = courierData['s_stat'] as int? ?? 0;
      
      // ⭐ KRİTİK: Vardiya durumu tamamen s_stat'a bağlı!
      // Eğer kurye statüsü OFFLINE (0) ise, vardiya kapalı demektir
      if (courierStatus == 0) {
        print('✅ Kurye statüsü OFFLINE (s_stat=0) - Vardiya kapalı');
        return null;
      }

      // ⭐ s_stat != 0 ise vardiya açık demektir
      // En son log'u bul (kayıt amaçlı, durum kontrolü için değil)
      print('✅ Kurye statüsü aktif (s_stat=$courierStatus) - Vardiya açık, log aranıyor...');

      // ⭐ ÖNEMLİ: s_stat = 1 ama log yoksa, bu bir tutarsızlık olabilir
      // Vardiya başlatma sırasında log oluşturulmadan önce s_stat güncellenmiş olabilir
      // Bu durumda kısa bir bekleme yapıp tekrar dene (log oluşturulana kadar)
      int retryCount = 0;
      const maxRetries = 3;
      const retryDelay = Duration(milliseconds: 500);
      
      CourierDailyLog? foundLog;
      
      while (retryCount < maxRetries && foundLog == null) {
        if (retryCount > 0) {
          print('🔄 Log aranıyor (retry $retryCount/$maxRetries)...');
          await Future.delayed(retryDelay);
        }
        
        // Önce bugünün tarihini kontrol et
        final today = _formatDate(DateTime.now());
        
        // Gece vardiyası kontrolü: Eğer 00:00-02:00 arasındaysa, 
        // bugün ve dün tarihlerini kontrol et
        final now = DateTime.now();
        String? checkDate;
        if (now.hour >= 0 && now.hour < 2) {
          // Gece vardiyası devam ediyor olabilir - dünün tarihini kontrol et
          final yesterday = now.subtract(const Duration(days: 1));
          checkDate = _formatDate(yesterday);
          print('🌙 Gece vardiyası kontrolü - Dünün tarihi: $checkDate');
        } else {
          checkDate = today;
        }

        // Bugünün vardiyasını ara
        final todayQuery = await _db
            .collection(_collectionName)
            .where('courierId', isEqualTo: courierId)
            .where('shiftDate', isEqualTo: checkDate)
            .where('isClosed', isEqualTo: false)
            .limit(1)
            .get();

        if (todayQuery.docs.isNotEmpty) {
          final log = CourierDailyLog.fromFirestore(todayQuery.docs.first);
          // ⭐ ÇİFTE KONTROL: Vardiya log'u var ama isClosed kontrolü (ekstra güvenlik)
          if (!log.isClosed) {
            foundLog = log;
            break;
          } else {
            print('⚠️ ⚠️ ⚠️ Vardiya log bulundu ama isClosed=true - Aktif vardiya yok');
          }
        }

        // Bugünün tarihi bulunamadıysa (gece vardiyası için) bugünü de kontrol et
        if (checkDate != today && foundLog == null) {
          final todayQuery2 = await _db
              .collection(_collectionName)
              .where('courierId', isEqualTo: courierId)
              .where('shiftDate', isEqualTo: today)
              .where('isClosed', isEqualTo: false)
              .limit(1)
              .get();

          if (todayQuery2.docs.isNotEmpty) {
            final log = CourierDailyLog.fromFirestore(todayQuery2.docs.first);
            if (!log.isClosed) {
              foundLog = log;
              break;
            } else {
              print('⚠️ ⚠️ ⚠️ Vardiya log bulundu ama isClosed=true - Aktif vardiya yok');
            }
          }
        }

        // Aktif vardiya yok - ama isClosed=false olan en son vardiyayı kontrol et (fallback)
        // ⭐ Index gerektirmemek için orderBy kaldırıldı, client-side sıralama yapılıyor
        if (foundLog == null) {
          final fallbackQuery = await _db
              .collection(_collectionName)
              .where('courierId', isEqualTo: courierId)
              .where('isClosed', isEqualTo: false)
              .get();

          if (fallbackQuery.docs.isNotEmpty) {
            // Client-side: En yeni vardiyayı bul (shiftStartAt'a göre sırala)
            final logs = fallbackQuery.docs
                .map((doc) => CourierDailyLog.fromFirestore(doc))
                .toList();
            
            // En yeni vardiyayı bul (shiftStartAt'a göre descending)
            logs.sort((a, b) => b.shiftStartAt.compareTo(a.shiftStartAt));
            final log = logs.first;
            
            // ⭐ ÇİFTE KONTROL
            if (!log.isClosed) {
              foundLog = log;
              break;
            } else {
              print('⚠️ ⚠️ ⚠️ Fallback vardiya log bulundu ama isClosed=true - Aktif vardiya yok');
            }
          }
        }
        
        retryCount++;
      }
      
      if (foundLog != null) {
        print('✅ Aktif vardiya log bulundu: ${foundLog.docId}');
        return foundLog;
      }
      
      // ⭐ s_stat = 1 ama log bulunamadı - bu bir tutarsızlık
      // Vardiya başlatma işlemi tamamlanmamış olabilir
      print('⚠️ ⚠️ ⚠️ UYARI: s_stat=$courierStatus (vardiya açık) ama log bulunamadı!');
      print('   Bu durum vardiya başlatma sırasında oluşmuş olabilir.');
      print('   Log henüz oluşturulmamış olabilir veya bir hata oluşmuş olabilir.');
      
      return null;
    } catch (e) {
      print('❌ Aktif vardiya getirme hatası: $e');
      return null;
    }
  }

  /// Vardiya logunu stream olarak dinle (real-time)
  /// 
  /// ⭐ KRİTİK DEĞİŞİKLİK: Vardiya durumu tamamen t_courier.s_stat'a bağlı!
  /// - s_stat = 0 → Vardiya kapalı, null döndür
  /// - s_stat != 0 → Vardiya açık, log'u döndür (kayıt amaçlı)
  /// 
  /// ⭐ NOT: Bu stream sadece log değişikliklerini dinler, asıl durum kontrolü s_stat'tan yapılır.
  Stream<CourierDailyLog?> watchActiveShift(int courierId) {
    // ⭐ KRİTİK DÜZELTME: shiftDate filtresini kaldır, sadece isClosed=false ve courierId ile filtrele
    // En son oluşturulan aktif vardiyayı al (gece vardiyası veya normal vardiya fark etmez)
    // ⭐ NOT: shiftDate filtresi kaldırıldı çünkü gece vardiyası durumunda vardiya dün başlamış olabilir
    // ama bugün devam ediyor olabilir. Bu yüzden sadece isClosed=false kontrolü yeterli.
    // ⭐ NOT: orderBy kullanmıyoruz çünkü Firestore index gerektirebilir, bunun yerine
    // tüm aktif vardiyaları alıp client-side'da en son olanı seçiyoruz
    // ⭐ ÖNCE s_stat kontrolü yap, sonra log'u döndür
    return _db
        .collection('t_courier')
        .where('s_id', isEqualTo: courierId)
        .snapshots()
        .asyncMap((courierSnapshot) async {
      // ⭐ s_stat kontrolü
      if (courierSnapshot.docs.isEmpty) {
        return null;
      }

      final courierData = courierSnapshot.docs.first.data();
      final courierStatus = courierData['s_stat'] as int? ?? 0;
      
      // ⭐ Eğer s_stat = 0 ise, vardiya kapalı demektir
      if (courierStatus == 0) {
        return null;
      }

      // ⭐ s_stat != 0 ise vardiya açık, log'u bul ve döndür
      final logSnapshot = await _db
          .collection(_collectionName)
          .where('courierId', isEqualTo: courierId)
          .where('isClosed', isEqualTo: false)
          .get();

      if (logSnapshot.docs.isEmpty) {
        // Log henüz oluşturulmamış olabilir (vardiya yeni başlatılmış)
        return null;
      }

      // En son başlatılan log'u bul
      CourierDailyLog? latestLog;
      DateTime? latestStartAt;
      
      for (var doc in logSnapshot.docs) {
        final log = CourierDailyLog.fromFirestore(doc);
        if (!log.isClosed) {
          if (latestLog == null || 
              (log.shiftStartAt.isAfter(latestStartAt ?? DateTime(1970)))) {
            latestLog = log;
            latestStartAt = log.shiftStartAt;
          }
        }
      }
      
      return latestLog;
    });
  }

  /// Kurye profilinden breakAllowedMinutes değerini al
  /// 
  /// t_courier collection'ındaki s_break_duration field'ından okur
  /// Yoksa default 60 dakika döner
  Future<int> getBreakAllowedMinutes(int courierId) async {
    try {
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        print('⚠️ Kurye bulunamadı, default breakAllowed=60 dk');
        return 60;
      }

      final courierData = courierQuery.docs.first.data();
      // ⭐ s_break_duration field'ından oku
      final breakAllowedRaw = courierData['s_break_duration'];
      
      // Tip güvenli dönüşüm (int veya String olabilir)
      int breakAllowed = 60; // Default
      if (breakAllowedRaw is int) {
        breakAllowed = breakAllowedRaw;
      } else if (breakAllowedRaw is String) {
        breakAllowed = int.tryParse(breakAllowedRaw) ?? 60;
      } else if (breakAllowedRaw != null) {
        // Diğer tipler için
        breakAllowed = (breakAllowedRaw as num).toInt();
      }
      
      print('✅ Kurye profilinden s_break_duration: $breakAllowed dk (courierId=$courierId)');
      return breakAllowed;
    } catch (e) {
      print('❌ s_break_duration alma hatası: $e, default=60 dk');
      return 60;
    }
  }

  /// 🔍 Vardiya Bilgilerini Getir (t_shift collection'ından)
  Future<Map<String, dynamic>> _getShiftInfo(int shiftId, int bayId) async {
    try {
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

  /// 📅 Bugünün Vardiya Saatlerini Al
  Map<String, dynamic> _getTodayShiftTimes(Map<String, dynamic> shiftData) {
    final today = DateTime.now().weekday % 7; // 0: Pazar, 1: Pazartesi, ...
    final dayName = dayNames[today] ?? 'ss_pazartesi';
    
    final shifts = shiftData['s_shifts'] as Map<String, dynamic>?;
    if (shifts == null || !shifts.containsKey(dayName)) {
      return {
        'hasShift': false,
        'startTime': '00:00', // ⭐ Android mantığı: Vardiya tanımı yoksa 00:00 - 00:00 döndür
        'endTime': '00:00',
        'startMinutes': 0,
        'endMinutes': 0,
      };
    }

    final todayTimes = shifts[dayName] as List<dynamic>;
    if (todayTimes.length < 2) {
      print('❌ Vardiya saatleri geçersiz');
      return {'hasShift': false};
    }

    final startTime = todayTimes[0] as String;
    final endTime = todayTimes[1] as String;

    // ["00:00", "00:00"] = Kapalı gün (ama Android mantığı: saatleri döndür)
    if (startTime == "00:00" && endTime == "00:00") {
      return {
        'hasShift': false,
        'startTime': startTime, // ⭐ Android mantığı: Saatleri döndür
        'endTime': endTime, // ⭐ Android mantığı: Saatleri döndür
        'startMinutes': _timeToMinutes(startTime),
        'endMinutes': _timeToMinutes(endTime),
      };
    }

    return {
      'hasShift': true,
      'startTime': startTime,
      'endTime': endTime,
      'startMinutes': _timeToMinutes(startTime),
      'endMinutes': _timeToMinutes(endTime),
    };
  }

  /// ⏰ Şu Anki Zamanı Dakikaya Çevir
  int _getCurrentTimeInMinutes() {
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    print('⏰ Şu anki saat: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ($minutes dakika)');
    return minutes;
  }

  /// 🕐 Saat String'ini Dakikaya Çevir
  int _timeToMinutes(String timeString) {
    final parts = timeString.split(':');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    return hours * 60 + minutes;
  }

  /// 📅 Bugünün Vardiya Bilgilerini Getir (Public - UI için)
  /// Returns: { hasShift: bool, startTime: String?, endTime: String?, message: String? }
  Future<Map<String, dynamic>> getTodayShiftInfo(int courierId) async {
    try {
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        return {
          'hasShift': false,
          'startTime': '00:00', // ⭐ Android mantığı: Hata durumunda da saatleri döndür
          'endTime': '00:00',
          'message': '❌ Kullanıcı bulunamadı',
        };
      }

      final courierData = courierQuery.docs.first.data();
      final shiftIdRaw = courierData['t_shift'];
      final int? shiftId = shiftIdRaw is int 
          ? shiftIdRaw 
          : (shiftIdRaw is String ? int.tryParse(shiftIdRaw) : null);

      if (shiftId == null) {
        return {
          'hasShift': false,
          'startTime': '00:00', // ⭐ Android mantığı: Hata durumunda da saatleri döndür
          'endTime': '00:00',
          'message': '⚠️ Vardiya tanımı atanmamış',
        };
      }

      final courierBayIdRaw = courierData['s_bay'];
      final int? courierBayId = courierBayIdRaw is int 
          ? courierBayIdRaw 
          : (courierBayIdRaw is String ? int.tryParse(courierBayIdRaw) : null);

      if (courierBayId == null) {
        return {
          'hasShift': false,
          'startTime': '00:00', // ⭐ Android mantığı: Hata durumunda da saatleri döndür
          'endTime': '00:00',
          'message': '⚠️ Bay ID bulunamadı',
        };
      }

      final shiftInfoResult = await _getShiftInfo(shiftId, courierBayId);
      if (!shiftInfoResult['success']) {
        return {
          'hasShift': false,
          'startTime': '00:00', // ⭐ Android mantığı: Hata durumunda da saatleri döndür
          'endTime': '00:00',
          'message': shiftInfoResult['message'] as String,
        };
      }

      final shiftData = shiftInfoResult['data'] as Map<String, dynamic>;
      final todayShiftTimes = _getTodayShiftTimes(shiftData);

      // ⭐ Android mantığı: hasShift: false olsa bile startTime ve endTime değerlerini döndür
      // (00:00 - 00:00 durumunda UI'da "HAZIR" durumu göstermek için)
      return {
        'hasShift': todayShiftTimes['hasShift'] as bool,
        'startTime': todayShiftTimes['startTime'] as String? ?? "00:00", // ⭐ Null ise 00:00 döndür
        'endTime': todayShiftTimes['endTime'] as String? ?? "00:00", // ⭐ Null ise 00:00 döndür
        'startMinutes': todayShiftTimes['startMinutes'] as int?,
        'endMinutes': todayShiftTimes['endMinutes'] as int?,
      };
    } catch (e) {
      print('❌ Bugünün vardiya bilgisi alma hatası: $e');
      return {
        'hasShift': false,
        'startTime': '00:00', // ⭐ Android mantığı: Hata durumunda da saatleri döndür
        'endTime': '00:00',
        'message': '❌ Vardiya bilgisi alınamadı: $e',
      };
    }
  }

  /// Tarihi YYYY-MM-DD formatına çevir
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }


  /// Mola dakikasını hesapla (ceil/round tutarlı)
  /// 
  /// Doğru ceil mantığı: Saniye varsa yukarı yuvarla
  /// Örnekler:
  /// - 0-59 saniye → 0 dk (veya 1 dk - eğer 1 dakikadan azsa 0, değilse 1)
  /// - 60-119 saniye → 2 dk
  /// - 120-179 saniye → 3 dk
  int _calculateBreakMinutes(DateTime startAt, DateTime endAt) {
    final duration = endAt.difference(startAt);
    final totalSeconds = duration.inSeconds;
    
    if (totalSeconds <= 0) {
      return 0;
    }
    
    // Ceil mantığı: Saniye varsa yukarı yuvarla
    // Örnek: 121 saniye = 2 dakika 1 saniye → 3 dk (ceil)
    // Örnek: 120 saniye = 2 dakika tam → 2 dk (tam dakika)
    final minutes = totalSeconds ~/ 60; // Tam dakika
    final remainingSeconds = totalSeconds % 60; // Kalan saniye
    
    // Eğer kalan saniye varsa yukarı yuvarla (ceil)
    if (remainingSeconds > 0) {
      return minutes + 1;
    }
    
    // Tam dakika ise direkt dakikayı döndür
    return minutes;
  }
}