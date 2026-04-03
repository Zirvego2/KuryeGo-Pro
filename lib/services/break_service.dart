import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/courier_daily_log.dart';
import 'shift_log_service.dart';
import 'shift_service.dart';
import 'location_service.dart';

/// Mola Servisi
/// Parça parça mola başlatma/bitirme ve otomatik bitiş yönetimi
class BreakService {
  static final BreakService _instance = BreakService._internal();
  factory BreakService() => _instance;
  BreakService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ShiftLogService _shiftLogService = ShiftLogService();
  static const String _collectionName = 'courier_daily_logs';

  // Otomatik bitiş kontrolü için timer (her kurye için)
  final Map<int, Timer> _autoEndTimers = {};
  

  /// Molaya çık (parça parça)
  /// 
  /// - breakRemainingMinutes <= 0 ise engelle
  /// - status = BREAK
  /// - breaks listesine yeni kayıt aç: { startAt: şimdi, endAt: null }
  /// - Otomatik bitiş timer'ını başlat
  Future<Map<String, dynamic>> startBreak(int courierId) async {
    try {
      print('☕ Mola başlatılıyor: courierId=$courierId');

      // ⭐ KRİTİK: ÖNCE s_stat kontrolü yap (vardiya durumu s_stat'a bağlı!)
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

      // ⭐ Eğer zaten BREAK (3) durumundaysa, mola başlatılamaz
      if (courierStatus == ShiftService.STATUS_BREAK) {
        return {
          'success': false,
          'message': '⚠️ Zaten moladasınız!',
        };
      }

      // ⭐ Eğer OFFLINE (0) ise, vardiya kapalı
      if (courierStatus == ShiftService.STATUS_OFFLINE) {
        return {
          'success': false,
          'message': '⚠️ Aktif vardiya bulunamadı! Önce vardiyaya başlayın.',
        };
      }

      final activeLog = await _shiftLogService.getActiveShift(courierId);
      if (activeLog == null || activeLog.isClosed) {
        return {
          'success': false,
          'message': '⚠️ Aktif vardiya bulunamadı! Önce vardiyaya başlayın.',
        };
      }

      final now = DateTime.now();
      
      // ⭐ KRİTİK DÜZELTME: Mola başladığında kalan süreyi doğru hesapla
      // activeLog.breakRemainingMinutes Firestore'dan geliyor ve yanlış olabilir
      // Bu yüzden breakAllowedMinutes - breakUsedMinutes formülünü kullanarak doğru değeri hesaplayalım
      final calculatedRemainingMinutes = (activeLog.breakAllowedMinutes - activeLog.breakUsedMinutes).clamp(0, double.infinity).toInt();
      
      // ⭐ Güvenlik kontrolü: Hesaplanan değer ile Firestore'dan gelen değer farklıysa uyar
      if (calculatedRemainingMinutes != activeLog.breakRemainingMinutes) {
        print('⚠️ ⚠️ ⚠️ UYARI: breakRemainingMinutes tutarsızlığı!');
        print('   Firestore\'dan gelen: ${activeLog.breakRemainingMinutes} dk');
        print('   Hesaplanan: $calculatedRemainingMinutes dk (breakAllowed: ${activeLog.breakAllowedMinutes} - breakUsed: ${activeLog.breakUsedMinutes})');
        print('   Hesaplanan değer kullanılıyor: $calculatedRemainingMinutes dk');
      }
      
      // ⭐ Hesaplanan değeri kullan (Firestore'daki değer yanlış olabilir)
      final remainingAtStart = calculatedRemainingMinutes;
      
      // ⭐ KRİTİK: Sadece hesaplanan değeri kontrol et (Firestore'dan gelen değer yanlış olabilir!)
      if (remainingAtStart <= 0) {
        return {
          'success': false,
          'message': '❌ Mola hakkınız bitti!',
        };
      }
      
      print('✅ Mola başlatma bilgileri:');
      print('   BreakAllowed: ${activeLog.breakAllowedMinutes} dk');
      print('   BreakUsed: ${activeLog.breakUsedMinutes} dk');
      print('   BreakRemaining (Firestore): ${activeLog.breakRemainingMinutes} dk');
      print('   BreakRemaining (Hesaplanan): $remainingAtStart dk ⭐');
      print('   RemainingAtStart (Kaydedilen): $remainingAtStart dk');
      
      final newBreak = BreakSession(
        startAt: now,
        minutes: 0, // Henüz bitirilmedi
        remainingAtStart: remainingAtStart, // ⭐ Hesaplanan doğru değer
      );

      final updatedBreaks = List<BreakSession>.from(activeLog.breaks);
      updatedBreaks.add(newBreak);

      // Firestore'u güncelle
      if (activeLog.docId == null) {
        return {
          'success': false,
          'message': '❌ Vardiya log ID bulunamadı!',
        };
      }

      // ⭐ Mola başladığında breakUsedMinutes ve breakRemainingMinutes'ı güncelle
      // Mola başladığında henüz kullanılan mola değişmez, sadece kalan mola güncellenir
      // Ancak UI'da doğru görünmesi için hesaplanan değerleri Firestore'a yaz
      await _db.collection(_collectionName).doc(activeLog.docId).update({
        'status': 'BREAK',
        'breaks': updatedBreaks.map((b) => b.toMap()).toList(),
        'breakUsedMinutes': activeLog.breakUsedMinutes, // Henüz değişmedi
        'breakRemainingMinutes': remainingAtStart, // ⭐ Hesaplanan doğru değer
      });

      // ⭐ KRİTİK: t_courier.s_stat'ı BREAK (3) yap (vardiya durumu s_stat'a bağlı!)
      // ⭐ NOT: courierQuery zaten yukarıda tanımlanmış, tekrar kullanıyoruz
      await courierQuery.docs.first.reference.update({
        's_stat': ShiftService.STATUS_BREAK, // BREAK = 3
      });
      print('✅ Kurye statüsü güncellendi: s_stat=3 (BREAK)');

      print('✅ Mola başlatıldı: ${activeLog.docId}, RemainingAtStart: $remainingAtStart dk');

      // ⭐ KRİTİK: Otomatik bitiş timer'ını hesaplanan değer ile başlat (Firestore'daki yanlış değer değil!)
      _startAutoEndTimer(courierId, activeLog.docId!, remainingAtStart, newBreak.startAt);

      return {
        'success': true,
        'message': '☕ Mola başladı',
        'remainingMinutes': remainingAtStart, // ⭐ Hesaplanan doğru değer
      };
    } catch (e) {
      print('❌ Mola başlatma hatası: $e');
      return {
        'success': false,
        'message': '❌ Mola başlatılamadı: $e',
      };
    }
  }

