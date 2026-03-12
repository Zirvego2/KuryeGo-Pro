import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import 'home_screen.dart';
import 'terms_acceptance_screen.dart';
import 'courier_application_screen.dart';

/// Login Ekranı
/// React Native Page_Login.js karşılığı
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _checkExistingLogin();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Mevcut login kontrolü
  Future<void> _checkExistingLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final courierId = prefs.getInt('courier_id');

    if (courierId != null && mounted) {
      // ⭐ Önce gizlilik ve konum onaylarını kontrol et (Google Play & Apple Store zorunlu)
      final termsAccepted = prefs.getBool('privacy_policy_accepted') ?? false;
      final locationAccepted = prefs.getBool('location_permission_accepted') ?? false;

      if (!termsAccepted || !locationAccepted) {
        print('⚠️ Kullanıcı politikaları onaylamamış - Onay ekranına yönlendiriliyor');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TermsAcceptanceScreen(
              courierId: courierId, // ⭐ Kurye ID'sini gönder
              onAccepted: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              },
            ),
          ),
        );
      } else {
        // Zaten giriş yapılmış ve onaylar verilmiş, ana sayfaya yönlendir
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  /// Login işlemi
  Future<void> _login() async {
    if (_phoneController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Kullanıcı adı ve şifre gerekli!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userData = await FirebaseService.loginCourier(
        _phoneController.text,
        _passwordController.text,
      );

      if (userData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('❌ Kullanıcı adı veya şifre hatalı')),
          );
        }
        return;
      }

      // Kullanıcı bilgilerini kaydet
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('courier_id', userData['s_id']);
      await prefs.setString('courier_name',
          '${userData['s_info']?['ss_name'] ?? ''} ${userData['s_info']?['ss_surname'] ?? ''}');
      await prefs.setInt('courier_bay', userData['s_bay'] ?? 0);

      // ⭐ KRİTİK: Konum izinlerini adım adım al
      print('🔐 Konum izinleri kontrol ediliyor...');
      
      // 1. Önce LocationService initialize et
      await LocationService.initialize();
      print('✅ LocationService initialized');
      
      // 2. İzinleri kontrol et ve iste
      final hasPermissions = await LocationService.checkAndRequestPermissions();
      print('📍 İzin durumu: $hasPermissions');

      if (!hasPermissions && mounted) {
        // İzin verilmedi - Kullanıcıyı uyar ve ayarlara yönlendir
        final goToSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ Konum İzni Gerekli'),
            content: const Text(
              'Arka planda konum takibi için "Her zaman izin ver" seçeneğini seçmeniz gerekiyor.\n\nAyarlar → Uygulamalar → ZirveGo → İzinler → Konum → Her zaman izin ver',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Ayarlara Git'),
              ),
            ],
          ),
        );

        if (goToSettings == true) {
          await LocationService.openAppSettings();
        }
      }

      // 3. 🔔 FCM Token yenile ve Firestore'a kaydet
      print('🔔 FCM Token yenileniyor ve kaydediliyor...');
      await NotificationService.refreshAndSaveToken();
      print('✅ FCM Token kaydedildi');

      // 4. Background location service başlat
      print('🚀 Background service başlatılıyor...');
      await LocationService.startService(userData['s_id']);
      print('✅ Background service başlatıldı');

      // 5. ⚡ Pil optimizasyonu uyarısı (Xiaomi, Oppo, Huawei için)
      await LocationService.checkBatteryOptimization();

      if (mounted) {
        // ⭐ Önce gizlilik ve konum onaylarını kontrol et (Google Play & Apple Store zorunlu)
        final termsAccepted = prefs.getBool('privacy_policy_accepted') ?? false;
        final locationAccepted = prefs.getBool('location_permission_accepted') ?? false;

        if (!termsAccepted || !locationAccepted) {
          print('⚠️ Kullanıcı politikaları onaylamamış - Onay ekranına yönlendiriliyor');
          
          // ⭐ Onay ekranına git, onay verilince geri dön ve HomeScreen'e yönlendir
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => TermsAcceptanceScreen(
                courierId: userData['s_id'], // ⭐ Kurye ID'sini gönder
                onAccepted: () {
                  // ⭐ Sadece geri dön (true döndür)
                  Navigator.of(context).pop(true);
                },
              ),
            ),
          );
          
          // ⭐ Onay verildiyse HomeScreen'e yönlendir
          if (result == true && mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Giriş başarılı!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          // Onaylar verilmiş, direkt ana sayfaya yönlendir
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Giriş başarılı!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        // ⚡ Xiaomi/Oppo kullanıcılarına uyarı
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('⚡ Önemli Uyarı'),
                content: const Text(
                  'Xiaomi, Oppo, Huawei veya benzeri telefonlarda:\n\n'
                  '1. Ayarlar → Pil → Uygulama pil tasarrufu\n'
                  '2. ZirveGo uygulamasını bulun\n'
                  '3. "Kısıtlama yok" seçeneğini seçin\n\n'
                  'Aksi takdirde arka planda konum gönderimi kesintiye uğrayabilir!',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Anladım'),
                  ),
                ],
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(0.1),
              Colors.blue.withOpacity(0.5),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo animasyonu
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: 1.0 + (_animationController.value * 0.1),
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.5),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.delivery_dining,
                            size: 100,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'ZirveGo',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),

                  const SizedBox(height: 10),

                  const Text(
                    'Kurye Uygulaması',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Kullanıcı adı
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.person_outline, color: Colors.blue),
                        hintText: 'Kullanıcı Adı',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Şifre
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.lock_outline, color: Colors.blue),
                        hintText: 'Şifre',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Giriş butonu
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.login, color: Colors.white),
                                SizedBox(width: 10),
                                Text(
                                  'Giriş Yap',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Kuryeci ol butonu
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CourierApplicationScreen(),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.blue, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 15),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pedal_bike, color: Colors.blue),
                        SizedBox(width: 10),
                        Text(
                          'Hemen Kurye Ol',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 50),

                  const Text(
                    '© 2025 Tüm hakları saklıdır.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

