import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kInitialMediaPermissionsKey = 'initial_media_permissions_v1';

/// Ana ekrana ilk girişte (oturum açıkken) galeri/foto iznini uygulama içinden ister.
/// Kamera izni istenmez (Android sistem diyaloğunda "video kaydı" metni çıkmaması için).
/// Kurulum başına bir kez çalışır.
///
/// iOS: App Store 5.1.1(iv) — foto izni yalnızca kullanıcı profilde "Galeriden seç"
/// dediğinde istenir ([MainProfileScreen]); ana ekranda proaktif istek yok.
Future<void> requestInitialMediaPermissionsIfNeeded() async {
  if (kIsWeb) return;
  if (Platform.isIOS) return;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kInitialMediaPermissionsKey) == true) return;

  await prefs.setBool(_kInitialMediaPermissionsKey, true);

  try {
    if (Platform.isAndroid) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk >= 33) {
        await Permission.photos.request();
      } else {
        await Permission.storage.request();
      }
    }
  } catch (_) {
    // İzin API hatası — sessiz geç
  }
}