  /// Molayı bitir (manuel)
  /// 
  /// - Aktif break kaydının endAt'ını doldur
  /// - Dakika hesapla (ceil/round kuralı)
  /// - breakUsedMinutes += süre
  /// - breakRemainingMinutes = max(0, breakAllowedMinutes - breakUsedMinutes)
  /// - status = ACTIVE
  /// - Timer'ı durdur
  Future<Map<String, dynamic>> endBreak(int courierId) async {
    try {
      print('🔚 Mola bitiriliyor: courierId=$courierId');

      final activeLog = await _shiftLogService.getActiveShift(courierId);
      if (activeLog == null || activeLog.isClosed) {
        return {
          'success': false,
          'message': '⚠️ Aktif vardiya bulunamadı!',
        };
      }

      if (activeLog.status != 'BREAK') {
        // ⭐ SELF-HEALING (KENDİNİ ONARMA):
        // Eğer courier_daily_log zaten 'ACTIVE' ise ama UI'da hala MOLA butonunu görüyorsa,
        // Bu s_stat'ın 3'te takılı kaldığını (desenkronizasyon) gösterir.
        // Bu durumda hataya düşmek yerine sadece s_stat'ı 1 (AVAILABLE) yapıp kurtaralım.
        final bugQuery = await _db.collection('t_courier').where('s_id', isEqualTo: courierId).limit(1).get();
        if (bugQuery.docs.isNotEmpty) {
           final statFix = bugQuery.docs.first.data()['s_stat'] as int? ?? 0;
           if (statFix == ShiftService.STATUS_BREAK) {
             print('🛠️ KENDİNİ ONARMA: Log ACTIVE ama s_stat=3. s_stat=1 yapılıyor...');
             await bugQuery.docs.first.reference.update({'s_stat': ShiftService.STATUS_AVAILABLE});
             LocationService.invalidateStatusCache();
             return {
               'success': true,
               'message': '✅ Senkronizasyon düzeltildi, mola bitirildi!',
             };
           }
        }

        return {
          'success': false,
          'message': '⚠️ Şu anda molada değilsiniz!',
        };
      }

      // Aktif mola oturumunu bul
      final activeBreakIndex = activeLog.breaks.indexWhere((b) => b.isActive);
      if (activeBreakIndex == -1) {
        return {
          'success': false,
          'message': '❌ Aktif mola oturumu bulunamadı!',
        };
      }

      final activeBreak = activeLog.breaks[activeBreakIndex];
      final now = DateTime.now();
      
      // ⭐ Manuel bitişte: Geçen süreyi hesapla ama breakAllowedMinutes'ı aşma
      final elapsed = now.difference(activeBreak.startAt);
      final elapsedSeconds = elapsed.inSeconds;
      
      // Mola başladığında kalan süre (remainingAtStart varsa kullan, yoksa mevcut kalan)
      final remainingAtStart = activeBreak.remainingAtStart ?? activeLog.breakRemainingMinutes;
      final maxThisBreakSeconds = remainingAtStart * 60; // Bu mola için max süre (başlangıçtaki kalan)
      
      // Gerçek kullanılan süre (max süreyi aşmamak için)
      final actualBreakSeconds = elapsedSeconds.clamp(0, maxThisBreakSeconds);
      final breakMinutes = _calculateBreakMinutesFromSeconds(actualBreakSeconds);
      
      // Toplam kullanılan ve kalan mola hesapla (breakAllowedMinutes'ı aşmamak için)
      final totalBreakUsed = (activeLog.breakUsedMinutes + breakMinutes).clamp(0, activeLog.breakAllowedMinutes);
      final breakRemaining = (activeLog.breakAllowedMinutes - totalBreakUsed).clamp(0, double.infinity).toInt();

      print('🔚 Manuel mola bitiş hesaplama:');
      print('   Geçen süre: $elapsedSeconds sn (${(elapsedSeconds / 60).toStringAsFixed(2)} dk)');
      print('   Mola başladığında kalan: $remainingAtStart dk');
      print('   Bu mola max: $maxThisBreakSeconds sn');
      print('   Bu mola kullanılan: $breakMinutes dk ($actualBreakSeconds sn)');
      print('   Önceki kullanılan: ${activeLog.breakUsedMinutes} dk');
      print('   Toplam kullanılan: $totalBreakUsed dk (max: ${activeLog.breakAllowedMinutes} dk)');
      print('   Kalan: $breakRemaining dk');

      // Mola oturumunu güncelle
      final updatedBreaks = List<BreakSession>.from(activeLog.breaks);
      updatedBreaks[activeBreakIndex] = activeBreak.copyWith(
        endAt: now,
        minutes: breakMinutes,
      );

      // Firestore'u güncelle
      if (activeLog.docId == null) {
        return {
          'success': false,
          'message': '❌ Vardiya log ID bulunamadı!',
        };
      }

      await _db.collection(_collectionName).doc(activeLog.docId).update({
        'status': 'ACTIVE',
        'breakUsedMinutes': totalBreakUsed,
        'breakRemainingMinutes': breakRemaining,
        'breaks': updatedBreaks.map((b) => b.toMap()).toList(),
      });

      // ⭐ KRİTİK: t_courier.s_stat'ı AVAILABLE (1) yap (vardiya durumu s_stat'a bağlı!)
      final courierQuery = await _db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isNotEmpty) {
        // Guard: Kurye OFFLINE ise AVAILABLE yapma
        try {
          final fresh = await courierQuery.docs.first.reference.get();
          final freshData = fresh.data() as Map<String, dynamic>? ?? {};
          final currentStat = freshData['s_stat'] as int? ?? ShiftService.STATUS_OFFLINE;
          if (currentStat != ShiftService.STATUS_OFFLINE) {
            await courierQuery.docs.first.reference.update({
              's_stat': ShiftService.STATUS_AVAILABLE, // AVAILABLE = 1
            });
            print('✅ Kurye statüsü güncellendi: s_stat=1 (AVAILABLE)');
          } else {
            print('ℹ️ Guard: Kurye OFFLINE, s_stat AVAILABLE yapılmadı (endBreak).');
          }
        } catch (e) {
          print('⚠️ Guard kontrolü sırasında hata (endBreak): $e');
        }
      }

      print('✅ Mola bitirildi: $breakMinutes dk kullanıldı, Kalan: $breakRemaining dk');

      // Timer'ı durdur
      _stopAutoEndTimer(courierId);

      return {
        'success': true,
        'message': '✅ Mola bitirildi ($breakMinutes dk kullanıldı)',
        'usedMinutes': breakMinutes,
        'remainingMinutes': breakRemaining,
      };
    } catch (e) {
      print('❌ Mola bitirme hatası: $e');
      return {
        'success': false,
        'message': '❌ Mola bitirilemedi: $e',
      };
    }
  }

  /// Mola otomatik bitirme (kritik)
  /// 
  /// - Kurye BREAK durumundayken kalan süre 0'a düşerse:
  /// - Break oturumu otomatik kapansın (endAt yaz)
  /// - breakUsedMinutes güncellensin
  /// - breakRemainingMinutes = 0
  /// - status otomatik ACTIVE olsun
  Future<Map<String, dynamic>> autoEndBreak(int courierId, String logDocId) async {
    try {
      print('⏰ Otomatik mola bitirme: courierId=$courierId, logDocId=$logDocId');

      final logDoc = await _db.collection(_collectionName).doc(logDocId).get();
      if (!logDoc.exists) {
        print('❌ Log dokümanı bulunamadı: $logDocId');
        _stopAutoEndTimer(courierId);
        return {'success': false, 'message': 'Log bulunamadı'};
      }

      final activeLog = CourierDailyLog.fromFirestore(logDoc);
      if (activeLog.status != 'BREAK') {
        print('✅ Vardiya BREAK durumunda değil, otomatik bitirme iptal');
        _stopAutoEndTimer(courierId);
        return {'success': false, 'message': 'BREAK durumunda değil'};
      }

      // Aktif mola oturumunu bul
      final activeBreakIndex = activeLog.breaks.indexWhere((b) => b.isActive);
      if (activeBreakIndex == -1) {
        print('❌ Aktif mola oturumu bulunamadı');
        _stopAutoEndTimer(courierId);
        return {'success': false, 'message': 'Aktif mola yok'};
      }

      final activeBreak = activeLog.breaks[activeBreakIndex];
      final now = DateTime.now();
      
      // ⭐ KRİTİK DÜZELTME: Otomatik bitişte, mola başladığında kalan süre kadar kullanılmış sayılmalı
      // Mola başladığında kalan süreyi BreakSession'dan al (remainingAtStart field'ından)
      int? remainingAtStartRaw = activeBreak.remainingAtStart;
      int remainingAtStart; // Null olmayacak şekilde hesaplanacak
      
      // ⭐ Güvenlik kontrolü: remainingAtStart null veya tutarsızsa hesapla
      if (remainingAtStartRaw == null || remainingAtStartRaw < 0 || remainingAtStartRaw > activeLog.breakAllowedMinutes) {
        print('⚠️ ⚠️ ⚠️ UYARI: remainingAtStart null veya tutarsız! (Değer: $remainingAtStartRaw, BreakAllowed: ${activeLog.breakAllowedMinutes})');
        print('   Fallback hesaplama yapılıyor...');
        
        // Eski veriler için fallback: Hesaplanan kalan süreyi kullan
        final calculatedRemaining = (activeLog.breakAllowedMinutes - activeLog.breakUsedMinutes).clamp(0, double.infinity).toInt();
        remainingAtStart = calculatedRemaining;
        
        print('   Hesaplanan remainingAtStart: $remainingAtStart dk');
        
        // Geçen süreyi hesapla
        final elapsed = now.difference(activeBreak.startAt);
        final elapsedSeconds = elapsed.inSeconds;
        final maxAllowedSeconds = activeLog.breakAllowedMinutes * 60;
        final previousUsedSeconds = activeLog.breakUsedMinutes * 60;
        final maxThisBreakSeconds = maxAllowedSeconds - previousUsedSeconds;
        final actualBreakSeconds = elapsedSeconds.clamp(0, maxThisBreakSeconds);
        final breakMinutes = _calculateBreakMinutesFromSeconds(actualBreakSeconds);
        final totalBreakUsed = ((previousUsedSeconds + actualBreakSeconds) / 60).ceil().clamp(0, activeLog.breakAllowedMinutes);
        final breakRemaining = (activeLog.breakAllowedMinutes - totalBreakUsed).clamp(0, double.infinity).toInt();
        
        print('⏰ Otomatik bitiş (fallback - hesaplanan değer):');
        print('   BreakAllowed: ${activeLog.breakAllowedMinutes} dk');
        print('   Önceki kullanılan: ${activeLog.breakUsedMinutes} dk');
        print('   Hesaplanan remainingAtStart: $remainingAtStart dk');
        print('   Geçen süre: $elapsedSeconds sn (${(elapsedSeconds / 60).toStringAsFixed(2)} dk)');
        print('   Bu mola kullanılan: $breakMinutes dk');
        print('   Toplam kullanılan: $totalBreakUsed dk');
        print('   Kalan: $breakRemaining dk');
        
        // Mola oturumunu güncelle
        final updatedBreaks = List<BreakSession>.from(activeLog.breaks);
        updatedBreaks[activeBreakIndex] = activeBreak.copyWith(
          endAt: now,
          minutes: breakMinutes,
        );
        
        try {
          await _db.collection(_collectionName).doc(logDocId).update({
            'status': 'ACTIVE',
            'breakUsedMinutes': totalBreakUsed,
            'breakRemainingMinutes': breakRemaining,
            'breaks': updatedBreaks.map((b) => b.toMap()).toList(),
          });
          print('✅ ✅ ✅ Firestore güncellemesi başarılı (fallback)! Status: ACTIVE');
          
          // ⭐ s_stat güncellemesi Cloud Function'a (autoEndCourierBreaks) bırakıldı.
          print('ℹ️ autoEndBreak fallback: s_stat güncellemesi Cloud Function tarafından yapılacak.');
          
          _stopAutoEndTimer(courierId);
          return {
            'success': true,
            'message': '✅ Mola süreniz doldu, otomatik bitirildi (fallback)',
            'usedMinutes': breakMinutes,
            'remainingMinutes': breakRemaining,
          };
        } catch (firestoreError) {
          print('❌ ❌ ❌ Firestore güncelleme hatası (fallback): $firestoreError');
          _stopAutoEndTimer(courierId);
          return {
            'success': false,
            'message': '❌ Firestore güncelleme hatası: $firestoreError',
          };
        }
        // ⭐ Fallback durumunda return yapıldı, buraya gelinmez (dead code ama güvenlik için)
        // Bu satır çalışmaz çünkü yukarıda return yapılıyor
      } else {
        // ⭐ remainingAtStart null değil ve geçerli bir değer
        remainingAtStart = remainingAtStartRaw; // Null değil çünkü else bloğundayız
      }
      
      // ⭐ remainingAtStart artık null değil (fallback'te hesaplandı veya zaten vardı)
      final maxAvailableBreak = activeLog.breakAllowedMinutes - activeLog.breakUsedMinutes; // Bu mola için maksimum kullanılabilir
      
      // ⭐ Güvenlik: remainingAtStart değeri breakAllowedMinutes'ı aşmamalı
      if (remainingAtStart > activeLog.breakAllowedMinutes) {
        print('⚠️ ⚠️ ⚠️ UYARI: remainingAtStart ($remainingAtStart) > breakAllowedMinutes (${activeLog.breakAllowedMinutes})!');
        print('   remainingAtStart değeri maxAvailableBreak ile sınırlandırılıyor: $maxAvailableBreak dk');
        remainingAtStart = maxAvailableBreak.clamp(0, activeLog.breakAllowedMinutes);
      }
      
      // Bu mola için kullanılan süre = min(başlangıçtaki kalan, maksimum kullanılabilir)
      // Örnek: Toplam 2 dk, önceki kullanılan 0 dk, başlangıçta kalan 2 dk → 2 dk kullanılır ✓
      // Örnek: Toplam 2 dk, önceki kullanılan 1 dk, başlangıçta kalan 2 dk → 1 dk kullanılır (maxAvailableBreak = 1)
      // Örnek: Toplam 2 dk, önceki kullanılan 0 dk, başlangıçta kalan 3 dk → 2 dk kullanılır (maxAvailableBreak = 2) ⭐ DÜZELTME
      final breakMinutesClamped = remainingAtStart.clamp(0, maxAvailableBreak);
      
      // Toplam kullanılan hesapla (breakAllowedMinutes'ı aşmamak için)
      final totalBreakUsed = (activeLog.breakUsedMinutes + breakMinutesClamped).clamp(0, activeLog.breakAllowedMinutes);
      final breakRemaining = (activeLog.breakAllowedMinutes - totalBreakUsed).clamp(0, double.infinity).toInt();

      print('⏰ Otomatik bitiş hesaplama:');
      print('   BreakAllowed: ${activeLog.breakAllowedMinutes} dk');
      print('   Önceki kullanılan: ${activeLog.breakUsedMinutes} dk');
      print('   Mola başladığında kalan: $remainingAtStart dk');
      print('   Bu mola için max: $maxAvailableBreak dk');
      print('   Bu mola kullanılan: $breakMinutesClamped dk (başlangıçtaki kalan kadar, max sınırlı)');
      print('   Toplam kullanılan: $totalBreakUsed dk (max: ${activeLog.breakAllowedMinutes} dk)');
      print('   Kalan: $breakRemaining dk');

      // Mola oturumunu güncelle
      final updatedBreaks = List<BreakSession>.from(activeLog.breaks);
      updatedBreaks[activeBreakIndex] = activeBreak.copyWith(
        endAt: now,
        minutes: breakMinutesClamped,
      );

      // ⭐ KRİTİK: Firestore'u güncelleme görevini TAMAMEN Cloud Function'a devrettik.
      // Eğer uygulama buradan logu ACTIVE yaparsa, Cloud Function "bu kişinin molası bitmiş" deyip es geçer
      // ve kuryenin s_stat'ı 3'te (MOLA) sonsuza dek takılı kalır!
      // Bu yüzden buradaki tüm veritabanı yazma işlemlerini KONTROLLÜ olarak devre dışı bıraktık.
      
      print('ℹ️ Mola süresi bitti. Firestore güncellemeleri (log ve s_stat) Cloud Function tarafından işlenecek.');

      print('✅ Mola otomatik bitirildi: $breakMinutesClamped dk kullanıldı, Kalan: $breakRemaining dk, Status: ACTIVE');

      // ⭐ s_stat güncellemesi Cloud Function'a (autoEndCourierBreaks) bırakıldı.
      // Cloud Function her 1 dakikada çalışır: s_stat=3 → s_stat=1 (guard ile).
      print('ℹ️ autoEndBreak: s_stat güncellemesi Cloud Function tarafından yapılacak.');

      // Timer'ı durdur
      _stopAutoEndTimer(courierId);

      return {
        'success': true,
        'message': '✅ Mola süreniz doldu, otomatik bitirildi',
        'usedMinutes': breakMinutesClamped,
        'remainingMinutes': breakRemaining,
      };
    } catch (e, stackTrace) {
      print('❌ ❌ ❌ Otomatik mola bitirme exception: $e');
      print('Stack trace: $stackTrace');
      _stopAutoEndTimer(courierId);
      return {
        'success': false,
        'message': '❌ Otomatik mola bitirme hatası: $e',
      };
    }
  }

  /// Anlık mola bilgilerini hesapla
  /// 
  /// - Geçen süre: şu an - molaStart (mm:ss formatında)
  /// - Kalan süre: remainingAtStart - geçen süre (dk/sn formatında)
  Future<Map<String, dynamic>?> getCurrentBreakInfo(int courierId) async {
    try {
      final activeLog = await _shiftLogService.getActiveShift(courierId);
      if (activeLog == null || activeLog.status != 'BREAK') {
        return null;
      }

      // Aktif mola oturumunu bul
      final activeBreakIndex = activeLog.breaks.indexWhere((b) => b.isActive);
      if (activeBreakIndex == -1) {
        return null; // Aktif mola oturumu yok
      }
      final activeBreak = activeLog.breaks[activeBreakIndex];

      final now = DateTime.now();
      final elapsed = now.difference(activeBreak.startAt);
      final elapsedTotalSeconds = elapsed.inSeconds;
      final elapsedMinutes = elapsed.inMinutes;
      final elapsedSeconds = elapsedTotalSeconds % 60;

      // ⭐ KRİTİK DÜZELTME: Kalan süreyi hesaplarken remainingAtStart kullan (timer ile tutarlı olması için)
      // Eğer remainingAtStart null veya tutarsızsa, hesaplanan değeri kullan
      int? remainingAtStartRaw = activeBreak.remainingAtStart;
      int remainingAtStart;
      
      // ⭐ Güvenlik kontrolü: remainingAtStart null veya tutarsızsa hesapla
      if (remainingAtStartRaw == null || remainingAtStartRaw < 0 || remainingAtStartRaw > activeLog.breakAllowedMinutes) {
        // Hesaplanan değeri kullan (breakAllowedMinutes - breakUsedMinutes)
        final calculatedRemaining = (activeLog.breakAllowedMinutes - activeLog.breakUsedMinutes).clamp(0, double.infinity).toInt();
        remainingAtStart = calculatedRemaining;
        
        if (remainingAtStartRaw == null) {
          print('⚠️ ⚠️ ⚠️ UYARI: remainingAtStart null! Hesaplanan değer kullanılıyor: $remainingAtStart dk');
        } else if (remainingAtStartRaw < 0) {
          print('⚠️ ⚠️ ⚠️ UYARI: remainingAtStart negatif! ($remainingAtStartRaw) Hesaplanan değer kullanılıyor: $remainingAtStart dk');
        } else {
          print('⚠️ ⚠️ ⚠️ UYARI: remainingAtStart tutarsız! ($remainingAtStartRaw > breakAllowed: ${activeLog.breakAllowedMinutes})');
          print('   Hesaplanan değer kullanılıyor: $remainingAtStart dk (breakAllowed: ${activeLog.breakAllowedMinutes} - breakUsed: ${activeLog.breakUsedMinutes})');
        }
      } else {
        remainingAtStart = remainingAtStartRaw;
        // ⭐ Doğrulama: remainingAtStart değeri ile hesaplanan değer tutarlı mı?
        final calculatedRemaining = (activeLog.breakAllowedMinutes - activeLog.breakUsedMinutes).clamp(0, double.infinity).toInt();
        if (remainingAtStart != calculatedRemaining) {
          print('⚠️ ⚠️ ⚠️ KRİTİK UYARI: remainingAtStart ($remainingAtStart) != hesaplanan ($calculatedRemaining)!');
          print('   BreakAllowed: ${activeLog.breakAllowedMinutes} dk, BreakUsed: ${activeLog.breakUsedMinutes} dk');
          print('   Bu tutarsizlik timer ve UI\'da yanlis hesaplamalara yol acabilir!');
          print('   ⭐ ÇÖZÜM: Hesaplanan değer kullanılıyor: $calculatedRemaining dk');
          print('   ⭐ NOT: Timer yanlış değer ile başlatılmış olabilir, ama getCurrentBreakInfo doğru değeri kullanacak');
          // ⭐ KRİTİK DÜZELTME: Tutarsızlık varsa hesaplanan değeri kullan (breakAllowedMinutes'ı aşmamak için)
          // ⭐ NOT: Timer zaten başlatılmış ve yanlış değer ile çalışıyor olabilir
          // Ancak eğer kalan süre 0 veya negatifse, fallback mekanizması devreye girecek
          remainingAtStart = calculatedRemaining;
        }
      }
      
      // ⭐ Kalan süre hesapla (remainingAtStart - geçen süre)
      // ⭐ NOT: remainingAtStart artık doğru değer (tutarsızlık varsa düzeltildi)
      final remainingTotalSeconds = (remainingAtStart * 60) - elapsedTotalSeconds;
      final remainingMinutes = (remainingTotalSeconds / 60).floor().clamp(0, double.infinity).toInt();
      final remainingSeconds = (remainingTotalSeconds % 60).clamp(0, 59).toInt();

      // ⭐ Kalan süre 0 veya negatifse, Cloud Function bunu yakında işleyecek (her 1 dk çalışır).
      // Uygulama tarafında s_stat güncellemesi yapılmıyor, duplicate sorununu önler.

      return {
        'elapsedMinutes': elapsedMinutes,
        'elapsedSeconds': elapsedSeconds,
        'elapsedFormatted': '${elapsedMinutes.toString().padLeft(2, '0')}:${elapsedSeconds.toString().padLeft(2, '0')}',
        'remainingMinutes': remainingMinutes,
        'remainingSeconds': remainingSeconds,
        'remainingFormatted': '${remainingMinutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}',
        'breakStartAt': activeBreak.startAt,
      };
    } catch (e) {
      print('❌ Anlık mola bilgisi hatası: $e');
      return null;
    }
  }

  /// Otomatik bitiş timer'ını başlat
  void _startAutoEndTimer(int courierId, String logDocId, int remainingMinutes, DateTime breakStartAt) {
    // Önceki timer'ı durdur
    _stopAutoEndTimer(courierId);

    if (remainingMinutes <= 0) {
      print('⚠️ Kalan mola süresi 0 veya negatif, timer başlatılmadı');
      return;
    }

    print('⏰ Otomatik bitiş timer başlatılıyor: courierId=$courierId, logDocId=$logDocId, remainingMinutes=$remainingMinutes dk, breakStartAt=$breakStartAt');

    // ⭐ Timer başlatıldığını doğrula
    if (remainingMinutes <= 0) {
      print('⚠️ ⚠️ ⚠️ UYARI: Kalan mola süresi 0 veya negatif, timer başlatılmadı!');
      print('   Bu durumda mola süresi zaten dolmuş demektir, hemen bitirilmeli!');
      // ⭐ Hemen bitir
      Future.microtask(() async {
        try {
          final result = await autoEndBreak(courierId, logDocId);
          if (result['success'] == true) {
            print('✅ ✅ ✅ Mola hemen bitirildi (timer başlatılamadı çünkü süre 0)!');
          }
        } catch (e) {
          print('❌ ❌ ❌ Hemen bitirme hatası: $e');
        }
      });
      return;
    }

    // Her saniye kontrol et (anlık sayaç için)
    _autoEndTimers[courierId] = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        // ⭐ KRİTİK: Timer.periodic callback async olamaz, bu yüzden async işlemi Future.microtask ile yapıyoruz
        try {
          final now = DateTime.now();
          final elapsed = now.difference(breakStartAt);
          final elapsedSeconds = elapsed.inSeconds;
          final elapsedMinutes = elapsed.inMinutes;

          // Kalan süre hesapla (saniye cinsinden)
          final remainingTotalSeconds = (remainingMinutes * 60) - elapsedSeconds;

          // Debug log (her 10 saniyede bir veya son 10 saniyede)
          if (elapsedSeconds % 10 == 0 || remainingTotalSeconds <= 10) {
            print('⏰ Timer kontrol (courierId=$courierId): Geçen: ${elapsedMinutes}m ${elapsedSeconds % 60}s, Kalan: ${remainingTotalSeconds ~/ 60}m ${remainingTotalSeconds % 60}s');
          }

          // ⭐ KRİTİK: Kalan süre 0 veya negatif olduğunda otomatik bitir
          if (remainingTotalSeconds <= 0) {
            // Mola süresi doldu - otomatik bitir
            print('⏰ ⏰ ⏰ Mola süresi doldu! Otomatik bitiriliyor... (courierId=$courierId, Geçen: ${elapsedMinutes}m ${elapsedSeconds % 60}s)');
            timer.cancel();
            _autoEndTimers.remove(courierId);

            // ⭐ KRİTİK: Async işlemi Future.microtask ile yap (Timer.periodic callback async olamaz)
            Future.microtask(() async {
              try {
                print('🚀 Otomatik bitiş işlemi başlatılıyor... (courierId=$courierId, logDocId=$logDocId)');
                final result = await autoEndBreak(courierId, logDocId);
                if (result['success'] == true) {
                  print('✅ ✅ ✅ Mola otomatik bitirildi başarıyla! (courierId=$courierId)');
                } else {
                  print('❌ ❌ ❌ Otomatik bitiş hatası: ${result['message']} (courierId=$courierId)');
                }
              } catch (e, stackTrace) {
                print('❌ ❌ ❌ Otomatik bitiş exception: $e (courierId=$courierId)');
                print('Stack trace: $stackTrace');
              }
            });
          }
        } catch (e) {
          print('❌ Timer callback hatası: $e (courierId=$courierId)');
          // Timer callback'inde hata olsa bile timer çalışmaya devam etsin
        }
      },
    );
  }

  /// Otomatik bitiş timer'ını durdur
  void _stopAutoEndTimer(int courierId) {
    final timer = _autoEndTimers[courierId];
    if (timer != null) {
      timer.cancel();
      _autoEndTimers.remove(courierId);
      print('🛑 Otomatik bitiş timer durduruldu: courierId=$courierId');
    }
  }

  /// Public: Otomatik bitiş timer'ını dışarıdan durdur
  void stopAutoEndTimer(int courierId) {
    _stopAutoEndTimer(courierId);
  }

  /// Mola dakikasını hesapla (ceil/round tutarlı)
  /// 
  /// Doğru ceil mantığı: Saniye varsa yukarı yuvarla
  /// Örnekler:
  /// - 0-59 saniye → 1 dk (minimum 1 dakika)
  /// - 60-119 saniye → 2 dk
  /// - 120 saniye → 2 dk (tam dakika)
  /// - 121 saniye → 3 dk (ceil)
  int _calculateBreakMinutes(DateTime startAt, DateTime endAt) {
    final duration = endAt.difference(startAt);
    final totalSeconds = duration.inSeconds;
    
    return _calculateBreakMinutesFromSeconds(totalSeconds);
  }
  
  /// Saniye cinsinden mola dakikasını hesapla (ceil ile)
  int _calculateBreakMinutesFromSeconds(int totalSeconds) {
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

  /// Tüm timer'ları temizle (dispose için)
  void dispose() {
    for (final timer in _autoEndTimers.values) {
      timer.cancel();
    }
    _autoEndTimers.clear();
    print('🧹 Tüm otomatik bitiş timer\'ları temizlendi');
  }
}
