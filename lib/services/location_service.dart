import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'courier_location_api.dart';
import 'native_location_bridge.dart';

/// ⭐ KRİTİK: Background Location Service
/// React Native service.js karşılığı
/// Her 10 saniyede bir konum gönderir (uygulama kapalıyken bile)
/// Tracking lifecycle değil, service controlled — yalnızca [stopService] ile durur.
@pragma('vm:entry-point')
class LocationService {
  static const String _lastLocationUrl = 'https://zirvego.app/api/lastlocation';

  /// Kalıcı kuyruk (isolate / yeniden başlatma sonrası da korunur)
  static const String _pendingQueuePrefsKey = 'location_pending_queue_json';
  static const int _maxQueueSize = 50;

  /// iOS: tek bir CoreLocation akışı; harita + API aynı kaynaktan beslenir
  static StreamSubscription<Position>? _iosUnifiedPositionSubscription;
  static final StreamController<Position> _positionBroadcast =
      StreamController<Position>.broadcast(sync: true);
  static StreamSubscription<Position>? _iosApiPositionSubscription;
  static int _iosStreamTickCount = 0;
  
  // 🔄 WATCHDOG SYSTEM - Task çalışıyor mu kontrol et
  static DateTime _lastLocationUpdate = DateTime.now();
  static Timer? _watchdogTimer;
  
  // 💾 CACHE SYSTEM - Firestore read'leri azaltmak için
  static int? _cachedCourierStatus;
  static DateTime? _lastStatusCheck;
  static const Duration _statusCacheDuration = Duration(minutes: 30); // 30 dakikada bir güncelle
  
  // 📍 SON GÖNDERİLEN KONUM - 50 metre kontrolü için
  static double? _lastSentLatitude;
  static double? _lastSentLongitude;
  static DateTime? _lastSentTime; // Son gönderim zamanı (zaman filtresi için)
  static DateTime? _lastBackendCheck;
  static DateTime? _lastBackendResponseTime; // Backend'den gelen son konum zamanı
  static const Duration _backendCheckInterval = Duration(minutes: 3); // 3 dakikada bir backend kontrol
  static const Duration _minTimeBetweenSends = Duration(seconds: 25); // Minimum 25 saniye aralık

