import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

/// ⭐ KRİTİK: Background Location Service
/// React Native service.js karşılığı
/// Her 10 saniyede bir konum gönderir (uygulama kapalıyken bile)
@pragma('vm:entry-point')
class LocationService {
  static const String _apiUrl = 'https://zirvego.app/api/servis';
  static const String _lastLocationUrl = 'https://zirvego.app/api/lastlocation';
  static Timer? _locationTimer;
  
  // 📦 OFFLINE QUEUE - Network yokken konum buraya kaydedilir
  static final List<Map<String, dynamic>> _locationQueue = [];
  static const int _maxQueueSize = 50;
  
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
  }

  /// Background service başlat
  static Future<void> startService(int courierId) async {
    print('🚀 Background service başlatılıyor: Kurye ID = $courierId');
    
    final service = FlutterBackgroundService();

    // User ID'yi kaydet
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('courier_id', courierId);
    await prefs.setBool('app_is_running', true); // ⭐ Uygulama çalışıyor işaretle
    print('💾 Courier ID kaydedildi: $courierId');
    print('🏁 app_is_running = true');

    // 🔄 Watchdog başlat
    _startWatchdog();

    bool isRunning = await service.isRunning();
    if (isRunning) {
      print('⚠️ Konum servisi zaten çalışıyor');
      return;
    }

    await service.startService();
    print('✅✅✅ Background location service BAŞLATILDI (15 saniye interval)');
    print('🌐 API URL: $_apiUrl');
  }

  /// Background service durdur
  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    service.invoke('stop');
    
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
    
    int tickCount = 0; // Timer tik sayacı
    
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      tickCount++;
      print('⏰ Timer tick #$tickCount - ${DateTime.now()}');
      
      // ⭐ UYGULAMA AÇIK MI KONTROLÜ (Her 1 dakikada bir = her 6 tick)
      if (tickCount % 6 == 0) {
        print('🔍 Uygulama durumu kontrol ediliyor... (1 dakika geçti)');
        final prefs = await SharedPreferences.getInstance();
        final appIsRunning = prefs.getBool('app_is_running') ?? false;
        
        if (!appIsRunning) {
          print('🚫 Uygulama kapalı tespit edildi - Service durduruluyor...');
          timer.cancel();
          service.invoke('stop');
          return;
        } else {
          print('✅ Uygulama hala çalışıyor');
        }
      }
      
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
        // iOS için
        print('📱 iOS service instance');
        final shouldSend = await _shouldSendLocationByStatus(tickCount);
        if (shouldSend) {
          await _sendLocation();
        }
      }
    });
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
      final now = DateTime.now();
      final shouldRefreshCache = _lastStatusCheck == null || 
                                 now.difference(_lastStatusCheck!) > _statusCacheDuration;

      if (shouldRefreshCache) {
        print('🔄 Cache yenileniyor (30 dakika geçti)...');
        
        // Firestore'dan kurye durumunu al
        final courierDoc = await FirebaseFirestore.instance
            .collection('t_courier')
            .where('s_id', isEqualTo: courierId)
            .limit(1)
            .get();

        if (courierDoc.docs.isEmpty) {
          print('⚠️ Kurye bulunamadı, varsayılan interval kullanılacak');
          _cachedCourierStatus = 1; // Varsayılan durum
          _lastStatusCheck = now;
          return true; // Her 10 saniyede bir (her tick)
        }

        _cachedCourierStatus = courierDoc.docs.first.data()['s_stat'] ?? 1;
        _lastStatusCheck = now;
        print('💾 Durum cache\'lendi: $_cachedCourierStatus');
      } else {
        print('💾 Cache kullanılıyor (${now.difference(_lastStatusCheck!).inSeconds} sn önce güncellendi)');
      }

      final courierStatus = _cachedCourierStatus ?? 1;
      
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

  /// 🔄 RETRY MEKANIZMASI - API hatası durumunda tekrar dene
  /// ⭐ React Native service.js sendLocationWithRetry karşılığı
  static Future<bool> _sendLocationWithRetry({
    required double latitude,
    required double longitude,
    required int courierId,
    double? speedKmh,
    int maxRetries = 3,
  }) async {
    print('🌐 API isteği hazırlanıyor...');
    print('   Endpoint: $_apiUrl');
    print('   Kurye ID: $courierId');
    print('   Konum: ($latitude, $longitude)');
    if (speedKmh != null) {
      print('   Hız: ${speedKmh.toStringAsFixed(2)} km/saat');
    }
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // ⭐ Cache bypass için timestamp (React Native'deki gibi)
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        String urlString = '$_apiUrl?x=$latitude&y=$longitude&s_id=$courierId&t=$timestamp';
        if (speedKmh != null) {
          urlString += '&km=${speedKmh.toStringAsFixed(2)}';
        }
        final url = Uri.parse(urlString);

        print('🌐 [$attempt/$maxRetries] GET isteği gönderiliyor...');
        print('   URL: $url');

        final response = await http.get(url).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('⏱️ [$attempt/$maxRetries] Timeout - 10 saniye aşıldı');
            return http.Response('{"error": "timeout"}', 408);
          },
        );

        print('📡 [$attempt/$maxRetries] Server yanıtı alındı: ${response.statusCode}');

        if (response.statusCode == 200) {
          print('✅✅✅ [$attempt/$maxRetries] Konum BAŞARIYLA gönderildi!');
          print('   Kurye: $courierId');
          print('   Konum: ($latitude, $longitude)');
          if (speedKmh != null) {
            print('   Hız: ${speedKmh.toStringAsFixed(2)} km/saat');
          }
          print('   Timestamp: $timestamp');
          print('📥 Server response: ${response.body}');
          _lastLocationUpdate = DateTime.now(); // Watchdog güncelle
          return true;
        } else {
          print('⚠️⚠️ [$attempt/$maxRetries] Sunucu hatası: ${response.statusCode}');
          print('📥 Error response: ${response.body}');
          
          if (attempt < maxRetries) {
            final waitTime = 1000 * (1 << (attempt - 1)); // Exponential backoff (ms)
            print('⏳ $waitTime ms bekleniyor...');
            await Future.delayed(Duration(milliseconds: waitTime));
          }
        }
      } catch (e, stackTrace) {
        print('❌ [$attempt/$maxRetries] Network hatası: $e');
        print('   Hata tipi: ${e.runtimeType}');
        if (e is http.ClientException) {
          print('   ClientException: ${e.message}');
        }
        print('   Stack trace: $stackTrace');
        
        if (attempt < maxRetries) {
          final waitTime = 1000 * (1 << (attempt - 1));
          print('⏳ $waitTime ms bekleniyor...');
          await Future.delayed(Duration(milliseconds: waitTime));
        }
      }
    }
    
    print('❌❌❌ TÜM DENEMELER BAŞARISIZ (${maxRetries}x)');
    return false; // Tüm denemeler başarısız
  }

  /// 📤 QUEUE'DEKİ KONUMLARI GÖNDER
  static Future<void> _processLocationQueue(int courierId) async {
    if (_locationQueue.isEmpty) return;
    
    print('📤 Queue işleniyor: ${_locationQueue.length} konum bekliyor');
    
    final itemsToProcess = List<Map<String, dynamic>>.from(_locationQueue);
    _locationQueue.clear(); // Queue'yu temizle
    
    for (final item in itemsToProcess) {
      final success = await _sendLocationWithRetry(
        latitude: item['latitude'],
        longitude: item['longitude'],
        courierId: courierId,
        speedKmh: item['speedKmh'] as double?,
        maxRetries: 1, // Queue için 1 deneme yeter
      );
      
      if (!success) {
        // Tekrar queue'ya ekle (ama max boyutu kontrol et)
        if (_locationQueue.length < _maxQueueSize) {
          _locationQueue.add(item);
        }
        break; // Birisi başarısız oldu, kalan queue'yu sonra dene
      }
    }
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

  /// Konum al ve API'ye gönder
  static Future<void> _sendLocation() async {
    try {
      print('🔄 _sendLocation() başladı - ${DateTime.now()}');
      
      final prefs = await SharedPreferences.getInstance();
      final courierId = prefs.getInt('courier_id');

      if (courierId == null) {
        print('❌ Courier ID bulunamadı - SharedPreferences boş');
        return;
      }

      print('✅ Courier ID: $courierId');

      // 📤 Önce queue'daki konumları göndermeyi dene
      await _processLocationQueue(courierId);

      // Konum al
      print('📍 Konum alınıyor...');
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 50, // 💰 50 metre distance filter - Fatura optimizasyonu
        ),
      );

      final latitude = position.latitude;
      final longitude = position.longitude;
      // Hızı m/s'den km/saat'e çevir (m/s * 3.6 = km/saat)
      // ⚠️ GPS hata toleransı: 3 km/h altındaki hızlar 0 olarak kabul edilir (durdurulmuş cihaz)
      final speedKmhRaw = position.speed >= 0 ? position.speed * 3.6 : 0.0;
      final speedKmh = speedKmhRaw < 3.0 ? 0.0 : speedKmhRaw; // 3 km/h eşik değeri

      print('✅ Konum alındı: ($latitude, $longitude)');
      print('   Accuracy: ${position.accuracy}m');
      print('   Speed: ${position.speed}m/s (${speedKmh.toStringAsFixed(2)} km/saat)');

      // 📍 50 METRE KONTROLÜ - ÖNCE MESAFE KONTROLÜ (Zaman filtresinden önce!)
      bool shouldCheckBackend = false;
      bool is50mOrMore = false; // 50m üzeri hareket var mı?
      
      if (_lastSentLatitude != null && _lastSentLongitude != null) {
        final distance = Geolocator.distanceBetween(
          _lastSentLatitude!,
          _lastSentLongitude!,
          latitude,
          longitude,
        );
        
        if (distance >= 50) {
          // ⚡ 50 METRE ÜZERİ - Zaman filtresini atla, direkt gönder!
          print('✅ 50 metre limit aşıldı: ${distance.toStringAsFixed(1)}m uzakta - Zaman filtresi atlanıyor, direkt gönderilecek');
          is50mOrMore = true;
          shouldCheckBackend = false; // Backend kontrolüne gerek yok
        } else {
          print('📍 50 metre kontrolü: Son gönderilen konumdan ${distance.toStringAsFixed(1)}m uzakta (50m limit altında)');
          shouldCheckBackend = true; // 50m altındaysa backend kontrolü yap
        }
      } else {
        // İlk konum gönderimi, direkt gönder (zaman filtresi yok)
        print('📍 İlk konum gönderimi, direkt gönderilecek');
        shouldCheckBackend = false;
        is50mOrMore = true; // İlk gönderimde zaman filtresi yok
      }

      // ⏰ ZAMAN BAZLI FİLTRE - Sadece 50m altındaysa kontrol et
      // ⚡ 50m üzeri hareket varsa zaman filtresi atlanır!
      if (!is50mOrMore && _lastSentTime != null) {
        final timeSinceLastSend = DateTime.now().difference(_lastSentTime!);
        if (timeSinceLastSend < _minTimeBetweenSends) {
          print('⏭️ SKIP: Son gönderimden ${timeSinceLastSend.inSeconds} sn geçti (25 sn minimum limit)');
          return;
        }
      }

      // ⏰ BACKEND KONTROLÜ (3 dakika içinde gönderilmiş mi?)
      // Sadece 50m altındaysa backend kontrolü yap
      if (shouldCheckBackend) {
        final shouldSkip = await _shouldSkipLocationSend(courierId);
        
        if (shouldSkip) {
          print('⏭️ SKIP: Backend kontrolü - Son 3 dakikada konum gönderilmiş');
          return;
        } else {
          print('✅ Backend kontrolü: Son 3 dakikada konum gönderilmemiş, gönderilecek');
        }
      }

      // 🔄 Retry mekanizması ile gönder
      final success = await _sendLocationWithRetry(
        latitude: latitude,
        longitude: longitude,
        courierId: courierId,
        speedKmh: speedKmh,
      );

      if (success) {
        // ✅ Başarılı - Son gönderilen konumu ve zamanı kaydet
        _lastSentLatitude = latitude;
        _lastSentLongitude = longitude;
        _lastSentTime = DateTime.now(); // Son gönderim zamanını kaydet
        print('💾 Son gönderilen konum kaydedildi: ($latitude, $longitude) - $_lastSentTime');
      } else {
        // ❌ Başarısız - Queue'ya ekle
        print('📦 Konum queue\'ya ekleniyor (offline)');
        if (_locationQueue.length < _maxQueueSize) {
          _locationQueue.add({
            'latitude': latitude,
            'longitude': longitude,
            'speedKmh': speedKmh,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          print('📦 Queue boyutu: ${_locationQueue.length}');
        } else {
          print('⚠️ Queue dolu! En eski konum siliniyor');
          _locationQueue.removeAt(0);
          _locationQueue.add({
            'latitude': latitude,
            'longitude': longitude,
            'speedKmh': speedKmh,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }
    } catch (e) {
      print('❌❌❌ Konum gönderme HATASI: $e');
      print('   Hata tipi: ${e.runtimeType}');
      if (e is Error) {
        print('   Stack trace: ${e.stackTrace}');
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

    // 3. ⭐ KRİTİK: Background (arka plan) konum izni (Android 10+)
    if (permission != LocationPermission.always) {
      print('⚠️⚠️ ARKA PLAN konum izni YOK!');
      print('   Permission: $permission (always olmalı)');
      
      // Permission handler ile background location iste
      try {
        final bgStatus = await Permission.locationAlways.status;
        print('📍 Background izin durumu: $bgStatus');
        
        if (!bgStatus.isGranted) {
          print('⏳ Background izni isteniyor...');
          final result = await Permission.locationAlways.request();
          print('📍 Background izin sonucu: $result');
          
          if (!result.isGranted) {
            print('⚠️⚠️ BACKGROUND İZNİ VERİLMEDİ!');
            print('   Kullanıcı ayarlardan "Her zaman izin ver" seçmeli');
            return false;
          }
        }
        
        print('✅✅ Background konum izni verildi!');
      } catch (e) {
        print('❌ Background izin kontrolü hatası: $e');
      }
    } else {
      print('✅✅ Background konum izni zaten var!');
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

  /// Konum stream'i (harita için real-time)
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // 10 metre hareket ettiğinde güncelle
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
  /// Örnek: shift_service'te durum değiştiğinde bu metod çağrılabilir
  static void invalidateStatusCache() {
    print('🔄 Status cache invalidate edildi');
    _cachedCourierStatus = null;
    _lastStatusCheck = null;
    // Not: _lastSentLatitude ve _lastSentLongitude temizlenmez (konum cache'i)
    // Not: _lastBackendCheck temizlenmez (backend kontrol cache'i)
  }
}

