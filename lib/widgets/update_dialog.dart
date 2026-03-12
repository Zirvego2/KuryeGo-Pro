import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

/// 📱 Güncelleme Dialog Widget'ı
/// 
/// Zorunlu veya opsiyonel güncelleme için kullanılır
class UpdateDialog extends StatelessWidget {
  final bool isMandatory;
  final String currentVersion;
  final String latestVersion;
  final String? updateMessage;
  final String? playStoreUrl;
  final String? appStoreUrl;
  final String? directApkUrl; // ⭐ Acil durumlar için direkt APK indirme linki

  const UpdateDialog({
    super.key,
    required this.isMandatory,
    required this.currentVersion,
    required this.latestVersion,
    this.updateMessage,
    this.playStoreUrl,
    this.appStoreUrl,
    this.directApkUrl,
  });

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Zorunlu güncellemede geri tuşunu devre dışı bırak
      onWillPop: () async => !isMandatory,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.system_update,
              color: isMandatory ? Colors.red : Colors.blue,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isMandatory ? 'Zorunlu Güncelleme' : 'Yeni Sürüm Mevcut',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isMandatory ? Colors.red : Colors.blue,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (updateMessage != null && updateMessage!.isNotEmpty) ...[
                Text(
                  updateMessage!,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Mevcut Versiyon:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          currentVersion,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Yeni Versiyon:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          latestVersion,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isMandatory) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bu güncelleme zorunludur. Uygulamayı kullanmaya devam etmek için lütfen güncelleyin.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!isMandatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Daha Sonra'),
            ),
          ElevatedButton(
            onPressed: () => _openStore(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: isMandatory ? Colors.red : Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download, size: 20),
                SizedBox(width: 8),
                Text('Güncelle'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    try {
      final url = _getStoreUrl();
      print('📱 Açılacak URL: $url');
      
      // APK linki mi kontrol et
      final isApkUrl = url.toLowerCase().endsWith('.apk');
      
      final uri = Uri.parse(url);
      
      // ⭐ APK linki için özel işlem (Android)
      if (isApkUrl && Platform.isAndroid) {
        print('📱 APK linki tespit edildi, Android DownloadManager kullanılıyor...');
        
        try {
          // Android DownloadManager kullan (platform channel)
          const platform = MethodChannel('com.example.zirvego_flutter/download');
          await platform.invokeMethod('downloadApk', {'url': url});
          print('📱 ✅ APK indirme başlatıldı (DownloadManager)');
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('APK indirme başlatıldı. Bildirimlerden takip edebilirsiniz.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          
          // Zorunlu güncellemede dialog'u kapat
          if (isMandatory && context.mounted) {
            Navigator.of(context).pop(true);
          }
          return;
        } catch (e) {
          print('❌ DownloadManager hatası: $e');
          print('📱 Fallback: Tarayıcıda açılıyor...');
          
          // Fallback: Tarayıcıda aç
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            print('📱 ✅ APK linki tarayıcıda açıldı');
            
            if (isMandatory && context.mounted) {
              Navigator.of(context).pop(true);
            }
            return;
          } catch (e2) {
            print('❌ Tarayıcı açma hatası: $e2');
            // Son fallback: Kullanıcıya linki göster
            if (context.mounted) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('APK İndirme'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('APK dosyasını indirmek için aşağıdaki linki tarayıcınızda açın:'),
                      const SizedBox(height: 12),
                      SelectableText(
                        url,
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Tamam'),
                    ),
                  ],
                ),
              );
            }
            return;
          }
        }
      }
      
      // Play Store veya App Store linki için normal işlem
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        // Zorunlu güncellemede dialog'u kapat
        if (isMandatory && context.mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        print('❌ URL açılamadı: $url');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mağaza açılamadı. Lütfen manuel olarak güncelleyin.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('❌ URL açma hatası: $e');
      print('❌ Stack: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  String _getStoreUrl() {
    // Platform kontrolü
    if (!kIsWeb) {
      if (Platform.isAndroid) {
        // ⭐ Direkt APK linki varsa (zaten settings'ten kontrol edilmiş, useDirectApk true ise gelir)
        if (directApkUrl != null && directApkUrl!.isNotEmpty) {
          print('📱 ✅ Direkt APK linki kullanılıyor: $directApkUrl');
          return directApkUrl!;
        }
        // Direkt APK yoksa veya kullanılmıyorsa Play Store linkini kullan
        print('📱 Play Store linki kullanılıyor');
        return playStoreUrl ?? 
            'https://play.google.com/store/apps/details?id=com.example.zirvego_flutter';
      } else if (Platform.isIOS) {
        return appStoreUrl ?? 
            'https://apps.apple.com/app/id1234567890';
      }
    }
    
    // Fallback - önce directApkUrl, sonra playStoreUrl, sonra appStoreUrl
    return directApkUrl ?? playStoreUrl ?? appStoreUrl ?? '';
  }
}
