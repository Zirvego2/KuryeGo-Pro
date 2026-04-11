import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'statistics_screen.dart';
import 'finance_screen.dart';
import 'reports_screen.dart';
import 'profile_screen.dart';
import '../services/firebase_service.dart';
import '../utils/restaurant_pricing_fee.dart';
import '../utils/business_day_bounds.dart';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// 📱 Ana Profil Ekranı (3 Tab)
class MainProfileScreen extends StatefulWidget {
  final int courierId;
  final String courierName;
  final int bayId;

  const MainProfileScreen({
    super.key,
    required this.courierId,
    required this.courierName,
    required this.bayId,
  });

  @override
  State<MainProfileScreen> createState() => _MainProfileScreenState();
}

class _MainProfileScreenState extends State<MainProfileScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _statsBorderAnim;
  
  // İstatistikler
  int _todayDeliveries = 0;
  double _todayEarnings = 0.0;
  double _todayDistance = 0.0;
  double _todayExtraKm = 0.0; // ⭐ EKSTRA KM
  String _shiftTime = '00:00 - 23:59';
  bool _isLoadingStats = true;
  int _resetHour = 0; // Günlük istatistik sıfırlama saati (0 = gece yarısı)

  /// [t_courier.s_photo_url]
  String? _photoUrl;
  bool _uploadingPhoto = false;

  static const double _avatarSize = 64;
  static const double _avatarRadius = 17;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // ⭐ 3 → 4 (Raporlar eklendi)
    _statsBorderAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _loadProfilePhoto();
    _initResetHourThenLoad();
  }

  Future<void> _loadProfilePhoto() async {
    final url = await FirebaseService.getCourierPhotoUrl(widget.courierId);
    if (mounted) setState(() => _photoUrl = url);
  }

  Future<void> _showPhotoSourceSheet() async {
    if (_uploadingPhoto) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload();
              },
            ),
            if (_photoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Fotoğrafı kaldır',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Profil fotoğrafı yalnızca galeriden (kamera izni yok — Android sistem metninde video geçmesin).
  /// Android 13+: fotoğraflar (READ_MEDIA_IMAGES); daha eski: depolama — iOS: fotoğraflar.
  Future<bool> _ensureGalleryPermission() async {
    Permission perm;
    var deniedTitle = 'Galeri izni';
    var deniedMessage =
        'Profil fotoğrafı seçmek için fotoğraflarınıza erişim gerekir. Ayarlardan izin verebilirsiniz.';

    if (Platform.isIOS) {
      perm = Permission.photos;
    } else if (Platform.isAndroid) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk >= 33) {
        perm = Permission.photos;
        deniedTitle = 'Fotoğraflar izni';
        deniedMessage =
            'Profil fotoğrafı için galerinizdeki fotoğraflara erişim gerekir. Ayarlardan izin verebilirsiniz.';
      } else {
        perm = Permission.storage;
        deniedTitle = 'Depolama izni';
        deniedMessage =
            'Profil fotoğrafı seçmek için galeri dosyalarına erişim gerekir. Ayarlardan izin verebilirsiniz.';
      }
    } else {
      perm = Permission.photos;
    }

    var status = await perm.status;
    if (!status.isGranted) {
      status = await perm.request();
    }
    if (status.isGranted ||
        status == PermissionStatus.limited) {
      return true;
    }
    if (!mounted) return false;
    await _showPermissionSettingsDialog(
      title: deniedTitle,
      message: deniedMessage,
    );
    return false;
  }

  Future<void> _showPermissionSettingsDialog({
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('Ayarlara git'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    if (_uploadingPhoto) return;

    final ok = await _ensureGalleryPermission();
    if (!ok || !mounted) return;

    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    try {
      final url =
          await FirebaseService.uploadCourierProfilePhoto(widget.courierId, file);
      if (mounted) setState(() => _photoUrl = url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil fotoğrafı güncellendi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf yüklenemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_uploadingPhoto) return;
    setState(() => _uploadingPhoto = true);
    try {
      await FirebaseService.clearCourierProfilePhoto(widget.courierId);
      if (mounted) setState(() => _photoUrl = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil fotoğrafı kaldırıldı')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaldırılamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _initResetHourThenLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt('daily_reset_hour') ?? 0;
    if (mounted) setState(() => _resetHour = hour);
    _loadDailyStats();
  }

  @override
  void dispose() {
    _statsBorderAnim.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Vardiya saatini al
  Future<String> _getShiftTime() async {
    try {
      // Kurye bilgilerini al
      final courierQuery = await FirebaseFirestore.instance
          .collection('t_courier')
          .where('s_id', isEqualTo: widget.courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) return '00:00 - 23:59';

      final courierData = courierQuery.docs.first.data();
      final tShift = courierData['t_shift'];
      final courierBayId = courierData['s_bay'];

      if (tShift == null || courierBayId == null) return '00:00 - 23:59';

      // t_shift'i int'e çevir
      int shiftId;
      if (tShift is String) {
        shiftId = int.tryParse(tShift) ?? 0;
      } else if (tShift is int) {
        shiftId = tShift;
      } else {
        return '00:00 - 23:59';
      }

      // Vardiya bilgilerini al
      final shiftQuery = await FirebaseFirestore.instance
          .collection('t_shift')
          .where('s_id', isEqualTo: shiftId)
          .where('s_bay', isEqualTo: courierBayId)
          .limit(1)
          .get();

      if (shiftQuery.docs.isEmpty) return '00:00 - 23:59';

      final shiftData = shiftQuery.docs.first.data();
      final sShifts = shiftData['s_shifts'];

      if (sShifts == null) return '00:00 - 23:59';

      // Bugünün gününü al
      final weekdayMap = {
        1: 'ss_pazartesi',
        2: 'ss_sali',
        3: 'ss_carsamba',
        4: 'ss_persembe',
        5: 'ss_cuma',
        6: 'ss_cumartesi',
        7: 'ss_pazar',
      };

      final today = DateTime.now().weekday;
      final todayKey = weekdayMap[today];

      if (todayKey == null) return '00:00 - 23:59';

      final todayShift = sShifts[todayKey];
      if (todayShift is List && todayShift.length >= 2) {
        final startTime = todayShift[0]?.toString() ?? '00:00';
        final endTime = todayShift[1]?.toString() ?? '23:59';
        return '$startTime - $endTime';
      }

      return '00:00 - 23:59';
    } catch (e) {
      print('❌ Vardiya saati yükleme hatası: $e');
      return '00:00 - 23:59';
    }
  }

  /// ⭐ t_courier.s_pricing VEYA (bayi ayarında) t_restaurant_pricing + web formülü
  /// Index: s_courier + s_stat + s_ddate
  Future<void> _loadDailyStats() async {
    try {
      final now = DateTime.now();
      final dayBounds = getBusinessDayBounds(now, _resetHour);
      final todayStart = dayBounds.start;
      final todayEnd = dayBounds.end;

      print('📊 Günlük istatistik sorgusu başlatılıyor...');
      print('   Kurye ID: ${widget.courierId}');
      print('   İş günü [start, end): $todayStart → $todayEnd');

      final restaurantMode =
          await FirebaseService.isRestaurantPricingEnabled(widget.bayId);

      Map<String, dynamic>? courierPricing;
      Map<int, RestaurantWorkPricing> restaurantPricingMap = {};

      if (restaurantMode) {
        print('   🏪 Restoran bazlı ücretlendirme: AÇIK');
        restaurantPricingMap = await FirebaseService.getActiveRestaurantPricingByCourier(
          widget.bayId,
          widget.courierId,
        );
      } else {
        courierPricing = await FirebaseService.getCourierPricingFromCourier(widget.courierId);
        if (courierPricing == null) {
          print('❌ Kurye ücretlendirme bilgisi yüklenemedi!');
          setState(() => _isLoadingStats = false);
          return;
        }

        final fixedFee = courierPricing['s_fixed_fee'] as double;
        final minKm = courierPricing['s_min_km'] as double;
        final perKmFee = courierPricing['s_per_km_fee'] as double;

        print('   ✅ Ücretlendirme bilgisi (s_pricing):');
        print('      Sabit Ücret: ${fixedFee.toStringAsFixed(2)}₺');
        print('      Minimum KM: ${minKm.toStringAsFixed(2)} km');
        print('      KM Başı Ücret: ${perKmFee.toStringAsFixed(2)}₺/km');
      }

      // ⭐ 2. Bu iş günündeki teslimler: [todayStart, todayEnd) — üst sınır yoksa yarın/sonrası da sayılırdı
      final todayQueryByDdate = await FirebaseFirestore.instance
          .collection('t_orders')
          .where('s_courier', isEqualTo: widget.courierId)
          .where('s_stat', isEqualTo: 2)
          .where('s_ddate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('s_ddate', isLessThan: Timestamp.fromDate(todayEnd))
          .get();

      print('   📦 Bugün teslim edilen sipariş: ${todayQueryByDdate.docs.length}');

      int deliveries = todayQueryByDdate.docs.length;
      double earnings = 0.0;
      double totalDistance = 0.0;
      double totalExtraKm = 0.0;

      print('   💰 Kazanç hesaplaması başlatılıyor...');

      int orderIndex = 0;
      for (var doc in todayQueryByDdate.docs) {
        orderIndex++;
        final data = doc.data();
        final orderId = data['s_pid'] ?? data['s_id']?.toString() ?? 'N/A';

        print('      🔹 Sipariş #$orderIndex (ID: $orderId):');

        final distance = parseOrderDistanceKm(data);
        print('         Mesafe: ${distance.toStringAsFixed(2)} km');

        if (restaurantMode) {
          final workId = parseWorkId(data['s_work']);
          final rp = workId != null ? restaurantPricingMap[workId] : null;
          if (rp == null) {
            final fallback = parsePayCurPacketFromOrder(data);
            print('         ℹ️ Restoran fiyatı yok → payCurPacket: $fallback₺');
            earnings += fallback;
          } else {
            final result = calculateRestaurantPricingFee(rp, distance);
            earnings += result.totalEarnings;
            totalExtraKm += result.extraKm;
            print(
                '         💵 Restoran bazlı toplam: ${result.totalEarnings.toStringAsFixed(2)}₺ (ekstra km: ${result.extraKm.toStringAsFixed(2)})');
          }
        } else {
          final fixedFee = courierPricing!['s_fixed_fee'] as double;
          final minKm = courierPricing['s_min_km'] as double;
          final perKmFee = courierPricing['s_per_km_fee'] as double;

          double orderEarnings = fixedFee;
          double extraKm = 0.0;

          if (distance > 0 && minKm > 0 && distance > minKm) {
            extraKm = distance - minKm;
            final extraKmEarnings = extraKm * perKmFee;
            orderEarnings += extraKmEarnings;

            print(
                '         ✅ EKSTRA KM: ${extraKm.toStringAsFixed(2)} km (${distance.toStringAsFixed(2)} - ${minKm.toStringAsFixed(2)})');
            print(
                '         ✅ Ekstra Ücret: ${extraKm.toStringAsFixed(2)} × ${perKmFee.toStringAsFixed(2)}₺ = ${extraKmEarnings.toStringAsFixed(2)}₺');
          } else if (minKm == 0) {
            print('         ⚠️ MinKM tanımlı değil!');
          } else {
            print(
                '         ℹ️ Mesafe MinKM içinde (${distance.toStringAsFixed(2)} ≤ ${minKm.toStringAsFixed(2)} km) - Sadece sabit ücret');
          }

          print(
              '         💵 TOPLAM Kazanç: ${orderEarnings.toStringAsFixed(2)}₺ (Sabit: ${fixedFee.toStringAsFixed(2)}₺ + Ekstra: ${(orderEarnings - fixedFee).toStringAsFixed(2)}₺)');

          earnings += orderEarnings;
          totalExtraKm += extraKm;
        }

        totalDistance += distance;
      }
      
      print('   ════════════════════════════════════');
      print('   📊 GENEL TOPLAM:');
      print('      📦 Sipariş: $deliveries');
      print('      💰 Kazanç: ${earnings.toStringAsFixed(2)}₺');
      print('      🛣️ Toplam Mesafe: ${totalDistance.toStringAsFixed(1)} km');
      print('      ⚡ EKSTRA KM: ${totalExtraKm.toStringAsFixed(1)} km');
      print('   ════════════════════════════════════');

      // Vardiya saatini al
      String shiftTime = await _getShiftTime();

      print('   ✅ İstatistikler hazır:');
      print('      📦 Paket: $deliveries');
      print('      💰 Kazanç: ₺${earnings.toStringAsFixed(2)}');
      print('      🛣️ Toplam Mesafe: ${totalDistance.toStringAsFixed(1)} km');
      print('      ⚡ EKSTRA KM: ${totalExtraKm.toStringAsFixed(1)} km');
      print('      ⏰ Vardiya: $shiftTime');

      setState(() {
        _todayDeliveries = deliveries;
        _todayEarnings = earnings;
        _todayDistance = totalDistance;
        _todayExtraKm = totalExtraKm; // ⭐ EKSTRA KM
        _shiftTime = shiftTime;
        _isLoadingStats = false;
      });

      print('   🎨 UI güncellendi!');
    } catch (e) {
      print('❌ Günlük istatistik yükleme hatası: $e');
      print('   Stack trace: ${StackTrace.current}');
      setState(() => _isLoadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 46,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profil',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Profil kartı
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Column(
              children: [
                // Avatar solda; isim sağdaki alanda (Expanded) yatay/dikey ortalı
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Sabit boyut: alttaki küçük ikon Stack yüksekliğini şişirmesin; isim dikeyde foto ile ortalansın
                    SizedBox(
                      width: _avatarSize,
                      height: _avatarSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _uploadingPhoto
                                ? null
                                : _showPhotoSourceSheet,
                            borderRadius:
                                BorderRadius.circular(_avatarRadius),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(_avatarRadius),
                              child: _photoUrl != null
                                  ? Image.network(
                                      _photoUrl!,
                                      width: _avatarSize,
                                      height: _avatarSize,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (context, child,
                                          loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return Container(
                                          width: _avatarSize,
                                          height: _avatarSize,
                                          color: const Color(0xFF2196F3),
                                          child: const Center(
                                            child: SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                      errorBuilder: (_, __, ___) =>
                                          Container(
                                        width: _avatarSize,
                                        height: _avatarSize,
                                        color: const Color(0xFF2196F3),
                                        child: const Icon(Icons.person,
                                            color: Colors.white, size: 30),
                                      ),
                                    )
                                  : Container(
                                      width: _avatarSize,
                                      height: _avatarSize,
                                      color: const Color(0xFF2196F3),
                                      child: const Icon(Icons.person,
                                          color: Colors.white, size: 30),
                                    ),
                            ),
                          ),
                        ),
                        if (_uploadingPhoto)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius:
                                    BorderRadius.circular(_avatarRadius),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Material(
                            color: Colors.white,
                            elevation: 1,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _uploadingPhoto
                                  ? null
                                  : _showPhotoSourceSheet,
                              child: const Padding(
                                padding: EdgeInsets.all(5),
                                child: Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 15,
                                  color: Color(0xFF2196F3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: _avatarSize,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.courierName,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // İstatistikler (Günlük) — mavi/kırmızı tonlarda dönen gradient kenarlık
                AnimatedBuilder(
                  animation: _statsBorderAnim,
                  builder: (context, child) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: SweepGradient(
                          colors: const [
                            Color(0xFF2196F3),
                            Color(0xFFFF6B6B),
                            Color(0xFF42A5F5),
                            Color(0xFFE53935),
                            Color(0xFF2196F3),
                          ],
                          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                          transform: GradientRotation(
                            _statsBorderAnim.value * 2 * pi,
                          ),
                        ),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: _isLoadingStats
                      ? const SizedBox(
                          height: 44,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(
                              _todayDeliveries.toString(),
                              'Paket',
                              Icons.local_shipping,
                            ),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.grey[300],
                            ),
                            _buildStatItem(
                              '₺${_todayEarnings.toStringAsFixed(2)}',
                              'Kazanç',
                              Icons.account_balance_wallet,
                            ),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.grey[300],
                            ),
                            _buildStatItem(
                              _todayExtraKm.toStringAsFixed(2),
                              'Ekstra KM',
                              Icons.local_fire_department, // ⭐ Farklı icon
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),

          // Tab bar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              tabAlignment: TabAlignment.fill,
              labelPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              indicatorColor: const Color(0xFF2196F3),
              indicatorWeight: 2.5,
              labelColor: const Color(0xFF2196F3),
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.assessment, size: 18), text: 'Paketler'),
                Tab(icon: Icon(Icons.account_balance_wallet, size: 18), text: 'Kazançlarım'),
                Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'Raporlar'),
                Tab(icon: Icon(Icons.settings, size: 18), text: 'Ayarlar'),
              ],
            ),
          ),

          // Tab view
          Expanded(
            child: Container(
              color: const Color(0xFFF5F5F5),
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 1️⃣ İstatistikler & Performans
                  StatisticsScreen(
                    courierId: widget.courierId,
                    courierName: widget.courierName,
                  ),

                  // 2️⃣ Finans & Kazançlarım
                  FinanceScreen(
                    courierId: widget.courierId,
                    courierName: widget.courierName,
                    bayId: widget.bayId, // ⭐ Bay ID eklendi
                  ),

                  // 3️⃣ Raporlar
                  ReportsScreen(
                    courierId: widget.courierId,
                    courierName: widget.courierName,
                  ),

                  // 4️⃣ Profil & Ayarlar
                  ProfileScreen(
                    courierId: widget.courierId,
                    courierName: widget.courierName,
                    bayId: widget.bayId,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// İstatistik item widget
  Widget _buildStatItem(String value, String label, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}


