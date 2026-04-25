import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

/// 📱 Güncelleme Dialog Widget'ı
///
/// Zorunlu veya opsiyonel güncelleme için kullanılır
class UpdateDialog extends StatefulWidget {
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
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _actionInProgress = false;

  /// Firestore’da direkt APK linki varsa mağaza yerine yalnızca dosya indirilir.
  bool get _hasDirectApk {
    final a = widget.directApkUrl?.trim();
    return a != null && a.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Zorunlu güncellemede geri tuşunu devre dışı bırak
      onWillPop: () async => !widget.isMandatory,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.system_update,
              color: widget.isMandatory ? Colors.red : Colors.blue,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.isMandatory ? 'Zorunlu Güncelleme' : 'Yeni Sürüm Mevcut',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: widget.isMandatory ? Colors.red : Colors.blue,
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
              if (widget.updateMessage != null && widget.updateMessage!.isNotEmpty) ...[
                Text(
                  widget.updateMessage!,
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
                          widget.currentVersion,
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
                          widget.latestVersion,
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
              if (widget.isMandatory) ...[
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
          if (!widget.isMandatory)
            TextButton(
              onPressed: _actionInProgress ? null : () => Navigator.of(context).pop(false),
              child: const Text('Daha Sonra'),
            ),
          ElevatedButton(
            onPressed: _actionInProgress ? null : () => _openStore(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.isMandatory ? Colors.red : Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.download, size: 20),
                const SizedBox(width: 8),
                Text(_hasDirectApk ? 'APK İndir' : 'Güncelle'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      final url = await _getStoreUrl();
      print('📱 Açılacak URL: $url');

      // Firebase Storage: .../x.apk?alt=media&token=... — sorgu string'i yüzünden endsWith('.apk') yanlış olur
      final isApkUrl = _isLikelyApkDownloadUrl(url);

      final uri = Uri.parse(url);

      // ⭐ APK linki (Android): önce tarayıcı — Chrome vb. indirmeyi genelde sorunsuz başlatır.
      // Android 11+ için AndroidManifest'te VIEW https/http queries gerekir; yoksa hiçbir şey olmazdı.
      if (isApkUrl && Platform.isAndroid) {
        print('📱 APK linki tespit edildi');

        Future<void> finishFlow({required String snackText}) async {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(snackText), duration: const Duration(seconds: 3)),
          );
          if (widget.isMandatory) {
            Navigator.of(context).pop(true);
          }
        }

        try {
          final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (launched) {
            print('📱 ✅ APK linki tarayıcıda açıldı');
            await finishFlow(
              snackText: 'İndirme tarayıcıda başlatıldı. İndirilenler veya bildirimleri kontrol edin.',
            );
            return;
          }
        } catch (e) {
          print('❌ launchUrl (APK): $e');
        }

        try {
          const platform = MethodChannel('com.zirvego.kurye/download');
          final method = await platform.invokeMethod<String>('downloadApk', {'url': url});
          print('📱 ✅ APK: native sonuç = $method');
          final msg = method == 'download_manager'
              ? 'APK indirmesi başlatıldı. Bildirim çubuğundan takip edebilirsiniz.'
              : 'İndirme tarayıcıda açıldı.';
          await finishFlow(snackText: msg);
          return;
        } catch (e) {
          print('❌ Native APK indirme: $e');
        }

        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          await finishFlow(
            snackText: 'İndirme tarayıcıda başlatıldı. İndirilenler veya bildirimleri kontrol edin.',
          );
          return;
        } catch (e) {
          print('❌ Son launchUrl: $e');
        }

        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('APK indirilemedi'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Linki kopyalayıp Chrome veya başka bir tarayıcıda açmayı deneyin. Sunucuda dosya yoksa (404) indirme başlamaz.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    url,
                    style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Tamam')),
              ],
            ),
          );
        }
        return;
      }

      // Play Store veya App Store linki için normal işlem
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

        // Zorunlu güncellemede dialog'u kapat
        if (widget.isMandatory && context.mounted) {
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
    } finally {
      if (mounted) {
        setState(() => _actionInProgress = false);
      }
    }
  }

  /// Gerçek paket adı (build.gradle applicationId) ile Play Store yedeği
  Future<String> _getStoreUrl() async {
    final pkg = (await PackageInfo.fromPlatform()).packageName;

    // Platform kontrolü
    if (!kIsWeb) {
      if (Platform.isAndroid) {
        final apk = widget.directApkUrl?.trim();
        if (apk != null && apk.isNotEmpty) {
          print('📱 ✅ Direkt APK linki kullanılıyor: $apk');
          return apk;
        }
        print('📱 Play Store linki kullanılıyor');
        final play = widget.playStoreUrl?.trim();
        if (play != null && play.isNotEmpty) return play;
        return 'https://play.google.com/store/apps/details?id=$pkg';
      } else if (Platform.isIOS) {
        final store = widget.appStoreUrl?.trim();
        if (store != null && store.isNotEmpty) return store;
        return 'https://apps.apple.com/app/id1234567890';
      }
    }

    return widget.directApkUrl?.trim() ??
        widget.playStoreUrl?.trim() ??
        widget.appStoreUrl?.trim() ??
        'https://play.google.com/store/apps/details?id=$pkg';
  }

  /// Doğrudan APK indirme (Firebase Storage dahil); mağaza HTTPS URL'lerini ele
  static bool _isLikelyApkDownloadUrl(String url) {
    final lower = url.toLowerCase().trim();
    if (lower.contains('play.google.com') ||
        lower.contains('apps.apple.com')) {
      return false;
    }
    final pathOnly = lower.split('?').first;
    return pathOnly.endsWith('.apk');
  }
}