  /// Background service'i başlat
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    // Notification channel oluştur (Android)
    // ⭐ Google Play onayı için ZORUNLU: Kullanıcıya arka plan konum kullanımını açıkça belirt
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'zirvego_location_channel',
      'ZirveGo Kurye - Konum Takibi',
      description: 'Sipariş yönlendirmesi ve teslimat doğrulaması için arka planda konumunuz takip edilmektedir',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'zirvego_location_channel',
        // ⭐ Google Play onayı için ZORUNLU: Arka plan konum kullanımı açıklaması
        initialNotificationTitle: 'ZirveGo – Konum Takibi Aktif',
        initialNotificationContent: 'Teslimat doğrulaması için konumunuz arka planda gönderiliyor',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    if (!kIsWeb && Platform.isIOS) {
      await ensureIosMainIsolateTracking();
      await _hydrateSharedLastSentFromNative();
      await _mergeNativePendingIntoFlutterQueue();
      final prefs = await SharedPreferences.getInstance();
      final cid = prefs.getInt('courier_id');
      if (cid != null) {
        await _processLocationQueue(cid);
      }
    }
  }

  /// Background service başlat
  static Future<void> startService(int courierId) async {
    print('🚀 Background service başlatılıyor: Kurye ID = $courierId');
    
    final service = FlutterBackgroundService();

    // User ID'yi kaydet
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('courier_id', courierId);
    await prefs.setBool('app_is_running', true); // ⭐ Uygulama çalışıyor işaretle
    await prefs.setBool('courier_location_tracking', true);
    print('💾 Courier ID kaydedildi: $courierId');
    print('🏁 app_is_running = true');

    // 🔄 Watchdog başlat
    _startWatchdog();

    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      print('✅✅✅ Background location service BAŞLATILDI');
      print('🌐 API: ${CourierLocationApi.servisUrl}');
    } else {
      print('⚠️ Konum servisi zaten çalışıyor');
    }

    if (!kIsWeb && Platform.isIOS) {
      await ensureIosMainIsolateTracking();
      final prefs = await SharedPreferences.getInstance();
      await NativeLocationBridge.setIosTrackingState(
        enabled: true,
        courierId: courierId,
        apiToken: prefs.getString('location_api_token'),
      );
    }
  }

  /// Background service durdur
  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    service.invoke('stop');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('courier_location_tracking', false);

    if (!kIsWeb && Platform.isIOS) {
      await NativeLocationBridge.setIosTrackingState(
        enabled: false,
        courierId: 0,
        apiToken: null,
      );
    }

    await stopIosMainIsolateTracking();
    
    // 🛑 Watchdog durdur
    _stopWatchdog();
    
    // 💾 Cache'i temizle
    _cachedCourierStatus = null;
    _lastStatusCheck = null;
    _lastSentLatitude = null;
    _lastSentLongitude = null;
    _lastSentTime = null;
    _lastBackendCheck = null;
    _lastBackendResponseTime = null;
    
    print('🛑 Background location service durduruldu');
  }

  /// iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  /// ⭐ MAIN BACKGROUND SERVICE HANDLER
  /// Her 10 saniyede bir çağrılır
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    
    // 🔥 Firebase initialize (Background service için kritik!)
    try {
      // Firebase zaten initialize edilmiş mi kontrol et
      if (Firebase.apps.isEmpty) {
        print('🔥 Firebase initialize ediliyor (background service)...');
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('✅ Firebase background service\'te başlatıldı');
      } else {
        print('✅ Firebase zaten initialize edilmiş');
      }
    } catch (e) {
      print('❌ Firebase initialize hatası: $e');
      // Hata olsa bile devam et (fallback mekanizması var)
    }

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stop').listen((event) async {
      print('🛑 Stop eventi alındı - Service kapatılıyor');
      
      // Android notification'ı temizle
      if (service is AndroidServiceInstance) {
        try {
          // Tüm notification'ları temizle
          final notification = FlutterLocalNotificationsPlugin();
          await notification.cancelAll();
          print('🔕 Tüm notification\'lar kaldırıldı');
        } catch (e) {
          print('⚠️ Notification temizleme hatası: $e');
        }
      }
      
      service.stopSelf();
      print('✅ Service durduruldu');
    });

    // ⭐ AKILLI KONUM TIMER - 10 saniye interval (50m + backend kontrolü ile optimize)
    // 💰 FATURA OPTİMİZASYONU: Lokal kontrol (Firestore/Backend maliyeti yok)
    print('⏰ Akıllı konum timer başlatıldı (10 saniye interval)');
    
    // 📦 HAVUZ SİPARİŞ DİNLEYİCİSİ — arka planda yeni sipariş gelince bildirim gönder
    _startBackgroundPoolListener();
    
    int tickCount = 0; // Timer tik sayacı
    
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      tickCount++;
      print('⏰ Timer tick #$tickCount - ${DateTime.now()}');

      if (service is AndroidServiceInstance) {
        print('📱 Android service instance');
        
        if (await service.isForegroundService()) {
          print('✅ Foreground service aktif');
          
          try {
            // ⭐ Kurye durumunu kontrol et
            final shouldSend = await _shouldSendLocationByStatus(tickCount);
            
            if (shouldSend) {
              // Konum al ve gönder
              await _sendLocation();

              // Notification güncelle
              final now = DateTime.now();
              final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
              service.setForegroundNotificationInfo(
                title: 'ZirveGo Kurye',
                content: 'ZirveGo Kurye uygulaması tarafından konumunuz izlenmektedir • Son: $timeStr',
              );
              print('🔔 Notification güncellendi: $timeStr');
            } else {
              print('⏭️ Bu tick için konum gönderimi atlandı');
            }
          } catch (e) {
            print('❌ Background location error: $e');
          }
        } else {
          print('⚠️ Foreground service aktif DEĞİL');
        }
      } else {
        // iOS: Timer tabanlı konum burada güvenilir değil; ana isolate + AppleSettings ile akış kullanılıyor.
        if (tickCount % 18 == 0) {
          print('📱 iOS: periyodik konum ana isolate akışında (flutter_background_service yalnızca yaşam döngüsü)');
        }
      }
    });
  }

  // ─── iOS ana isolate: arka plan konum akışı ─────────────────────────────────

  static LocationSettings _platformCourierStreamSettings() {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 40,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 40,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
  }

  /// Harita ve iOS konum API için ortak yayın (yalnızca bir native abonelik).
  static Stream<Position> get courierPositionBroadcast => _positionBroadcast.stream;

  /// Harita + API için tek native konum kaynağı (iOS).
  /// iOS app kill edilirse tracking durur (Apple limitation).
  static Future<void> ensureIosUnifiedPositionStream() async {
    if (kIsWeb || !Platform.isIOS) return;

    if (_iosUnifiedPositionSubscription != null) return;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _iosUnifiedPositionSubscription = Geolocator.getPositionStream(
      locationSettings: _platformCourierStreamSettings(),
    ).listen(
      _positionBroadcast.add,
      onError: (Object e) {
        print('❌ iOS birleşik konum akışı hatası: $e');
      },
    );
    print('✅ iOS birleşik konum akışı (allowBackgroundLocationUpdates)');
  }

  /// Konum → API (yalnızca [courier_location_tracking] true iken, tek abonelik).
  static Future<void> ensureIosCourierApiListener() async {
    if (kIsWeb || !Platform.isIOS) return;

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('courier_location_tracking') ?? false)) return;
    if (prefs.getInt('courier_id') == null) return;

    await ensureIosUnifiedPositionStream();

    if (_iosApiPositionSubscription != null) return;

    _iosApiPositionSubscription = courierPositionBroadcast.listen(
      (position) async {
        _iosStreamTickCount++;
        try {
          final p = await SharedPreferences.getInstance();
          final courierId = p.getInt('courier_id');
          final tracking = p.getBool('courier_location_tracking') ?? false;
          if (courierId == null || !tracking) return;

          final shouldSend =
              await _shouldSendLocationByStatus(_iosStreamTickCount);
          if (!shouldSend) return;

          await _onFreshPosition(position, courierId);
        } catch (e) {
          print('❌ iOS konum API işleme hatası: $e');
        }
      },
    );
    print('✅ iOS konum → API dinleyicisi aktif');
  }

  static Future<void> stopIosCourierApiListener() async {
    await _iosApiPositionSubscription?.cancel();
    _iosApiPositionSubscription = null;
    _iosStreamTickCount = 0;
  }

  static Future<void> stopIosUnifiedPositionStream() async {
    await _iosUnifiedPositionSubscription?.cancel();
    _iosUnifiedPositionSubscription = null;
  }

  static Future<void> ensureIosMainIsolateTracking() async {
    if (kIsWeb || !Platform.isIOS) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('courier_location_tracking') ?? false)) return;
    if (prefs.getInt('courier_id') == null) return;
    await ensureIosCourierApiListener();
  }

  static Future<void> stopIosMainIsolateTracking() async {
    await stopIosCourierApiListener();
    await stopIosUnifiedPositionStream();
  }

  /// Ön plan + ağ: kuyruk boşaltma; iOS tracking tazeleme
  static Future<void> onApplicationResumed() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final courierId = prefs.getInt('courier_id');
    if (courierId == null) return;
    if (Platform.isIOS) {
      await _hydrateSharedLastSentFromNative();
      await _mergeNativePendingIntoFlutterQueue();
    }
    await _processLocationQueue(courierId);
    if (Platform.isIOS) {
      await ensureIosMainIsolateTracking();
      if (prefs.getBool('courier_location_tracking') ?? false) {
        await NativeLocationBridge.setIosTrackingState(
          enabled: true,
          courierId: courierId,
          apiToken: prefs.getString('location_api_token'),
        );
      }
    }
  }

  static Future<void> _hydrateSharedLastSentFromNative() async {
    if (kIsWeb || !Platform.isIOS) return;
    final m = await NativeLocationBridge.getSharedLastSent();
    if (m == null) return;
    final lat = m['lat'];
    final lon = m['lon'];
    if (lat != null && lon != null) {
      _lastSentLatitude = lat;
      _lastSentLongitude = lon;
    }
  }

  static Future<void> _mergeNativePendingIntoFlutterQueue() async {
    if (kIsWeb || !Platform.isIOS) return;
    final raw = await NativeLocationBridge.drainNativePendingQueueRaw();
    if (raw == null || raw.isEmpty || raw == '[]') return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return;
      var existing = await _readPersistentQueue();
      for (final e in decoded) {
        if (e is Map) {
          existing.add(Map<String, dynamic>.from(e));
        }
      }
      while (existing.length > _maxQueueSize) {
        existing.removeAt(0);
      }
      await _writePersistentQueue(existing);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> _readPersistentQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingQueuePrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writePersistentQueue(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_pendingQueuePrefsKey);
      return;
    }
    await prefs.setString(_pendingQueuePrefsKey, jsonEncode(items));
  }

  static Future<void> _enqueuePersistentFailedLocation({
    required double latitude,
    required double longitude,
    required double? speedKmh,
    required int timestamp,
  }) async {
    var list = await _readPersistentQueue();
    while (list.length >= _maxQueueSize) {
      list.removeAt(0);
    }
    list.add({
      'latitude': latitude,
      'longitude': longitude,
      'speedKmh': speedKmh,
      'timestamp': timestamp,
    });
    await _writePersistentQueue(list);
  }

  /// ⭐ Kurye durumuna göre konum gönderilmeli mi?
  /// 💾 CACHE OPTİMİZASYONU: Firestore read'leri 1 dakikada bir yapılır (5760 → 1440 read/gün)
  static Future<bool> _shouldSendLocationByStatus(int tickCount) async {
    try {
      // SharedPreferences'tan courierId al
      final prefs = await SharedPreferences.getInstance();
      final courierId = prefs.getInt('courier_id');

      if (courierId == null) {
        print('⚠️ Courier ID bulunamadı - Varsayılan interval kullanılacak');
        return true; // Her 10 saniyede bir (her tick)
      }

      // 💾 CACHE KONTROLÜ: Son kontrol 30 dakikadan eskiyse güncelle
      // ⭐ KRİTİK: Background isolate için SharedPreferences üzerinden invalidate sinyali kontrol et
      final now = DateTime.now();
      
      // Main isolate'ten gelen invalidate sinyalini kontrol et
      bool externalInvalidated = false;
      final invalidatedAt = prefs.getInt('status_cache_invalidated_at');
      if (invalidatedAt != null && _lastStatusCheck != null) {
        final invalidatedTime = DateTime.fromMillisecondsSinceEpoch(invalidatedAt);
        if (invalidatedTime.isAfter(_lastStatusCheck!)) {
          print('🔄 External invalidate sinyali algılandı! Background cache temizleniyor...');
          _cachedCourierStatus = null;
          _lastStatusCheck = null;
          externalInvalidated = true;
        }
      }
      
      final shouldRefreshCache = _lastStatusCheck == null || 
                                 now.difference(_lastStatusCheck!) > _statusCacheDuration ||
                                 externalInvalidated;

      if (shouldRefreshCache) {
        print('🔄 Cache yenileniyor...');
        
        // Firestore'dan kurye durumunu al
        final courierDoc = await FirebaseFirestore.instance
            .collection('t_courier')
            .where('s_id', isEqualTo: courierId)
            .limit(1)
            .get();

        if (courierDoc.docs.isEmpty) {
          print('⚠️ Kurye bulunamadı, varsayılan interval kullanılacak');
          // ⭐ KRİTİK DÜZELTMESİ: Kurye bulunamazsa OFFLINE (0) varsay (eskiden 1 idi)
          _cachedCourierStatus = 0; // Güvenli default: OFFLINE
          _lastStatusCheck = now;
          return false; // Kurye yoksa konum gönderme
        }

        // ⭐ KRİTİK DÜZELTMESİ: s_stat null ise OFFLINE (0) varsay (eskiden 1 idi)
        _cachedCourierStatus = courierDoc.docs.first.data()['s_stat'] ?? 0;
        _lastStatusCheck = now;
        print('💾 Durum cache\'lendi: $_cachedCourierStatus');
      } else {
        print('💾 Cache kullanılıyor (${now.difference(_lastStatusCheck!).inSeconds} sn önce güncellendi)');
      }

      final courierStatus = _cachedCourierStatus ?? 0; // Güvenli default: OFFLINE
      
      // ⭐ Duruma göre interval belirleme
      // tickCount * 15 saniye = toplam geçen süre
      switch (courierStatus) {
        case 0: // Çalışmıyor - Konum gönderilmemeli
          print('🚫 Durum: ÇALIŞMIYOR - Konum gönderilmeyecek');
          return false;
          
        case 1: // Müsait - Her 10 saniyede kontrol (50m + backend kontrolü ile)
        case 2: // Meşgul - Her 10 saniyede kontrol (50m + backend kontrolü ile)
          print('✅ Durum: ${courierStatus == 1 ? "MÜSAİT" : "MEŞGUL"} - Kontrol yapılacak (10 sn)');
          return true; // Her tick kontrol et (50m + backend kontrolü yapılacak)
          
        case 3: // Mola - 10 dakikada bir kontrol (60 tick × 10sn = 600sn)
          if (tickCount % 60 == 0) {
            print('☕ Durum: MOLA - Kontrol yapılacak (10 dk)');
            return true;
          }
          return false;
          
        case 4: // Kaza - 10 dakikada bir kontrol (60 tick × 10sn = 600sn)
          if (tickCount % 60 == 0) {
            print('🚨 Durum: KAZA - Kontrol yapılacak (10 dk)');
            return true;
          }
          return false;
          
        default:
          print('⚠️ Bilinmeyen durum: $courierStatus - Varsayılan 10 sn');
          return true; // Her tick kontrol et
      }
    } catch (e) {
      print('❌ Durum kontrolü hatası: $e - Varsayılan kullanılacak');
      return true; // Hata durumunda 10 saniye
    }
  }

  /// ⏰ BACKEND ZAMAN KONTROLÜ - Son konum 3 dakika içinde gönderilmiş mi?
  /// 💰 FATURA OPTİMİZASYONU: 3 dakikada bir backend kontrolü
  static Future<bool> _shouldSkipLocationSend(int courierId) async {
    try {
      final now = DateTime.now();
      
      // ⏰ Son backend kontrolünden 3 dakika geçmediyse, cache'den kontrol et
      if (_lastBackendCheck != null && 
          now.difference(_lastBackendCheck!) < _backendCheckInterval) {
        print('💾 Backend kontrolü cache\'den (${now.difference(_lastBackendCheck!).inSeconds} sn önce kontrol edildi)');
        
        // Cache'de backend'den gelen son konum zamanı var mı?
        if (_lastBackendResponseTime != null) {
          final timeSinceLastBackendLocation = now.difference(_lastBackendResponseTime!);
          if (timeSinceLastBackendLocation < _backendCheckInterval) {
            print('⏭️ SKIP: Backend cache - Son konum ${timeSinceLastBackendLocation.inSeconds} sn önce gönderilmiş (3 dk limit)');
            return true; // Skip yap
          } else {
            print('✅ Backend cache - Son konum ${timeSinceLastBackendLocation.inSeconds} sn önce gönderilmiş, gönderilecek');
            return false; // Gönder
          }
        }
        
        // Backend response zamanı yoksa, son gönderim zamanına bak
        if (_lastSentTime != null) {
          final timeSinceLastSend = now.difference(_lastSentTime!);
          if (timeSinceLastSend < _backendCheckInterval) {
            print('⏭️ SKIP: Son gönderim ${timeSinceLastSend.inSeconds} sn önce (3 dk limit)');
            return true; // Skip yap
          }
        }
        
        // Cache'de bilgi yoksa gönder (güvenli mod)
        print('⚠️ Backend cache bilgisi yok, gönderilecek');
        return false;
      }
      
      print('⏰ Backend zaman kontrolü başlatıldı (3 dakika kontrolü)...');
      
      final url = Uri.parse('$_lastLocationUrl?s_id=$courierId');
      final response = await http.get(url).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('⏱️ Backend timeout, konum gönderilecek (safe mode)');
          return http.Response('{}', 408);
        },
      );
      
      _lastBackendCheck = now; // Backend kontrol zamanını kaydet
      
      if (response.statusCode != 200) {
        print('⚠️ Backend yanıt vermedi, konum gönderilecek (safe mode)');
        return false;
      }
      
      // Backend'den gelen son konum zamanı
      try {
        final data = response.body.trim();
        print('📥 Backend response: ${data.length > 200 ? data.substring(0, 200) : data}');
        
        // Backend'den timestamp geliyorsa parse et
        if (data.isEmpty || data == '{}' || data == 'null') {
          print('📥 Backend boş yanıt, son gönderim zamanına bakılacak');
          // Backend'de konum yok, son gönderim zamanına bak
          if (_lastSentTime != null) {
            final timeSinceLastSend = now.difference(_lastSentTime!);
            if (timeSinceLastSend < _backendCheckInterval) {
              print('⏭️ SKIP: Son gönderim ${timeSinceLastSend.inSeconds} sn önce (3 dk limit)');
              _lastBackendResponseTime = _lastSentTime; // Cache'e kaydet
              return true; // Skip yap
            }
          }
          return false; // Gönder
        }
        
        // JSON parse dene
        try {
          // Backend response formatını parse et (örnek: {"timestamp": 1234567890} veya {"last_location_time": "..."})
          // Şimdilik basit kontrol: Eğer timestamp varsa kullan
          // Backend formatına göre bu kısım güncellenebilir
          
          // Backend'den timestamp gelmediyse, son gönderim zamanını kullan
          if (_lastSentTime != null) {
            final timeSinceLastSend = now.difference(_lastSentTime!);
            if (timeSinceLastSend < _backendCheckInterval) {
              print('⏭️ SKIP: Son gönderim ${timeSinceLastSend.inSeconds} sn önce (3 dk limit)');
              _lastBackendResponseTime = _lastSentTime; // Cache'e kaydet
              return true; // Skip yap
            }
          }
          
          print('📥 Backend yanıt alındı, konum gönderilecek');
          _lastBackendResponseTime = now; // Backend'den yanıt geldi, şimdiki zamanı kaydet
          return false; // Gönder
        } catch (e) {
          print('⚠️ Parse hatası, son gönderim zamanına bakılacak: $e');
          // Parse hatası durumunda son gönderim zamanına bak
          if (_lastSentTime != null) {
            final timeSinceLastSend = now.difference(_lastSentTime!);
            if (timeSinceLastSend < _backendCheckInterval) {
              return true; // Skip yap
            }
          }
          return false; // Gönder
        }
      } catch (e) {
        print('⚠️ Parse hatası, konum gönderilecek: $e');
        return false;
      }
    } catch (e) {
      print('❌ Backend kontrol hatası: $e');
      return false; // Hata durumunda konum gönder (safe mode)
    }
  }

  static Future<bool> _sendLocationWithRetry({
    required double latitude,
    required double longitude,
    required int courierId,
    double? speedKmh,
    int maxRetries = 3,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    print('🌐 Konum API: $courierId @ ($latitude, $longitude) t=$timestamp');

    final ok = await CourierLocationApi.submitWithRetry(
      latitude: latitude,
      longitude: longitude,
      courierId: courierId,
      timestampMs: timestamp,
      speedKmh: speedKmh,
      maxRetries: maxRetries,
    );

    if (ok) {
      _lastLocationUpdate = DateTime.now();
    }
    return ok;
  }

  /// 📤 Kalıcı kuyruktaki konumları sırayla gönder
  static Future<void> _processLocationQueue(int courierId) async {
    var items = await _readPersistentQueue();
    if (items.isEmpty) return;

    print('📤 Kalıcı kuyruk işleniyor: ${items.length} kayıt');

    final remaining = <Map<String, dynamic>>[];
    var failed = false;
    for (final item in items) {
      if (failed) {
        remaining.add(item);
        continue;
      }
      final lat = item['latitude'] as num?;
      final lng = item['longitude'] as num?;
      final ts = item['timestamp'] as int?;
      final speed = item['speedKmh'] as double?;
      if (lat == null || lng == null || ts == null) {
        continue;
      }

      final success = await CourierLocationApi.submitWithRetry(
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        courierId: courierId,
        timestampMs: ts,
        speedKmh: speed,
        maxRetries: 2,
      );

      if (!success) {
        failed = true;
        remaining.add(item);
      }
    }

    await _writePersistentQueue(remaining);
  }

  /// 🔄 WATCHDOG BAŞLAT - Servis sağlık kontrolü
  static void _startWatchdog() {
    _stopWatchdog(); // Önceki watchdog'u durdur
    
    print('🐕 Watchdog başlatıldı');
    _watchdogTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      final timeSinceLastUpdate = DateTime.now().difference(_lastLocationUpdate);
      print('🐕 Watchdog kontrol: Son güncelleme ${timeSinceLastUpdate.inMinutes} dakika önce');
      
      if (timeSinceLastUpdate.inMinutes > 10) {
        print('⚠️⚠️ Watchdog ALARM: 10 dakikadır konum gönderilmedi!');
        // TODO: Gerekirse servisi yeniden başlatma mekanizması
      }
    });
  }

  /// 🛑 WATCHDOG DURDUR
  static void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// [Position] ile filtre + API (Android isolate / iOS ana akış ortak mantık)
  static Future<void> _onFreshPosition(Position position, int courierId) async {
    await _processLocationQueue(courierId);

    final latitude = position.latitude;
    final longitude = position.longitude;
    final speedKmhRaw = position.speed >= 0 ? position.speed * 3.6 : 0.0;
    final speedKmh = speedKmhRaw < 3.0 ? 0.0 : speedKmhRaw;

    print('✅ Konum işleniyor: ($latitude, $longitude) acc=${position.accuracy}m');

    bool shouldCheckBackend = false;
    bool is50mOrMore = false;

    if (_lastSentLatitude != null && _lastSentLongitude != null) {
      final distance = Geolocator.distanceBetween(
        _lastSentLatitude!,
        _lastSentLongitude!,
        latitude,
        longitude,
      );

      if (distance >= 50) {
        print(
            '✅ 50m+ hareket: ${distance.toStringAsFixed(1)}m — zaman/backend atlanır');
        is50mOrMore = true;
        shouldCheckBackend = false;
      } else {
        print(
            '📍 Son gönderime ${distance.toStringAsFixed(1)}m — backend kontrolü');
        shouldCheckBackend = true;
      }
    } else {
      print('📍 İlk konum gönderimi');
      shouldCheckBackend = false;
      is50mOrMore = true;
    }

    if (!is50mOrMore && _lastSentTime != null) {
      final timeSinceLastSend = DateTime.now().difference(_lastSentTime!);
      if (timeSinceLastSend < _minTimeBetweenSends) {
        print(
            '⏭️ SKIP: ${timeSinceLastSend.inSeconds}s < ${_minTimeBetweenSends.inSeconds}s');
        return;
      }
    }

    if (shouldCheckBackend) {
      final shouldSkip = await _shouldSkipLocationSend(courierId);
      if (shouldSkip) {
        print('⏭️ SKIP: backend son 3 dk içinde güncel');
        return;
      }
    }

    final success = await _sendLocationWithRetry(
      latitude: latitude,
      longitude: longitude,
      courierId: courierId,
      speedKmh: speedKmh,
    );

    if (success) {
      _lastSentLatitude = latitude;
      _lastSentLongitude = longitude;
      _lastSentTime = DateTime.now();
      print('💾 Son gönderilen konum kaydedildi: ($latitude, $longitude)');
      if (!kIsWeb && Platform.isIOS) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        unawaited(
          NativeLocationBridge.syncLastSentToNative(
            latitude: latitude,
            longitude: longitude,
            timestampMs: ts,
          ),
        );
      }
    } else {
      print('📦 Konum kalıcı kuyruğa (ağ/sunucu hatası)');
      await _enqueuePersistentFailedLocation(
        latitude: latitude,
        longitude: longitude,
        speedKmh: speedKmh,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  /// Konum al ve API'ye gönder (Android arka plan isolate)
  static Future<void> _sendLocation() async {
    try {
      print('🔄 _sendLocation() — ${DateTime.now()}');

      final prefs = await SharedPreferences.getInstance();
      final courierId = prefs.getInt('courier_id');

      if (courierId == null) {
        print('❌ Courier ID yok');
        return;
      }

      await _processLocationQueue(courierId);

      print('📍 getCurrentPosition (Android isolate)...');
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 50,
        ),
      );

      await _onFreshPosition(position, courierId);
    } catch (e) {
      print('❌ Konum gönderme HATASI: $e');
      if (e is Error) {
        print('   Stack: ${e.stackTrace}');
      }
    }
  }

  /// ⭐ Konum izinlerini kontrol et ve iste (DETAYLI)
  static Future<bool> checkAndRequestPermissions() async {
    print('🔐 İzin kontrolü başlıyor...');
    
    // 1. Konum servisi aktif mi?
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('❌ Konum servisi kapalı - Kullanıcı GPS açmalı');
      return false;
    }
    print('✅ GPS servisi aktif');

    // 2. Foreground (normal) konum izni
    LocationPermission permission = await Geolocator.checkPermission();
    print('📍 Mevcut izin durumu: $permission');

    if (permission == LocationPermission.denied) {
      print('⚠️ İzin denied - İsteniyor...');
      permission = await Geolocator.requestPermission();
      print('📍 İstek sonrası durum: $permission');
      
      if (permission == LocationPermission.denied) {
        print('❌ Konum izni reddedildi');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('❌ Konum izni kalıcı olarak reddedildi - Ayarlardan açmalı');
      return false;
    }

    print('✅ Foreground konum izni verildi');

    // 3. Arka plan: Android 10+ ve iOS "Always" — kurye takibi için zorunlu
    if (permission != LocationPermission.always) {
      print('⚠️ Konum henüz "always" değil: $permission');
      try {
        final bgStatus = await Permission.locationAlways.status;
        print('📍 locationAlways durumu: $bgStatus');

        if (!bgStatus.isGranted) {
          print('⏳ locationAlways isteniyor...');
          final result = await Permission.locationAlways.request();
          print('📍 locationAlways sonuç: $result');

          if (!result.isGranted) {
            print('⚠️ "Her zaman" verilmedi — iOS arka planda konum çalışmaz');
            if (!kIsWeb && Platform.isIOS) {
              return false;
            }
            if (!kIsWeb && Platform.isAndroid) {
              return false;
            }
          }
        }

        permission = await Geolocator.checkPermission();
        print('📍 Geolocator (always sonrası): $permission');
      } catch (e) {
        print('❌ locationAlways hatası: $e');
      }
    } else {
      print('✅ Konum izni: always');
    }

    // 4. Notification izni (Android 13+)
    try {
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        print('⏳ Bildirim izni isteniyor...');
        await Permission.notification.request();
      }
    } catch (e) {
      print('⚠️ Bildirim izni hatası: $e');
    }

    if (!kIsWeb && Platform.isIOS) {
      permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        print(
            '❌ iOS: Arka plan konumu için "Her Zaman" gerekli, mevcut: $permission');
        return false;
      }
    }

    print('✅✅✅ TÜM İZİNLER TAMAM');
    return true;
  }

  /// ⭐ Uygulama ayarlarını aç
  static Future<void> openAppSettings() async {
    print('⚙️ Uygulama ayarları açılıyor...');
    await Geolocator.openAppSettings();
  }

  /// ⚡ Pil optimizasyonunu kontrol et (Xiaomi, Oppo, Huawei için önemli)
  static Future<void> checkBatteryOptimization() async {
    print('🔋 Pil optimizasyonu kontrolü...');
    // TODO: Android'de battery optimization dialogu göster
    // Not: permission_handler ile yapılabilir ama manuel kontrol daha iyi
    print('⚠️ Xiaomi/Oppo/Huawei kullanıyorsanız:');
    print('   Ayarlar → Pil → Uygulama pil tasarrufu → ZirveGo → "Kısıtlama yok" seçin');
  }

  /// Anlık konum al (foreground)
  static Future<Position?> getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return position;
    } catch (e) {
      print('❌ Konum alma hatası: $e');
      return null;
    }
  }

  /// Harita için konum akışı. iOS'ta [courierPositionBroadcast] kullanılır (tek abonelik).
  static Stream<Position> getPositionStream() {
    if (!kIsWeb && Platform.isIOS) {
      return courierPositionBroadcast;
    }
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  /// 📍 Konum servisi açık mı kontrol et (Google Play & Apple Store zorunlu)
  static Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      print('❌ Konum servisi kontrol hatası: $e');
      return false;
    }
  }

  /// ⚙️ Konum ayarlarını aç (Google Play & Apple Store zorunlu)
  static Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (e) {
      print('❌ Konum ayarları açma hatası: $e');
    }
  }

  /// 💾 Cache'i invalidate et (kurye durumu değiştiğinde çağrılmalı)
  /// ⭐ KRİTİK: Hem main isolate hem de background isolate'in cache'ini temizler.
  /// Main isolate → static değişkenleri sıfırla
  /// Background isolate → SharedPreferences üzerinden "invalidate" sinyali gönder
  static void invalidateStatusCache() {
    print('🔄 Status cache invalidate edildi (main isolate)');
    _cachedCourierStatus = null;
    _lastStatusCheck = null;
    // Not: _lastSentLatitude ve _lastSentLongitude temizlenmez (konum cache'i)
    // Not: _lastBackendCheck temizlenmez (backend kontrol cache'i)
    
    // ⭐ Background isolate'e invalidate sinyali gönder (SharedPreferences üzerinden)
    // Background isolate bu flag'i okuyunca cache'ini temizleyecek
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('status_cache_invalidated_at', DateTime.now().millisecondsSinceEpoch);
      print('🔄 Background isolate cache invalidate sinyali gönderildi (SharedPreferences)');
    }).catchError((e) {
      print('⚠️ Cache invalidate sinyal hatası: $e');
    });
  }

  // ─── Havuz Sipariş Arka Plan Dinleyicisi ───────────────────────────────────

  static int _bgPoolPrevCount = -1;
  static StreamSubscription<QuerySnapshot>? _bgPoolSubscription;

  /// Arka plan izolat'ında havuz siparişlerini dinle ve bildirim gönder.
  /// SharedPreferences'tan pool config okur (main isolat'ın yazdığı değerler).
  @pragma('vm:entry-point')
  static Future<void> _startBackgroundPoolListener() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('pool_enabled') ?? false;
      if (!enabled) {
        print('📦 Havuz izni yok, arka plan dinleyicisi başlatılmadı');
        return;
      }

      final bayId = prefs.getInt('pool_bay_id');
      if (bayId == null) {
        print('⚠️ Havuz bay_id bulunamadı');
        return;
      }

      final scope = prefs.getString('pool_scope') ?? 'selected';
      final idsRaw = prefs.getString('pool_business_ids') ?? '';
      final allowedIds = idsRaw.isEmpty
          ? <int>[]
          : idsRaw
              .split(',')
              .map((s) => int.tryParse(s.trim()))
              .whereType<int>()
              .toList();

      // flutter_local_notifications'ı background izolat'ında başlat
      final localNotif = FlutterLocalNotificationsPlugin();
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      await localNotif.initialize(
        const InitializationSettings(android: androidSettings),
      );

      // Havuz kanalını oluştur (telefon varsayılan bildirim sesi)
      final Int64List vibPattern = Int64List.fromList([0, 400, 200, 400]);
      final poolChannel = AndroidNotificationChannel(
        'pool_orders_v3',
        'Havuz Siparişleri',
        description: 'Havuzda yeni sipariş olduğunda bildirim alırsınız',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: vibPattern,
        showBadge: true,
      );
      await localNotif
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(poolChannel);

      print('📦 Arka plan havuz dinleyicisi başlatılıyor (bayId=$bayId, scope=$scope)');

      _bgPoolSubscription?.cancel();
      _bgPoolPrevCount = -1;

      Query query = FirebaseFirestore.instance
          .collection('t_orders')
          .where('s_bay', isEqualTo: bayId)
          .where('s_courier', isEqualTo: 0)
          .where('s_stat', whereIn: [0, 4]);

      _bgPoolSubscription = query.snapshots().listen((snapshot) async {
        // Platform Valesi (s_delivery_type=1) ve yetki dışı siparişleri filtrele
        final orders = snapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if ((data['s_delivery_type'] as int? ?? 0) == 1) return false;
          if (scope == 'all') return true;
          final sWork = data['s_work'] as int? ?? 0;
          return allowedIds.contains(sWork);
        }).toList();

        final newCount = orders.length;

        if (_bgPoolPrevCount >= 0 && newCount > _bgPoolPrevCount) {
          print('📦 Arka planda yeni havuz siparişi: $newCount (önceki: $_bgPoolPrevCount)');
          await localNotif.show(
            DateTime.now().millisecondsSinceEpoch.remainder(100000),
            '📦 Havuzda $newCount sipariş var',
            'Yeni sipariş havuza düştü. Hemen kontrol et!',
            NotificationDetails(
              android: AndroidNotificationDetails(
                'pool_orders_v3',
                'Havuz Siparişleri',
                channelDescription: 'Havuzda yeni sipariş olduğunda bildirim alırsınız',
                importance: Importance.max,
                priority: Priority.max,
                playSound: true,
                enableVibration: true,
                vibrationPattern: vibPattern,
                icon: '@mipmap/ic_launcher',
              ),
            ),
          );
        }

        _bgPoolPrevCount = newCount;
      }, onError: (e) {
        print('❌ Arka plan havuz dinleyicisi hatası: $e');
      });
    } catch (e) {
      print('❌ _startBackgroundPoolListener başlatma hatası: $e');
    }
  }
}

