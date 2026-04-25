import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/version_check_service.dart';
import 'widgets/update_dialog.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';

final _locationLifecycleBridge = _LocationLifecycleBridge();

/// iOS: ön plana dönünce kalıcı konum kuyruğunu gönder; konum akışını tazele
class _LocationLifecycleBridge with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(LocationService.onApplicationResumed());
    }
  }
}

late bool _onboardingShown;

void main() async {
  print('🚀 ========================================');
  print('🚀 UYGULAMA BAŞLATILIYOR...');
  print('🚀 ========================================');
  
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addObserver(_locationLifecycleBridge);

  // Onboarding daha önce gösterildi mi?
  final prefs = await SharedPreferences.getInstance();
  _onboardingShown = prefs.getBool('onboarding_shown') ?? false;

  await initializeDateFormatting('tr', null);

  // Firebase başlat (iOS'ta AppDelegate'te zaten configure edilmiş olabilir)
  print('🔥 Firebase başlatılıyor...');
  try {
    // Firebase zaten initialize edilmiş mi kontrol et
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('✅ Firebase başlatıldı');
    } else {
      print('✅ Firebase zaten başlatılmış (native tarafında)');
    }
  } catch (e) {
    // Duplicate app hatası olabilir, görmezden gel
    if (e.toString().contains('duplicate-app')) {
      print('✅ Firebase zaten başlatılmış');
    } else {
      print('❌ Firebase başlatma hatası: $e');
      rethrow;
    }
  }

  runApp(const ZirveGoApp());

  // Uygulamanın ilk frame'ini geciktirmemek için servisleri arka planda başlat.
  unawaited(_initializeStartupServices());
}

Future<void> _initializeStartupServices() async {
  // 🔔 Notification service başlat (FCM token + bildirim ayarları)
  print('🔔 Notification Service başlatılıyor...');
  try {
    await NotificationService.initialize();
    print('✅ Notification Service başlatıldı');
  } catch (e, stackTrace) {
    print('❌ Notification Service BAŞLATMA HATASI!');
    print('❌ Hata: $e');
    print('❌ Stack: $stackTrace');
  }

  // Background location service başlat
  print('📍 Location Service başlatılıyor...');
  try {
    await LocationService.initialize();
    print('✅ Location Service başlatıldı');
  } catch (e, stackTrace) {
    print('❌ Location Service BAŞLATMA HATASI!');
    print('❌ Hata: $e');
    print('❌ Stack: $stackTrace');
  }

  print('🚀 ========================================');
  print('🚀 UYGULAMA HAZIR!');
  print('🚀 ========================================');
}

class ZirveGoApp extends StatelessWidget {
  const ZirveGoApp({super.key});

  // ⭐ Global Navigator Key - Versiyon kontrolü için
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// MaterialApp.builder her rebuild'de çalışır; yalnızca bir kez zamanla.
  static bool _initialVersionCheckScheduled = false;

  /// Aynı anda birden fazla checkVersionAndShowDialog çağrısını tek Future'da birleştir.
  static Future<void>? _activeVersionCheck;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ZirveGo Kurye',
      debugShowCheckedModeBanner: false,
      
      // ⭐ Localization desteği (DatePicker, TimePicker vs. için gerekli)
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'), // Türkçe
        Locale('en', 'US'), // İngilizce (fallback)
      ],
      locale: const Locale('tr', 'TR'), // Varsayılan dil: Türkçe
      
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      home: _onboardingShown
          ? const LoginScreen()
          : OnboardingScreen(onDone: () {
              ZirveGoApp.navigatorKey.currentState?.pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }),
      
      // ⭐ Versiyon kontrolü — yalnızca ilk frame sonrası bir kez (builder tekrarlarında tekrarlanmaz)
      builder: (context, child) {
        if (!_initialVersionCheckScheduled) {
          _initialVersionCheckScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkVersionAfterBuild();
          });
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
  
  /// Versiyon kontrolü - Navigator hazır olduğunda
  static Future<void> _checkVersionAfterBuild() async {
    // Navigator'ın hazır olmasını bekle (max 3 saniye)
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      final navigatorContext = navigatorKey.currentContext;
      if (navigatorContext != null && navigatorContext.mounted) {
        print('📱 Navigator hazır, versiyon kontrolü başlatılıyor...');
        await checkVersionAndShowDialog(navigatorContext);
        return;
      }
    }
    print('⚠️ Navigator context 3 saniye içinde hazır olmadı, versiyon kontrolü atlandı');
  }

  /// Versiyon kontrolü yap ve gerekirse dialog göster
  static Future<void> checkVersionAndShowDialog(BuildContext context) async {
    if (_activeVersionCheck != null) {
      await _activeVersionCheck;
      return;
    }
    _activeVersionCheck = _checkVersionAndShowDialogBody(context);
    try {
      await _activeVersionCheck;
    } finally {
      _activeVersionCheck = null;
    }
  }

  static Future<void> _checkVersionAndShowDialogBody(BuildContext context) async {
    try {
      print('📱 ========================================');
      print('📱 VERSİYON KONTROLÜ BAŞLATILIYOR...');
      print('📱 ========================================');
      
      final versionInfo = await VersionCheckService.checkVersion();
      
      print('📱 Kontrol sonucu:');
      print('   - needsUpdate: ${versionInfo['needsUpdate']}');
      print('   - isMandatory: ${versionInfo['isMandatory']}');
      print('   - currentVersion: ${versionInfo['currentVersion']}');
      print('   - latestVersion: ${versionInfo['latestVersion']}');
      print('   - updateMessage: ${versionInfo['updateMessage']}');
      print('   - directApkUrl: ${versionInfo['directApkUrl']}');
      print('   - useDirectApk: ${versionInfo['useDirectApk']}');
      print('   - playStoreUrl: ${versionInfo['playStoreUrl']}');
      
      if (versionInfo['needsUpdate'] == true) {
        if (context.mounted) {
          print('📱 ✅ Güncelleme gerekli, dialog gösteriliyor...');
          
          await Future.delayed(const Duration(milliseconds: 500)); // Kısa bir gecikme
          
          if (context.mounted) {
            showDialog(
              context: context,
              barrierDismissible: versionInfo['isMandatory'] == false,
              builder: (context) => UpdateDialog(
                isMandatory: versionInfo['isMandatory'] == true,
                currentVersion: versionInfo['currentVersion'] as String,
                latestVersion: versionInfo['latestVersion'] as String,
                updateMessage: versionInfo['updateMessage'] as String?,
                playStoreUrl: versionInfo['playStoreUrl'] as String?,
                appStoreUrl: versionInfo['appStoreUrl'] as String?,
                directApkUrl: versionInfo['directApkUrl'] as String?,
              ),
            );
            print('📱 ✅ Dialog gösterildi');
          } else {
            print('⚠️ Context artık mounted değil, dialog gösterilemedi');
          }
        } else {
          print('⚠️ Context mounted değil, dialog gösterilemedi');
        }
      } else {
        print('✅ Uygulama güncel, güncelleme gerekmiyor');
      }
      
      print('📱 ========================================');
    } catch (e, stackTrace) {
      print('❌ ========================================');
      print('❌ VERSİYON KONTROLÜ HATASI!');
      print('❌ Hata: $e');
      print('❌ Stack: $stackTrace');
      print('❌ ========================================');
      // Hata durumunda uygulama çalışmaya devam etsin
    }
  }

}