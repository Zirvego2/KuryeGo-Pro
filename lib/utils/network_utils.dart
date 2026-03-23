import 'package:http/http.dart' as http;

class NetworkUtils {
  const NetworkUtils._();

  /// Basit internet erişim kontrolü.
  /// Ağ yoksa veya timeout olursa false döner.
  static Future<bool> hasInternetConnection() async {
    try {
      final response = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
