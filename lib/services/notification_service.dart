import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';
import 'dart:io' show Platform;

/// 🔔 Firebase Cloud Messaging ve Bildirim Servisi
/// React Native usePushNotifications.js karşılığı
class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  
  static String? _fcmToken;
  
  /// Bildirim servisini başlat
  static Future<void> initialize() async {
    try {
      print('🔔 ========================================');
      print('🔔 Notification Service başlatılıyor...');
      print('🔔 ========================================');
      
      // 1️⃣ Bildirim izinlerini iste
      print('🔔 Adım 1: Bildirim izinleri isteniyor...');
      await _requestPermissions();
      print('✅ Adım 1: Bildirim izinleri tamam');
      
      // 2️⃣ Local notifications kurulumu
      print('🔔 Adım 2: Local notifications kuruluyor...');
      await _setupLocalNotifications();
      print('✅ Adım 2: Local notifications tamam');
      
      // 3️⃣ FCM token al
      print('🔔 Adım 3: FCM token alınıyor...');
      await _getFCMToken();
      print('✅ Adım 3: FCM token tamam');
      
      // 4️⃣ Background message handler
      print('🔔 Adım 4: Background message handler ayarlanıyor...');
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      print('✅ Adım 4: Background handler tamam');
      
      // 5️⃣ Foreground message listener
      print('🔔 Adım 5: Foreground message listener ayarlanıyor...');
      _setupForegroundMessageListener();
      print('✅ Adım 5: Foreground listener tamam');
      
      // 6️⃣ Token refresh listener
      print('🔔 Adım 6: Token refresh listener ayarlanıyor...');
      _setupTokenRefreshListener();
      print('✅ Adım 6: Token refresh listener tamam');
      
      print('🔔 ========================================');
      print('✅ Notification Service başlatıldı!');
      print('🔔 ========================================');
    } catch (e, stackTrace) {
      print('❌ ========================================');
      print('❌ Notification Service HATA!');
      print('❌ Hata: $e');
      print('❌ Stack: $stackTrace');
      print('❌ ========================================');
    }
  }
  
  /// Bildirim izinlerini iste
  static Future<void> _requestPermissions() async {
    try {
      print('📲 Bildirim izni isteniyor...');
      
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: true,
        provisional: false,
      );
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Bildirim izni VERİLDİ!');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        print('⚠️ Geçici bildirim izni verildi');
      } else {
        print('❌ Bildirim izni REDDEDİLDİ!');
      }
    } catch (e) {
      print('❌ Bildirim izni hatası: $e');
    }
  }
  
  /// Local notifications kurulumu (ses ve titreşim ayarları)
  static Future<void> _setupLocalNotifications() async {
    try {
      print('🔧 Local notifications kuruluyor...');
      
      // Android ayarları
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS ayarları
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      
      // Android Notification Channel oluştur (React Native'deki gibi)
      if (Platform.isAndroid) {
        print('🔧 Android notification channel kuruluyor...');
        
        // Titreşim deseni (5 kere güçlü titreşim - her durumda çalışır)
        final vibrationPattern = Int64List.fromList([0, 800, 300, 800, 300, 800, 300, 800, 300, 800]);
        
        // Sipariş Bildirimleri kanalı (güçlü titreşim - her durumda çalışır)
        final ordersChannel = AndroidNotificationChannel(
          'orders2',
          'Sipariş Atamaları',
          description: 'Yeni sipariş atamalarında bildirim alırsınız',
          importance: Importance.max, // ⭐ MAX importance - sessiz modda da çalışır
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('order_notification'),
          enableVibration: true, // ⭐ Titreşim her zaman aktif
          vibrationPattern: vibrationPattern, // ⭐ Güçlü titreşim deseni
          enableLights: true,
          ledColor: const Color.fromARGB(255, 255, 0, 0),
          showBadge: true,
        );
        
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(ordersChannel);
        
        print('✅ Android notification channel OLUŞTURULDU: orders2');
        
        // Default kanal (genel bildirimler - güçlü titreşim)
        final defaultChannel = AndroidNotificationChannel(
          'default',
          'Sipariş Bildirimleri',
          description: 'Genel sipariş bildirimleri',
          importance: Importance.max, // ⭐ MAX importance - sessiz modda da çalışır
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('order_notification'),
          enableVibration: true, // ⭐ Titreşim her zaman aktif
          vibrationPattern: vibrationPattern, // ⭐ Güçlü titreşim deseni
          enableLights: true,
          ledColor: const Color.fromARGB(255, 255, 0, 0),
          showBadge: true,
        );
        
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(defaultChannel);
        
        print('✅ Android notification channel OLUŞTURULDU: default');
      }
      
      print('✅ Local notifications kuruldu');
    } catch (e) {
      print('❌ Local notifications kurulum hatası: $e');
    }
  }
  
  /// FCM token al ve Firestore'a kaydet
  static Future<String?> _getFCMToken() async {
    try {
      print('🔑 FCM token alınıyor...');
      
      _fcmToken = await _firebaseMessaging.getToken();
      
      if (_fcmToken != null) {
        print('✅ FCM Token alındı: ${_fcmToken!.substring(0, 20)}...');
        
        // Token'ı SharedPreferences'a kaydet
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', _fcmToken!);
        
        // Firestore'a kaydet (eğer kurye login olmuşsa)
        await _saveTokenToFirestore(_fcmToken!);
        
        return _fcmToken;
      } else {
        print('❌ FCM token alınamadı!');
        return null;
      }
    } catch (e) {
      print('❌ FCM token alma hatası: $e');
      return null;
    }
  }
  
  /// Token'ı Firestore'a kaydet (t_courier koleksiyonuna)
  static Future<void> _saveTokenToFirestore(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final courierId = prefs.getInt('courier_id');
      
      if (courierId == null) {
        print('⚠️ Kurye ID bulunamadı, token Firestore\'a kaydedilemedi');
        return;
      }
      
      print('💾 FCM Token Firestore\'a kaydediliyor (Kurye ID: $courierId)...');
      
      await FirebaseService.updateFCMToken(courierId, token);
      
      print('✅ FCM Token Firestore\'a kaydedildi!');
    } catch (e) {
      print('❌ Token Firestore kaydetme hatası: $e');
    }
  }
  
  /// Token yenilendiğinde otomatik güncelle
  static void _setupTokenRefreshListener() {
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      print('🔄 FCM Token yenilendi: ${newToken.substring(0, 20)}...');
      _fcmToken = newToken;
      _saveTokenToFirestore(newToken);
    });
  }
  
  /// Foreground mesajları dinle (uygulama açıkken)
  static void _setupForegroundMessageListener() {
    print('👂 ========================================');
    print('👂 FOREGROUND MESSAGE LISTENER BAŞLATILIYOR');
    print('👂 ========================================');
    print('👂 FirebaseMessaging.onMessage.listen() çağrılıyor...');
    
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('');
      print('🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔');
      print('🔔 FOREGROUND MESAJ ALINDI!');
      print('🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔');
      print('   📌 Timestamp: ${DateTime.now()}');
      print('   📌 Mesaj ID: ${message.messageId}');
      print('   📌 Başlık: ${message.notification?.title ?? "YOK"}');
      print('   📌 İçerik: ${message.notification?.body ?? "YOK"}');
      print('   📌 Data: ${message.data}');
      print('   📌 Android: ${message.notification?.android}');
      print('   📌 iOS: ${message.notification?.apple}');
      print('   📌 Category: ${message.category}');
      print('   📌 CollapseKey: ${message.collapseKey}');
      print('   📌 ContentAvailable: ${message.contentAvailable}');
      print('   📌 MutableContent: ${message.mutableContent}');
      print('   📌 SenderId: ${message.senderId}');
      print('   📌 ThreadId: ${message.threadId}');
      print('   📌 TTL: ${message.ttl}');
      print('🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔🔔');
      print('');
      
      // Telefonu titreştir (sistem titreşimi - güçlü desen)
      try {
        if (await Vibration.hasVibrator() ?? false) {
          // Güçlü titreşim deseni: 800ms titreşim, 300ms bekleme, 800ms titreşim, 300ms bekleme, 800ms titreşim
          Vibration.vibrate(pattern: [0, 800, 300, 800, 300, 800]);
          print('📳 Telefon titreşimi tetiklendi (Firebase mesajı - sistem titreşimi)');
        } else {
          // Titreşim desteklenmiyorsa HapticFeedback kullan
          HapticFeedback.heavyImpact();
          print('📳 HapticFeedback kullanıldı (titreşim desteklenmiyor)');
        }
      } catch (e) {
        print('❌ Titreşim hatası: $e');
        // Fallback olarak HapticFeedback kullan
        try {
          HapticFeedback.heavyImpact();
        } catch (_) {}
      }
      
      // Local bildirim göster
      _showLocalNotification(message, isBackground: false);
    }, onError: (error) {
      print('');
      print('❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌');
      print('❌ FOREGROUND MESSAGE HATA!');
      print('❌ Hata: $error');
      print('❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌❌');
      print('');
    });
    
    print('✅ Foreground listener kuruldu ve DİNLİYOR!');
    print('✅ Şimdi bildirim bekleniyor...');
    print('👂 ========================================');
  }
  
  /// Local bildirim göster (foreground ve background için)
  static Future<void> _showLocalNotification(RemoteMessage message, {bool isBackground = false}) async {
    try {
      print('📱 Local bildirim gösteriliyor...');
      print('   📌 İsBackground: $isBackground');
      
      // ⭐ Uygulama durumu kontrolü
      final prefs = await SharedPreferences.getInstance();
      final appIsRunning = prefs.getBool('app_is_running') ?? false;
      
      // ⭐ iOS için özel kontrol: Background handler'dan geliyorsa her zaman göster
      // ⭐ Android için: app_is_running kontrolü yapılabilir ama background'da her zaman göster
      final shouldShowNotification = isBackground || !appIsRunning;
      final shouldPlaySound = isBackground || !appIsRunning; // Background'da veya uygulama kapalıysa ses çal
      
      if (!shouldShowNotification) {
        print('📱 Uygulama içinde (foreground) - Bildirim gösterilmeyecek (definite.mp3 çalacak)');
        return;
      } else {
        print('📱 Uygulama dışında veya background - Bildirim gösterilecek');
        if (shouldPlaySound) {
          print('   🔊 Ses: order_notification.mp3');
        } else {
          print('   🔇 Ses: KAPALI');
        }
      }
      
      final notification = message.notification;
      final android = message.notification?.android;
      
      if (notification == null) {
        print('⚠️ Notification null - Data-only message olabilir');
        
        // Data-only message için manuel bildirim oluştur
        if (message.data.isNotEmpty) {
          print('📦 Data-only message tespit edildi, manuel bildirim oluşturuluyor');
          
          final title = message.data['title'] ?? 'Yeni Sipariş';
          final body = message.data['body'] ?? 'Yeni bir sipariş atandı';
          
          // Güçlü titreşim deseni (5 kere)
          final vibrationPattern = Int64List.fromList([0, 800, 300, 800, 300, 800, 300, 800, 300, 800]);
          
          await _localNotifications.show(
            DateTime.now().millisecondsSinceEpoch.remainder(100000),
            title,
            body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                'orders2',
                'Sipariş Atamaları',
                channelDescription: 'Yeni sipariş atamalarında bildirim alırsınız',
                importance: Importance.max, // ⭐ MAX importance
                priority: Priority.max, // ⭐ MAX priority - sessiz modda da titreşir
                playSound: shouldPlaySound,
                sound: shouldPlaySound ? const RawResourceAndroidNotificationSound('order_notification') : null,
                enableVibration: true, // ⭐ Her zaman titreşim aktif
                vibrationPattern: vibrationPattern, // ⭐ Güçlü titreşim deseni
                enableLights: true,
                ledColor: const Color.fromARGB(255, 255, 0, 0),
                ledOnMs: 1000,
                ledOffMs: 500,
                icon: '@mipmap/ic_launcher',
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: shouldPlaySound,
                sound: shouldPlaySound ? 'order_notification.caf' : null,
                categoryIdentifier: 'orders2',
              ),
            ),
            payload: message.data.toString(),
          );
          
          print('✅ Data-only bildirim gösterildi');
        }
        return;
      }
      
      // Normal notification mesajı
      print('📬 Normal notification message işleniyor');
      print('   Başlık: ${notification.title}');
      print('   İçerik: ${notification.body}');
      
      // Güçlü titreşim deseni (5 kere - her durumda çalışır)
      final vibrationPattern = Int64List.fromList([0, 800, 300, 800, 300, 800, 300, 800, 300, 800]);
      
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'orders2',
            'Sipariş Atamaları',
            channelDescription: 'Yeni sipariş atamalarında bildirim alırsınız',
            importance: Importance.max,
            priority: Priority.max, // ⭐ MAX priority - sessiz modda da titreşir
            playSound: shouldPlaySound,
            sound: shouldPlaySound ? const RawResourceAndroidNotificationSound('order_notification') : null,
            enableVibration: true, // ⭐ Her zaman titreşim aktif (sesli/sessiz modda)
            vibrationPattern: vibrationPattern, // ⭐ Güçlü titreşim deseni
            enableLights: true,
            ledColor: const Color.fromARGB(255, 255, 0, 0),
            ledOnMs: 1000,
            ledOffMs: 500,
            icon: android?.smallIcon ?? '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: shouldPlaySound,
            sound: shouldPlaySound ? 'order_notification.caf' : null,
            categoryIdentifier: 'orders2',
          ),
        ),
        payload: message.data.toString(),
      );
      
      print('✅ Local bildirim başarıyla gösterildi');
      if (shouldPlaySound) {
        print('   🔊 Ses: order_notification.mp3 (uygulama dışında)');
      } else {
        print('   🔇 Ses: KAPALI (uygulama içinde - definite.mp3 çalacak)');
      }
      print('   📳 Titreşim: 3x güçlü');
      print('   💡 LED: Kırmızı');
    } catch (e, stackTrace) {
      print('❌ ========================================');
      print('❌ Local bildirim gösterme HATA!');
      print('❌ Hata: $e');
      print('❌ Stack: $stackTrace');
      print('❌ ========================================');
    }
  }
  
  /// Bildirime tıklandığında (foreground)
  static void _onNotificationTapped(NotificationResponse response) {
    print('👆 Bildirime tıklandı: ${response.payload}');
    // TODO: Sipariş detay sayfasına yönlendir
  }
  
  /// Manuel token al ve kaydet (login sonrası çağrılabilir)
  static Future<void> refreshAndSaveToken() async {
    try {
      print('🔄 Token yenileniyor ve kaydediliyor...');
      await _getFCMToken();
    } catch (e) {
      print('❌ Token yenileme hatası: $e');
    }
  }
  
  /// Mevcut token'ı döndür
  static String? get currentToken => _fcmToken;
}

/// Background message handler (top-level function olmalı)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('');
  print('🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙');
  print('🌙 BACKGROUND MESAJ ALINDI!');
  print('🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙');
  print('   📌 Timestamp: ${DateTime.now()}');
  print('   📌 Mesaj ID: ${message.messageId}');
  print('   📌 Başlık: ${message.notification?.title ?? "YOK"}');
  print('   📌 İçerik: ${message.notification?.body ?? "YOK"}');
  print('   📌 Data: ${message.data}');
  print('🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙🌙');
  print('');
  
  // ⭐ Background'da bildirim göster (titreşim ile)
  // ⭐ iOS için kritik: Background handler'dan geldiği için her zaman bildirim göster
  await NotificationService._showLocalNotification(message, isBackground: true);
}

