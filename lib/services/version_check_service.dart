import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 📱 Versiyon Kontrol Servisi
/// 
/// Özellikler:
/// - ✅ Firestore'dan mevcut versiyonu kontrol eder
/// - ✅ Kullanıcının versiyonunu karşılaştırır
/// - ✅ Zorunlu/opsiyonel güncelleme desteği
/// - ✅ Play Store/App Store'a yönlendirme
class VersionCheckService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  /// Versiyon bilgisi modeli
  static const String _versionCollection = 'app_version';
  static const String _versionDocument = 'current';

  /// Versiyon kontrolü yap
  /// 
  /// Returns: {
  ///   needsUpdate: bool,
  ///   isMandatory: bool,
  ///   currentVersion: String,
  ///   latestVersion: String,
  ///   updateMessage: String?,
  ///   playStoreUrl: String?,
  ///   appStoreUrl: String?
  /// }
  static Future<Map<String, dynamic>> checkVersion() async {
    try {
      print('📱 Versiyon kontrolü başlatılıyor...');
      
      // Kullanıcının mevcut versiyonunu al
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // Örn: "8.6.7"
      final buildNumber = packageInfo.buildNumber; // Örn: "867"
      
      print('📱 Mevcut versiyon: $currentVersion+$buildNumber');
      
      // Firestore'dan güncel versiyon bilgisini çek
      print('📱 Firestore\'dan versiyon bilgisi çekiliyor...');
      print('   Collection: $_versionCollection');
      print('   Document: $_versionDocument');
      
      final versionDoc = await _db
          .collection(_versionCollection)
          .doc(_versionDocument)
          .get();
      
      print('📱 Firestore sorgu sonucu:');
      print('   - Document exists: ${versionDoc.exists}');
      print('   - Document ID: ${versionDoc.id}');
      
      if (!versionDoc.exists) {
        print('⚠️ Versiyon bilgisi Firestore\'da bulunamadı');
        print('⚠️ Collection ve Document ID\'yi kontrol edin:');
        print('   Collection: $_versionCollection');
        print('   Document: $_versionDocument');
        return {
          'needsUpdate': false,
          'isMandatory': false,
          'currentVersion': currentVersion,
          'latestVersion': currentVersion,
        };
      }
      
      final versionData = versionDoc.data();
      print('📱 Firestore verisi: $versionData');
      
      if (versionData == null) {
        print('⚠️ Firestore document boş');
        return {
          'needsUpdate': false,
          'isMandatory': false,
          'currentVersion': currentVersion,
          'latestVersion': currentVersion,
        };
      }
      
      final latestVersionRaw = versionData['version'];
      print('📱 Firestore\'dan gelen version (raw): $latestVersionRaw (${latestVersionRaw.runtimeType})');
      
      String latestVersion;
      if (latestVersionRaw is String) {
        latestVersion = latestVersionRaw.trim(); // Boşlukları temizle
      } else {
        latestVersion = latestVersionRaw?.toString().trim() ?? currentVersion;
      }
      
      final isMandatory = versionData['mandatory'] as bool? ?? false;
      final updateMessage = versionData['message'] as String?;
      String? trimUrl(dynamic v) {
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }
      final playStoreUrl = trimUrl(versionData['playStoreUrl']);
      final appStoreUrl = trimUrl(versionData['appStoreUrl']);
      final directApkUrl = trimUrl(versionData['directApkUrl']);
      
      print('📱 Sunucudaki versiyon (temizlenmiş): "$latestVersion"');
      print('📱 Zorunlu güncelleme: $isMandatory');
      print('📱 Mesaj: $updateMessage');
      print('📱 Direct APK URL: ${directApkUrl != null ? "Mevcut" : "Yok"}');

      // ⭐ current.directApkUrl doluysa her zaman direkt APK indirme (settings/useDirectApk gerekmez)
      final bool useDirectApk =
          directApkUrl != null && directApkUrl.isNotEmpty;
      final String? finalDirectApkUrl = useDirectApk ? directApkUrl : null;
      if (useDirectApk) {
        print('📱 ✅ directApkUrl kullanılacak (direkt indirme): $finalDirectApkUrl');
      }
      
      // Versiyonları karşılaştır
      final comparisonResult = _compareVersions(currentVersion, latestVersion);
      final needsUpdate = comparisonResult < 0;
      
      print('📱 Versiyon karşılaştırma sonucu: $comparisonResult');
      print('   (-1 = current < latest, 0 = eşit, 1 = current > latest)');
      print('📱 Güncelleme gerekli: $needsUpdate');
      
      return {
        'needsUpdate': needsUpdate,
        'isMandatory': isMandatory,
        'currentVersion': currentVersion,
        'latestVersion': latestVersion,
        'updateMessage': updateMessage,
        'playStoreUrl': playStoreUrl,
        'appStoreUrl': appStoreUrl,
        'directApkUrl': finalDirectApkUrl,
        'useDirectApk': useDirectApk,
      };
    } catch (e, stackTrace) {
      print('❌ Versiyon kontrolü hatası: $e');
      print('❌ Stack: $stackTrace');
      
      // Hata durumunda güncelleme gerekmediğini döndür (uygulama çalışmaya devam etsin)
      final packageInfo = await PackageInfo.fromPlatform();
      return {
        'needsUpdate': false,
        'isMandatory': false,
        'currentVersion': packageInfo.version,
        'latestVersion': packageInfo.version,
      };
    }
  }
  
  /// Versiyonları karşılaştır
  /// Returns: -1 (current < latest), 0 (eşit), 1 (current > latest)
  static int _compareVersions(String current, String latest) {
    try {
      // Boşlukları temizle
      current = current.trim();
      latest = latest.trim();
      
      print('📱 Versiyon karşılaştırması:');
      print('   Current: "$current"');
      print('   Latest: "$latest"');
      
      final currentParts = current.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
      final latestParts = latest.split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
      
      print('   Current parts: $currentParts');
      print('   Latest parts: $latestParts');
      
      // Eksik kısımları 0 ile doldur
      while (currentParts.length < latestParts.length) {
        currentParts.add(0);
      }
      while (latestParts.length < currentParts.length) {
        latestParts.add(0);
      }
      
      for (int i = 0; i < currentParts.length; i++) {
        if (currentParts[i] < latestParts[i]) {
          print('   Sonuç: Current < Latest (${currentParts[i]} < ${latestParts[i]})');
          return -1;
        } else if (currentParts[i] > latestParts[i]) {
          print('   Sonuç: Current > Latest (${currentParts[i]} > ${latestParts[i]})');
          return 1;
        }
      }
      
      print('   Sonuç: Current == Latest');
      return 0;
    } catch (e, stackTrace) {
      print('⚠️ Versiyon karşılaştırma hatası: $e');
      print('⚠️ Stack: $stackTrace');
      return 0; // Hata durumunda eşit kabul et
    }
  }
  
  /// Play Store'a yönlendir
  static Future<void> openPlayStore(String? url) async {
    try {
      // Eğer özel URL varsa onu kullan, yoksa varsayılan paket adını kullan
      final packageInfo = await PackageInfo.fromPlatform();
      final packageName = packageInfo.packageName;
      
      final playStoreUrl = url ?? 
          'https://play.google.com/store/apps/details?id=$packageName';
      
      print('📱 Play Store açılıyor: $playStoreUrl');
      
      final uri = Uri.parse(playStoreUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('❌ Play Store açılamadı');
      }
    } catch (e) {
      print('❌ Play Store açma hatası: $e');
    }
  }
  
  /// App Store'a yönlendir
  static Future<void> openAppStore(String? url) async {
    try {
      // Eğer özel URL varsa onu kullan, yoksa varsayılan app ID'yi kullan
      final packageInfo = await PackageInfo.fromPlatform();
      final bundleId = packageInfo.packageName;
      
      final appStoreUrl = url ?? 
          'https://apps.apple.com/app/id$bundleId';
      
      print('📱 App Store açılıyor: $appStoreUrl');
      
      final uri = Uri.parse(appStoreUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('❌ App Store açılamadı');
      }
    } catch (e) {
      print('❌ App Store açma hatası: $e');
    }
  }
  
  /// Platforma göre uygun mağazaya yönlendir
  static Future<void> openStore({
    String? playStoreUrl,
    String? appStoreUrl,
  }) async {
    // Platform kontrolü için dart:io kullan
    // Flutter'da Platform.isAndroid ve Platform.isIOS kullanılır
    // Ancak burada daha basit bir yaklaşım: her iki URL'i de deneyebiliriz
    // veya package_info'dan platform bilgisi alabiliriz
    
    // Şimdilik Android varsayalım (Play Store)
    // iOS için ayrı bir kontrol eklenebilir
    try {
      // Android için Play Store
      await openPlayStore(playStoreUrl);
    } catch (e) {
      // iOS için App Store (eğer Android açılamazsa)
      await openAppStore(appStoreUrl);
    }
  }
}
