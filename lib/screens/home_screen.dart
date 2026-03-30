import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';
import '../services/shift_service.dart';
import '../services/shift_log_service.dart';
import '../services/break_service.dart';
import '../services/route_service.dart';
import '../services/pool_order_service.dart';
import '../models/order_model.dart';
import '../widgets/modern_order_detail_sheet.dart';
import '../widgets/modern_header.dart';
import 'external_order_screen.dart';
import '../widgets/modern_order_card.dart';
import '../widgets/shift_menu_sheet.dart';
import '../widgets/route_add_order_popup.dart';
// import '../widgets/new_order_popup.dart'; // ⭐ Popup sistemi kaldırıldı - Küçük bildirim kullanılıyor
import '../main.dart';
import 'login_screen.dart';
import 'main_profile_screen.dart';
import 'pool_orders_screen.dart';

/// Ana Harita Ekranı
/// React Native Page_Home.js karşılığı
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  LatLng? _currentLocation; // İlk konum alınana kadar null
  final Set<Marker> _markers = {};
  List<OrderModel> _orders = [];
  List<OrderModel> _filteredOrders = [];
  int? _courierId;
  bool _isLoading = true;
  String _selectedFilter = 'all'; // all, waiting, onroad
  
  // ⭐ YENİ: Header bilgileri
  String _userName = '';
  int _packageCount = 0;
  int _todayDeliveredCount = 0; // Bugün teslim edilen paket sayısı
  String _statusText = 'MÜSAİT';
  int _courierStatus = 1; // 0=Çalışmıyor, 1=Müsait, 2=Meşgul, 3=Mola, 4=Kaza
  bool _isOnTheWay = false; // t_courier.s_on_the_way
  int _bayId = 1; // Bay/Şube ID (varsayılan)
  bool _poolPermissionEnabled = false;
  bool _poolAllowWhileBusy = false;
  String _poolBusinessScope = 'selected';
  List<int> _poolBusinessIds = [];
  bool _externalOrderEntryEnabled = false;
  
  // ⏰ Foreground location timer (debug/development için)
  Timer? _foregroundLocationTimer;
  int _foregroundTickCount = 0; // Tick sayacı
  bool _initialLocationTimedOut = false;
  
  
  // 🆕 Yeni sipariş bildirim kontrolü (Popup sistemi kaldırıldı)
  final Set<String> _processedOrderIds = {}; // Gösterilen bildirimleri takip et (stat değişince temizlenir)
  final Map<String, int> _orderStatusMap = {}; // ⭐ Sipariş ID -> Stat mapping (stat değişikliğini takip etmek için)
  Set<String> _previousOrderIds = {}; // ⭐ Önceki stream emit'teki sipariş ID'leri (değişiklik tespiti için)
  bool _isFirstLoad = true; // İlk yükleme mi? (mevcut siparişler için bildirim gösterilmesin)
  final AudioPlayer _notificationAudioPlayer = AudioPlayer(); // ⭐ Bildirim sesi için

  // 🗺️ Rota yönetimi
  RouteResult? _currentRoute; // Mevcut rota
  bool _isRouteActive = false; // Rota aktif mi?
  final Set<Polyline> _polylines = {}; // Rota çizgileri
  final Map<int, BitmapDescriptor> _numberedMarkerIcons = {}; // Numaralı pin ikonları (cache)
  bool _autoRouteEnabled = true; // Rota özelliği aktif mi? (Ayarlardan kontrol edilir)
  
  final ShiftLogService _shiftLogService = ShiftLogService(); // ⭐ Vardiya log servisi
  final BreakService _breakService = BreakService();
  
  // 🏪 Restoran sipariş yoğunluk haritası
  final Map<int, Map<String, dynamic>> _restaurants = {}; // Restoran bilgileri cache (restoran ID -> {s_id, s_name, s_loc})
  final Map<int, int> _restaurantOrderCounts = {}; // Restoran ID -> Sipariş sayısı
  final Map<String, BitmapDescriptor> _restaurantMarkerIcons = {}; // Restoran marker icon cache (renk_sayı -> icon)
  StreamSubscription<QuerySnapshot>? _restaurantOrdersSubscription; // Kuryeye atanmamış siparişler stream'i
  StreamSubscription? _ordersSubscription; // ⭐ Sipariş stream subscription
  StreamSubscription<bool>? _courierOnTheWaySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setAppRunningFlag(true); // Uygulama açık
    _initializeApp();
    
    // ⭐ Versiyon kontrolü - HomeScreen açıldığında kontrol et (context kesinlikle hazır)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Kısa bir gecikme ile versiyon kontrolü yap (ekran tamamen yüklensin)
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            ZirveGoApp.checkVersionAndShowDialog(context);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundLocationTimer?.cancel();
    _notificationAudioPlayer.dispose(); // ⭐ Audio player'ı temizle
    _restaurantOrdersSubscription?.cancel(); // ⭐ Restoran sipariş stream'ini iptal et
    _ordersSubscription?.cancel(); // ⭐ Sipariş stream'ini iptal et
    _courierOnTheWaySubscription?.cancel();
    
    // ⭐ Uygulama kapatılıyor flag'ini set et
    _setAppRunningFlag(false); // Uygulama kapandı
    print('🚫 Uygulama kapatılıyor - app_is_running = false');
    
    // ⭐ Eğer vardiya kapalıysa background service'i durdur
    if (_courierStatus == 0) {
      print('🛑 Uygulama kapanıyor - Vardiya kapalı olduğu için background service durduruluyor');
      LocationService.stopService();
    }
    
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBreakStateOnResume();
    }
  }

  /// App tekrar on plana geldiginde mola state'ini hizlica senkronla.
  Future<void> _refreshBreakStateOnResume() async {
    if (_courierId == null) return;
    try {
      final activeLog = await _shiftLogService.getActiveShift(_courierId!);
      if (activeLog?.status == 'BREAK') {
        // Kalan sure dolmussa BreakService fallback'i autoEndBreak'i tetikler.
        await _breakService.getCurrentBreakInfo(_courierId!);
      }
    } catch (e) {
      print('⚠️ Resume break refresh hatası: $e');
    }
  }

  /// 🏁 Uygulama çalışıyor flag'ini set et (Background service için)
  Future<void> _setAppRunningFlag(bool isRunning) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_is_running', isRunning);
      print('🏁 app_is_running = $isRunning');
    } catch (e) {
      print('❌ app_is_running set hatası: $e');
    }
  }

  Future<void> _initializeApp() async {
    final prefs = await SharedPreferences.getInstance();
    _courierId = prefs.getInt('courier_id');

    if (_courierId == null) {
      // Login yoksa login ekranına yönlendir
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
      return;
    }

    // ⭐ Rota özelliği ayarını yükle
    await _reloadRouteSetting();

    // ⭐ Kullanıcı bilgilerini yükle
    await _loadUserData();
    
    // ⭐ Restoran verilerini yükle
    await _loadRestaurants();

    // ⭐ Background location service'i kontrol et ve başlat
    await _ensureLocationServiceRunning();

    // s_on_the_way alanı belgede yoksa ilk açılışta siparişlerden üretip initialize et.
    await FirebaseService.refreshCourierOnTheWayFromOrders(_courierId!);

    // Konum takibini başlat (foreground - harita için)
    _startLocationTracking();
    unawaited(_ensureInitialLocationReady());
    
    // ⏰ Foreground location timer KAPALI - Background service zaten optimize edilmiş ve çalışıyor
    // _startForegroundLocationTimer(); // ❌ KAPALI: Gereksiz API istekleri oluşturuyordu

    // ⭐ Kurye statusunu dinle (real-time)
    print('👤 Kurye statüsü dinleniyor: Kurye ID = $_courierId');
    FirebaseService.watchCourierStatus(_courierId!).listen(
      (status) {
        print('👤 Kurye statüsü güncellendi: $status');
        if (mounted) {
          setState(() {
            _courierStatus = status;
            // Statü metni güncelle
            switch (status) {
              case 0:
                _statusText = 'ÇALIŞMIYOR';
                break;
              case 1:
                _statusText = 'MÜSAİT';
                break;
              case 2:
                _statusText = 'MEŞGUL';
                break;
              case 3:
                _statusText = 'MOLA';
                break;
              case 4:
                _statusText = 'KAZA';
                break;
              default:
                _statusText = 'MÜSAİT';
            }
            // ⭐ Vardiya çıkış bildirimi kaldırıldı - shiftTimeExpired artık yok
          });
          
        }
      },
      onError: (error) {
        print('❌ Kurye statü stream hatası: $error');
      },
    );

    // ⭐ Kurye yolda alanını dinle (s_on_the_way)
    _courierOnTheWaySubscription = FirebaseService.watchCourierOnTheWay(_courierId!).listen(
      (isOnTheWay) {
        if (!mounted) return;
        setState(() {
          _isOnTheWay = isOnTheWay;
        });
      },
      onError: (error) {
        print('❌ s_on_the_way stream hatası: $error');
      },
    );

    // Siparişleri dinle (real-time)
    print('🎧 Sipariş stream başlatılıyor: Kurye ID = $_courierId');
    _ordersSubscription = FirebaseService.watchOrders(_courierId!).listen(
      (orders) {
        // ⭐ Async işlemler için Future'ı unawaited ile kullan
        _handleOrdersUpdate(orders);
      },
      onError: (error) {
        print('❌ Sipariş stream hatası: $error');
      },
    );

    setState(() => _isLoading = false);
  }

  /// ⭐ Sipariş güncellemelerini işle (async)
  Future<void> _handleOrdersUpdate(List<Map<String, dynamic>> orders) async {
    print('📥 Sipariş stream güncellendi: ${orders.length} sipariş');
    
    if (mounted) {
      // ⭐ Önce mevcut sipariş ID'lerini topla
      final currentOrderIds = orders.map((o) => o['docId'] as String).toSet();
      
          // ⭐ İlk yükleme: Mevcut siparişleri işlendi olarak işaretle (popup açılmasın)
          if (_isFirstLoad) {
            print('📋 İlk yükleme - Mevcut siparişler işlendi olarak işaretleniyor: ${currentOrderIds.length} sipariş');
            
            // İlk yüklemede: Tüm siparişlerin stat'lerini kaydet
            for (final orderData in orders) {
              final orderDocId = orderData['docId'] as String;
              final orderStat = orderData['s_stat'] as int? ?? 0;
              
              // Stat mapping'i kaydet (stat değişikliğini takip etmek için)
              _orderStatusMap[orderDocId] = orderStat;
              
              // ⭐ İlk yüklemede: Sadece stat=1 (kabul edilmiş) olanları işlendi olarak işaretle
              // Stat=0 olanlar işlenmemiş olarak kalsın (kurye değişirse popup açılabilir)
              if (orderStat == 1) {
                _processedOrderIds.add(orderDocId);
                print('   ✅ Stat=1 sipariş (kabul edilmiş): $orderDocId - İşlendi olarak işaretlendi');
              } else if (orderStat == 0 || orderStat == 4) {
                // Stat=0 (hazır) veya stat=4 (hazırlanıyor) olanları işlenmemiş bırak (bildirim gösterilebilir)
                print('   📦 Stat=$orderStat sipariş (mevcut): $orderDocId - İşlenmemiş olarak bırakıldı (bildirim gösterilebilir)');
              } else {
                // Diğer stat'ler için işlendi olarak işaretle
                _processedOrderIds.add(orderDocId);
              }
            }
            
            _previousOrderIds = Set<String>.from(currentOrderIds); // Önceki ID'leri kaydet
            _isFirstLoad = false;
            print('   📊 İşlenmiş (toplam): ${_processedOrderIds.length}, Stat mapping: ${_orderStatusMap.length}');
          } else {
        // ⭐ Gerçekten yeni olan siparişleri bul (önceki emit'te yoktu)
        final newOrderIds = currentOrderIds.difference(_previousOrderIds);
        
        if (newOrderIds.isNotEmpty) {
          print('🆕 Gerçekten yeni siparişler tespit edildi: ${newOrderIds.length} adet');
        }
        
        // ⭐ Stat değişikliklerini kontrol et - Eğer stat=1'den stat=0'a düştüyse (kurye değişti), popup açılabilir
        for (final orderData in orders) {
          final orderDocId = orderData['docId'] as String;
          final orderStat = orderData['s_stat'] as int? ?? 0;
          final previousStat = _orderStatusMap[orderDocId];
          
          // Stat değişikliğini kaydet
          _orderStatusMap[orderDocId] = orderStat;
          
          // ⭐ Eğer stat=1'den stat=0 veya 4'e düştüyse (kurye değişti veya hazırlanmaya başladı), işlenmiş listesinden çıkar
          if (previousStat != null && previousStat == 1 && (orderStat == 0 || orderStat == 4)) {
            print('🔄 Stat değişikliği tespit edildi: $orderDocId - Stat: $previousStat → $orderStat (Kurye değişti veya hazırlanmaya başladı, bildirim gösterilebilir)');
            _processedOrderIds.remove(orderDocId); // İşlenmiş listesinden çıkar, bildirim gösterilebilir
          }
          
          // ⭐ Stat=4'ten stat=0'a geçiş: Hazırlanıyor → Hazır (özel bildirim göster)
          if (previousStat == 4 && orderStat == 0) {
            print('🔄 🔄 🔄 Stat değişikliği tespit edildi: $orderDocId - Stat: $previousStat → $orderStat (Hazırlanıyor → Hazır)');
            _processedOrderIds.remove(orderDocId); // İşlenmiş listesinden çıkar, bildirim gösterilebilir
            
            // ⭐ Özel bildirim göster: "Sipariş hazırlandı onaylayabilirsiniz"
            try {
              final order = OrderModel.fromFirestore(orderData, orderDocId);
              final businessName = order.sNameWork.isNotEmpty 
                  ? order.sNameWork 
                  : order.sRestaurantName ?? 'İşletme';
              
              print('✅ ✅ ✅ Sipariş hazırlandı bildirimi gösteriliyor: $businessName');
              _showOrderReadyNotification(businessName);
              
              // İşlendi olarak işaretle
              _processedOrderIds.add(orderDocId);
            } catch (e) {
              print('❌ Sipariş hazırlandı bildirimi hatası: $e');
            }
          }
          
          // ⭐ Stat=1 olanları işlenmiş olarak işaretle (ama kalıcı değil, stat değişirse tekrar bildirim gösterilebilir)
          if (orderStat == 1 && !_processedOrderIds.contains(orderDocId)) {
            _processedOrderIds.add(orderDocId);
            print('✅ Stat=1 (Kabul edilmiş) sipariş işlendi olarak işaretlendi: $orderDocId');
          }
        }
        
        // Önceki ID'leri güncelle
        _previousOrderIds = Set<String>.from(currentOrderIds);
        
        // ⭐ Yeni sipariş tespiti: Henüz gösterilmemiş ve stat=0 (hazır/alınacak) veya stat=4 (hazırlanıyor) olan siparişler
        for (final orderData in orders) {
          final orderDocId = orderData['docId'] as String;
          final orderStat = orderData['s_stat'] as int? ?? 0;
          
          // ⭐ Stat=0 (hazır/alınacak) veya stat=4 (hazırlanıyor) olan siparişler için bildirim göster
          // Kontroller:
          // 1. Stat=0 (hazır/alınacak) veya stat=4 (hazırlanıyor) olmalı - ZORUNLU
          // 2. Henüz işlenmemiş olmalı (_processedOrderIds'de yok) - ZORUNLU
          if ((orderStat == 0 || orderStat == 4) && !_processedOrderIds.contains(orderDocId)) {
            try {
              final newOrder = OrderModel.fromFirestore(orderData, orderDocId);
              final previousStat = _orderStatusMap[orderDocId];
              
              if (previousStat != null && previousStat == 1) {
                print('🔄 YENİ SİPARİŞ (Kurye değişti - Önceki stat=1, şimdi stat=$orderStat): $orderDocId');
              } else if (orderStat == 4) {
                print('🆕 🆕 🆕 HAZIRLANAN SİPARİŞ TESPİT EDİLDİ: $orderDocId (Stat=4)');
                print('   📌 Önceki stat: $previousStat');
                print('   📌 Şimdiki stat: $orderStat');
                print('   📌 CourierId: $_courierId');
              } else {
                print('🆕 YENİ SİPARİŞ TESPİT EDİLDİ: $orderDocId (Stat=0)');
              }
              
              final businessName = newOrder.sNameWork.isNotEmpty 
                  ? newOrder.sNameWork 
                  : newOrder.sRestaurantName ?? 'İşletme';
              
              print('   📦 İşletme: $businessName');
              print('   📊 Stat: $orderStat, Önceki stat: $previousStat, İşlenmiş: ${_processedOrderIds.contains(orderDocId)}');
              
              // ⭐ Rota aktifse ve rota özelliği açıksa: Yeni sipariş popup'ı göster
              // Değilse: Sadece bildirim göster
              if (_isRouteActive && _autoRouteEnabled && _currentRoute != null) {
                print('🗺️ [ROTA] Aktif rota var, yeni sipariş popup\'ı gösterilecek');
                _showRouteAddOrderPopup(newOrder);
              } else {
                // ⭐ Bildirimi göster ve sesi çal
                _showNewOrderNotification(businessName);
              }
              
              // İşlendi olarak işaretle
              _processedOrderIds.add(orderDocId);
            } catch (e) {
              print('❌ Yeni sipariş parse hatası: $e');
            }
          } else if ((orderStat == 0 || orderStat == 4) && _processedOrderIds.contains(orderDocId)) {
            // Debug: Stat=0 veya 4 ama işlenmiş - neden?
            final previousStat = _orderStatusMap[orderDocId];
            print('⚠️ Stat=$orderStat sipariş zaten işlenmiş (atlandı): $orderDocId (Önceki stat: $previousStat)');
          }
        }
      }
      
      // ⭐ Eski siparişleri temizle - Stream'den çıkan siparişleri hem işlenmiş listesinden hem stat mapping'den çıkar
      final removedFromProcessed = _processedOrderIds.length;
      final removedFromStatusMap = _orderStatusMap.length;
      
      // Stream'den çıkan siparişleri temizle
      _processedOrderIds.removeWhere((id) => !currentOrderIds.contains(id));
      _orderStatusMap.removeWhere((id, stat) => !currentOrderIds.contains(id));
      
      if (_processedOrderIds.length < removedFromProcessed || _orderStatusMap.length < removedFromStatusMap) {
        print('🧹 Eski siparişler temizlendi: İşlenmiş: ${removedFromProcessed - _processedOrderIds.length}, Stat mapping: ${removedFromStatusMap - _orderStatusMap.length}');
        print('   📊 İşlenmiş (toplam): ${_processedOrderIds.length}, Stat mapping: ${_orderStatusMap.length}');
      }
      
      if (mounted) {
        setState(() {
          _orders = orders.map((o) => OrderModel.fromFirestore(o, o['docId'])).toList();
          print('✅ UI güncellendi: ${_orders.length} sipariş görüntüleniyor');
          _applyFilter();
          _updatePackageCount(); // ⭐ Paket sayısını güncelle
        });
        
        // Marker'ları güncelle (async)
        _updateMarkers().then((_) {
          if (mounted) {
            setState(() {
              // Marker'lar güncellendi
            });
          }
        });
      }
    }
  }

  /// ⭐ Kullanıcı bilgilerini yükle (Login'de kaydedilmiş)
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userName = prefs.getString('courier_name') ?? 'Kurye';
    final bayId = prefs.getInt('courier_bay') ?? 1; // ⭐ Login'de 'courier_bay' olarak kaydedilmiş
    
    setState(() {
      _userName = userName;
      _bayId = bayId;
    });

    if (_courierId != null) {
      try {
        final poolConfig = await PoolOrderService.getCourierPoolConfig(_courierId!);
        final externalOrderEnabled = await FirebaseService.isExternalOrderEntryEnabledForBay(bayId);
        if (!mounted) return;
        setState(() {
          _poolPermissionEnabled = poolConfig['enabled'] == true;
          _poolAllowWhileBusy = poolConfig['allowWhileBusy'] == true;
          _poolBusinessScope = poolConfig['scope'] == 'all' ? 'all' : 'selected';
          _poolBusinessIds = (poolConfig['businessIds'] as List<dynamic>)
              .map((item) => int.tryParse(item.toString()))
              .whereType<int>()
              .toList();
          _externalOrderEntryEnabled = externalOrderEnabled;
        });
      } catch (e) {
        print('❌ Havuz yetki bilgisi alınamadı: $e');
      }
    }
    
    print('👤 Kullanıcı bilgileri yüklendi: $_userName (Bay: $_bayId)');
  }

  Future<void> _openPoolScreen() async {
    if (_courierId == null || !_poolPermissionEnabled) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PoolOrdersScreen(
          courierId: _courierId!,
          bayId: _bayId,
          courierStatus: _courierStatus,
          allowWhileBusy: _poolAllowWhileBusy,
          businessScope: _poolBusinessScope,
          businessIds: _poolBusinessIds,
        ),
      ),
    );
  }

  Future<void> _openExternalOrderEntry() async {
    if (!_externalOrderEntryEnabled) return;
    if (!mounted) return;

    if (_courierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Devam etmek için giriş yapın')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExternalOrderScreen(
          bayId: _bayId,
          courierId: _courierId!,
        ),
      ),
    );
  }

  /// 🏪 Bay'a bağlı restoranları yükle
  Future<void> _loadRestaurants() async {
    try {
      print('🏪 Restoranlar yükleniyor: Bay ID = $_bayId');
      
      final workQuery = await FirebaseFirestore.instance
          .collection('t_work')
          .where('s_bay', isEqualTo: _bayId)
          .get();

      _restaurants.clear();
      
      for (var doc in workQuery.docs) {
        final data = doc.data();
        final workId = data['s_id'] as int?;
        
        if (workId == null) continue;
        
        // Konum bilgisini al
        final sLoc = data['s_loc'];
        LatLng? location;
        
        if (sLoc is Map) {
          final ssLocation = sLoc['ss_location'];
          if (ssLocation is GeoPoint) {
            location = LatLng(ssLocation.latitude, ssLocation.longitude);
          }
        }
        
        // Konum varsa restoranı ekle
        if (location != null) {
          _restaurants[workId] = {
            's_id': workId,
            's_name': data['s_name'] ?? 'Restoran',
            'location': location,
          };
        }
      }
      
      print('✅ ${_restaurants.length} restoran yüklendi');
      
      // Sipariş sayılarını hesapla (mevcut siparişlerden)
      _calculateRestaurantOrderCounts();
      
      // Marker'ları güncelle
      if (mounted) {
        await _updateMarkers();
        setState(() {});
      }
    } catch (e) {
      print('❌ Restoranlar yüklenirken hata: $e');
    }
  }

  /// 📊 Restoran sipariş sayılarını hesapla (sadece kuryeye atanmamış siparişler)
  void _calculateRestaurantOrderCounts() {
    try {
      // Önceki stream'i iptal et
      _restaurantOrdersSubscription?.cancel();
      
      // Tüm siparişleri Firestore'dan dinle (sadece kuryeye atanmamış olanları saymak için)
      _restaurantOrdersSubscription = FirebaseFirestore.instance
          .collection('t_orders')
          .where('s_bay', isEqualTo: _bayId)
          .where('s_stat', whereIn: [0, 1, 4]) // Aktif siparişler
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        
        _restaurantOrderCounts.clear();
        
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final sCourier = data['s_courier'] as int? ?? 0;
          
          // ⭐ Sadece kuryeye atanmamış siparişleri say (s_courier == 0)
          if (sCourier == 0) {
            final restaurantId = data['s_work'] as int? ?? 0;
            if (restaurantId > 0 && _restaurants.containsKey(restaurantId)) {
              _restaurantOrderCounts[restaurantId] = (_restaurantOrderCounts[restaurantId] ?? 0) + 1;
            }
          }
        }
        
        print('✅ Sipariş sayıları hesaplandı: ${_restaurantOrderCounts.length} restoran (atanmamış siparişler)');
        
        // Marker'ları güncelle
        if (mounted) {
          _updateMarkers().then((_) {
            if (mounted) {
              setState(() {
                // Marker'lar güncellendi
              });
            }
          });
        }
      });
    } catch (e) {
      print('❌ Sipariş sayıları hesaplanırken hata: $e');
    }
  }

  /// 🔊 Yeni sipariş bildirim sesini çal
  Future<void> _playNotificationSound() async {
    try {
      print('🔊 Yeni sipariş bildirim sesi çalınıyor: definite.mp3');
      
      await _notificationAudioPlayer.stop();
      await _notificationAudioPlayer.setVolume(1.0);
      await _notificationAudioPlayer.setReleaseMode(ReleaseMode.release);
      
      await _notificationAudioPlayer.play(
        AssetSource('definite.mp3'),
        mode: PlayerMode.mediaPlayer,
        volume: 1.0,
      );
      
      print('✅ Ses çalma başarılı: definite.mp3 (root)');
    } catch (e) {
      print('❌ Ses çalma hatası (definite.mp3 root): $e');
      
      // Alternatif path dene
      try {
        print('🔄 Alternatif path deneniyor: sounds/definite.mp3');
        await _notificationAudioPlayer.stop();
        await _notificationAudioPlayer.setVolume(1.0);
        await _notificationAudioPlayer.setReleaseMode(ReleaseMode.release);
        await _notificationAudioPlayer.play(
          AssetSource('sounds/definite.mp3'),
          mode: PlayerMode.mediaPlayer,
          volume: 1.0,
        );
        print('✅ Alternatif path ile ses çalma başarılı: sounds/definite.mp3');
      } catch (e2) {
        print('❌ Alternatif path başarısız: $e2');
      }
    }
  }

  /// 📢 Sipariş hazırlandı bildirimi göster (stat=4'ten stat=0'a geçiş)
  void _showOrderReadyNotification(String businessName) {
    if (!mounted) return;
    
    // Ses çal
    _playNotificationSound();
    
    // Bildirimi göster
    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, -50 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade600, // ⭐ Yeşil renk (hazır)
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Sipariş Hazırlandı',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$businessName - Onaylayabilirsiniz',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    // 3 saniye sonra kaldır
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry?.remove();
    });
  }

  /// 📢 Üstte küçük bildirim göster (2 saniye) ve ses çal
  Future<void> _showNewOrderNotification(String businessName) async {
    if (!mounted) return;
    
    // Telefonu titreştir (sistem titreşimi - güçlü desen)
    try {
      if (await Vibration.hasVibrator() ?? false) {
        // Güçlü titreşim deseni: 800ms titreşim, 300ms bekleme, 800ms titreşim, 300ms bekleme, 800ms titreşim
        Vibration.vibrate(pattern: [0, 800, 300, 800, 300, 800]);
        print('📳 Telefon titreşimi tetiklendi (sistem titreşimi - güçlü desen)');
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
    
    // Ses çal
    _playNotificationSound();
    
    // Bildirimi göster
    final overlay = Overlay.of(context);
    OverlayEntry? overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, -50 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_active,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Yeni Sipariş Geldi',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          businessName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    // 2 saniye sonra otomatik kaldır
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry?.remove();
      overlayEntry = null;
    });
  }

  /// ✅ Yeni Siparişi Kabul Et
  Future<void> _acceptNewOrder(OrderModel order) async {
    if (_courierId == null) return;

    try {
      print('✅ Yeni sipariş kabul ediliyor: ${order.docId}');
      
      // Siparişi kabul et
      await FirebaseService.acceptOrder(order.docId);
      
      // Kurye durumunu meşgul yap
      await FirebaseService.updateCourierStatus(_courierId!, 2); // 2 = Meşgul
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sipariş başarıyla kabul edildi!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      print('✅ Sipariş kabul işlemi tamamlandı');
    } catch (e) {
      print('❌ Sipariş kabul hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ❌ Yeni Siparişi Reddet
  Future<void> _rejectNewOrder(OrderModel order) async {
    if (_courierId == null) return;

    try {
      print('❌ Yeni sipariş reddediliyor: ${order.docId}');
      
      // Siparişi reddet
      await FirebaseService.rejectOrder(order.docId, _courierId!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sipariş reddedildi'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      print('✅ Sipariş red işlemi tamamlandı');
    } catch (e) {
      print('❌ Sipariş red hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🕐 Vardiya Yönetim Menüsünü Göster
  void _showShiftDialog() {
    if (_courierId == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ShiftMenuSheet(
        courierId: _courierId!,
        bayId: _bayId,
        currentStatus: _courierStatus,
        onStatusChanged: (newStatus) {
            setState(() {
              _courierStatus = newStatus;
              
              // Durum metnini güncelle
            switch (newStatus) {
              case 0:
                _statusText = 'ÇALIŞMIYOR';
                break;
              case 1:
                _statusText = 'MÜSAİT';
                break;
              case 2:
                _statusText = 'MEŞGUL';
                break;
              case 3:
                _statusText = 'MOLADA';
                break;
              case 4:
                _statusText = 'KAZA';
                break;
            }
          });
        },
      ),
    );
  }

  /// ⭐ Paket sayılarını güncelle (TESLİM TARİHİNE GÖRE)
  Future<void> _updatePackageCount() async {
    try {
      // ⭐ DOĞRU: s_ddate (teslim tarihi) kullan
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      
      // Firestore'dan bugünkü teslim edilmiş siparişleri say (s_ddate ile)
      final deliveredToday = await FirebaseService.getDeliveredOrdersCountToday(
        _courierId!,
        startOfDay,
      );
      
      if (mounted) {
        setState(() {
          _packageCount = deliveredToday;
          _todayDeliveredCount = deliveredToday; // Header için
        });
      }
      
      print('📦 Bugün teslim edilen (s_ddate): $deliveredToday paket');
    } catch (e) {
      print('⚠️ Paket sayısı hesaplama hatası: $e');
      // Hata durumunda 0 göster
      if (mounted) {
        setState(() {
          _packageCount = 0;
        });
      }
    }
  }

  /// ⭐ Background location service'in çalıştığından emin ol
  Future<void> _ensureLocationServiceRunning() async {
    print('🔍 Vardiya ve konum servisi durumu kontrol ediliyor...');
    
    try {
      // ⭐ KONUM SERVİSİ KAPAL I MI KONTROL ET (Google Play & Apple Store zorunlu)
      final isLocationEnabled = await LocationService.isLocationServiceEnabled();
      if (!isLocationEnabled && mounted) {
        _showLocationDisabledWarning();
        return;
      }

      // ⭐ Kurye durumunu kontrol et
      final courierDoc = await FirebaseFirestore.instance
          .collection('t_courier')
          .where('s_id', isEqualTo: _courierId)
          .limit(1)
          .get();

      if (courierDoc.docs.isEmpty) {
        print('❌ Kurye bulunamadı!');
        return;
      }

      final courierStatus = courierDoc.docs.first.data()['s_stat'] ?? 0;
      print('👤 Kurye Durumu: $courierStatus');
      print('   0=Çalışmıyor, 1=Müsait, 2=Meşgul, 3=Mola, 4=Kaza');

      // ⭐ ÇALIŞMIYOR (0) İSE KONUM SERVİSİNİ BAŞLATMA!
      if (courierStatus == 0) {
        print('🚫 Vardiya kapalı - Konum servisi BAŞLATILMAYACAK');
        print('   ℹ️ Vardiya açıldığında konum servisi otomatik başlayacak');
        
        // Eğer çalışıyorsa durdur
        final service = FlutterBackgroundService();
        final isRunning = await service.isRunning();
        if (isRunning) {
          print('⚠️ Konum servisi çalışıyor ama vardiya kapalı - Durduruluyor...');
          LocationService.stopService();
          print('✅ Konum servisi durduruldu');
        }
        return;
      }

      // ⭐ VARDİYA AÇIK - KONUM SERVİSİNİ BAŞLAT
      print('✅ Vardiya açık - Konum servisi kontrol ediliyor...');
      
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();
      
      if (!isRunning) {
        print('📍 Background service çalışmıyor - Başlatılıyor...');
        await LocationService.startService(_courierId!);
        print('✅ Background service başlatıldı');
      } else {
        print('✅ Background service zaten çalışıyor');
      }
    } catch (e) {
      print('❌ Vardiya kontrol hatası: $e');
      // Hata durumunda güvenli tarafta kal - başlatma
    }
  }

  /// 📍 Konum Kapalı Uyarısı (Google Play & Apple Store zorunlu)
  void _showLocationDisabledWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '🔴 Konum Kapalı',
                style: TextStyle(fontSize: 20, color: Colors.red),
              ),
            ),
          ],
        ),
        content: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sipariş almak için konumunuzun açık olması gerekiyor.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Konum servisi kapalı. Lütfen aşağıdaki adımları takip edin:',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: 12),
            Text('1️⃣ Telefonunuzun konum ayarlarına gidin'),
            SizedBox(height: 8),
            Text('2️⃣ Konum servisini AÇIN'),
            SizedBox(height: 8),
            Text('3️⃣ Uygulamaya geri dönün'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              // Telefon ayarlarını aç
              await LocationService.openLocationSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Ayarlara Git'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }


  /// 📢 Üst sağda bildirim göster
  void _showTopRightNotification(String title, String message, Color color) {
    if (!mounted) return;
    
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 50,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(50 * (1 - value), 0),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // 3 saniye sonra kaldır
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }


  /// ⏰ Foreground location timer başlat (debug/development için)
  void _startForegroundLocationTimer() {
    print('⏰ Foreground location timer başlatılıyor (15 saniye interval)...');
    
    // İlk gönderimi hemen yap
    _sendLocationFromForeground();
    
    // Sonra her 15 saniyede bir tick
    _foregroundLocationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (timer) {
        _foregroundTickCount++;
        print('⏰ Foreground timer tick #$_foregroundTickCount (${DateTime.now()})');
        
        // ⭐ Duruma göre kontrol et
        if (_shouldSendLocationForeground()) {
          print('   ✅ Bu tick\'te konum gönderilecek');
          _sendLocationFromForeground();
        } else {
          print('   ⏭️ Bu tick atlandı (${_getStatusName(_courierStatus)})');
        }
      },
    );
    
    print('✅ Foreground timer başlatıldı');
  }

  /// ⭐ Foreground timer için konum gönderilmeli mi?
  bool _shouldSendLocationForeground() {
    // Vardiya kapalıysa hiç gönderme
    if (_courierStatus == 0) {
      return false;
    }

    // Duruma göre interval kontrolü
    switch (_courierStatus) {
      case 1: // Müsait - 15 saniyede bir (her tick)
      case 2: // Meşgul - 15 saniyede bir (her tick)
        return true; // Her tick gönder
        
      case 3: // Mola - 10 dakikada bir (40 tick × 15sn = 600sn)
      case 4: // Kaza - 10 dakikada bir (40 tick × 15sn = 600sn)
        return _foregroundTickCount % 40 == 0;
        
      default:
        return true; // Varsayılan 15 saniye
    }
  }

  /// 📡 Foreground'dan konum gönder
  Future<void> _sendLocationFromForeground() async {
    try {
      final position = await LocationService.getCurrentLocation();
      
      if (position == null) {
        print('⚠️ Foreground: Konum alınamadı');
        return;
      }

      print('📍 Foreground: Konum alındı (${position.latitude}, ${position.longitude})');
      print('   Vardiya Durumu: $_courierStatus (${_getStatusName(_courierStatus)})');
      
      // API'ye gönder
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse(
          'https://zirvego.app/api/servis?x=${position.latitude}&y=${position.longitude}&s_id=$_courierId&t=$timestamp');

      print('🌐 Foreground: API\'ye gönderiliyor...');
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        print('✅ Foreground: Konum gönderildi! Response: ${response.body}');
      } else {
        print('⚠️ Foreground: API hatası ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Foreground: Konum gönderme hatası: $e');
    }
  }

  /// Durum adını al (debug için)
  String _getStatusName(int status) {
    switch (status) {
      case 0: return 'ÇALIŞMIYOR';
      case 1: return 'MÜSAİT';
      case 2: return 'MEŞGUL';
      case 3: return 'MOLA';
      case 4: return 'KAZA';
      default: return 'BİLİNMİYOR';
    }
  }

  /// 🧪 DEBUG: Manuel konum gönderme testi
  Future<void> _testLocationSend() async {
    print('');
    print('🧪🧪🧪 MANUEL KONUM TEST BAŞLATILDI');
    print('================================================');
    
    try {
      // Mevcut konumu al
      final position = await LocationService.getCurrentLocation();
      
      if (position == null) {
        print('❌ Konum alınamadı!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Konum alınamadı! GPS açık mı kontrol edin.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      print('✅ Konum alındı: (${position.latitude}, ${position.longitude})');
      print('🌐 API\'ye gönderiliyor...');

      // API'ye gönder
      final url = Uri.parse(
          'https://zirvego.app/api/servis?x=${position.latitude}&y=${position.longitude}&s_id=$_courierId&t=${DateTime.now().millisecondsSinceEpoch}');
      
      print('📡 URL: $url');

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      print('📡 Response Code: ${response.statusCode}');
      print('📥 Response Body: ${response.body}');

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Test başarılı!\nKonum: (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ API Hatası: ${response.statusCode}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      print('================================================');
      print('');
    } catch (e, stackTrace) {
      print('❌ Test hatası: $e');
      print('Stack trace: $stackTrace');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Filtreyi uygula
  void _applyFilter() {
    switch (_selectedFilter) {
      case 'waiting':
        _filteredOrders = _orders.where((o) => o.sStat == 0 || o.sStat == 4).toList();
        break;
      case 'onroad':
        _filteredOrders = _orders.where((o) => o.sStat == 1).toList();
        break;
      default:
        _filteredOrders = _orders;
    }
  }

  /// Konum takibi başlat (foreground - harita için)
  bool _isFirstLocation = true; // İlk konum güncellemesi mi?
  DateTime? _lastMarkerUpdate; // Son marker güncelleme zamanı (throttle için)
  static const Duration _markerUpdateThrottle = Duration(seconds: 2); // Marker güncelleme throttle (2 saniye)
  
  void _startLocationTracking() {
    LocationService.getPositionStream().listen((position) {
      if (mounted) {
        final newLocation = LatLng(position.latitude, position.longitude);
        
        // ⭐ İlk konum alındığında haritayı göster ve merkeze al
        if (_isFirstLocation) {
          _isFirstLocation = false;
          setState(() {
            _currentLocation = newLocation;
            _initialLocationTimedOut = false;
          });
          
          // Widget rebuild olacak, harita oluşturulunca onMapCreated içinde merkeze alınacak
          // Ama harita zaten oluşturulmuşsa direkt merkeze al
          Future.microtask(() {
            if (mounted && _mapController != null && _currentLocation != null) {
              _mapController!.animateCamera(
                CameraUpdate.newLatLngZoom(_currentLocation!, 16.0),
              );
            }
          });
          
          _updateMarkers(); // İlk konumda marker'ları göster
          print('📍 [KONUM] İlk konum alındı ve harita güncellendi: (${newLocation.latitude.toStringAsFixed(6)}, ${newLocation.longitude.toStringAsFixed(6)})');
        } else {
          // ⭐ PERFORMANS: Sonraki konum güncellemelerinde setState YAPMA
          // myLocationEnabled: true olduğu için Google Maps otomatik olarak kurye konumunu gösterir (mavi nokta)
          // _currentLocation sadece ilk konum için gerekli, sonraki güncellemelerde widget rebuild gereksiz
          _currentLocation = newLocation; // Sadece değişkeni güncelle (setState yok - performans için)
          
          // Marker'ları throttle ile güncelle (performans için)
          final now = DateTime.now();
          if (_lastMarkerUpdate == null || now.difference(_lastMarkerUpdate!) >= _markerUpdateThrottle) {
            _lastMarkerUpdate = now;
            
            // ⭐ Marker'ları async güncelle ve sonra setState yap
            _updateMarkers().then((_) {
              if (mounted) {
                setState(() {
                  // Marker'lar güncellendi, widget'ı rebuild et
                });
              }
            });
          }
          // ⭐ Debug log'u kaldır veya throttle et (performans için)
          // print('📍 [KONUM] Konum güncellendi: (${newLocation.latitude.toStringAsFixed(6)}, ${newLocation.longitude.toStringAsFixed(6)})');
        }
      }
    }, onError: (error) {
      print('❌ [KONUM] Position stream hatası: $error');
      if (mounted && _currentLocation == null) {
        setState(() {
          _initialLocationTimedOut = true;
        });
      }
    });
  }

  Future<void> _ensureInitialLocationReady() async {
    await Future.delayed(const Duration(seconds: 6));
    if (!mounted || _currentLocation != null) return;

    print('⚠️ [KONUM] Stream ilk konumu vermedi, tek seferlik konum denemesi yapılıyor...');
    final position = await LocationService.getCurrentLocation().timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );

    if (!mounted || _currentLocation != null) return;

    if (position != null) {
      final newLocation = LatLng(position.latitude, position.longitude);
      setState(() {
        _isFirstLocation = false;
        _currentLocation = newLocation;
        _initialLocationTimedOut = false;
      });
      _updateMarkers();
      print('✅ [KONUM] Fallback ile ilk konum alındı');
      return;
    }

    setState(() {
      _initialLocationTimedOut = true;
    });
    print('❌ [KONUM] İlk konum alınamadı (stream + fallback başarısız)');
  }

  /// Marker'ları güncelle
  Future<void> _updateMarkers() async {
    _markers.clear();

    // Rota aktifse numaralı pinler göster
    if (_isRouteActive && _currentRoute != null) {
      for (var routePoint in _currentRoute!.routePoints) {
        final order = routePoint.order;
        if (order.ssLoc != null) {
          final icon = await _getNumberedMarkerIcon(routePoint.sequenceNumber);
          _markers.add(
            Marker(
              markerId: MarkerId('route_${order.sId}'),
              position: routePoint.deliveryLocation,
              icon: icon,
              infoWindow: InfoWindow(
                title: '${routePoint.sequenceNumber}. ${order.ssFullname}',
                snippet: order.ssAdres,
              ),
              onTap: () => _showOrderBottomSheet(order),
            ),
          );
        }
      }
    } else {
      // Normal marker'lar (rota yoksa)
      // 8. Düzeltme: Kurye marker'ı kaldırıldı (zaten mavi konum noktası var)

      // Sipariş marker'ları
      for (var order in _orders) {
        // 7. Düzeltme: Müşteri marker - Yeşil sepet rengi
        if (order.ssLoc != null) {
          _markers.add(
            Marker(
              markerId: MarkerId('customer_${order.sId}'),
              position: LatLng(
                order.ssLoc!['latitude'],
                order.ssLoc!['longitude'],
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              infoWindow: InfoWindow(
                title: '🛒 Müşteri: ${order.ssFullname}',
                snippet: order.ssAdres,
              ),
              onTap: () => _showOrderBottomSheet(order),
            ),
          );
        }

        // İşletme marker
        if (order.ssLocationWork != null) {
          _markers.add(
            Marker(
              markerId: MarkerId('business_${order.sId}'),
              position: LatLng(
                order.ssLocationWork!['latitude'],
                order.ssLocationWork!['longitude'],
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange),
              infoWindow: InfoWindow(
                title: 'İşletme: ${order.sRestaurantName ?? order.sNameWork}',
                snippet: order.sWorkAdres,
              ),
              onTap: () => _showOrderBottomSheet(order),
            ),
          );
        }
      }
      
      // 🏪 Restoran marker'ları (sipariş yoğunluk haritası)
      for (var entry in _restaurants.entries) {
        final restaurantId = entry.key;
        final restaurantData = entry.value;
        final location = restaurantData['location'] as LatLng;
        final restaurantName = restaurantData['s_name'] as String;
        final orderCount = _restaurantOrderCounts[restaurantId] ?? 0;
        
        // 0 paket olan restoranları gösterme
        if (orderCount == 0) continue;
        
        // Marker icon oluştur
        final color = _getRestaurantColor(orderCount);
        final icon = await _getRestaurantMarkerIcon(orderCount, color);
        
        _markers.add(
          Marker(
            markerId: MarkerId('restaurant_$restaurantId'),
            position: location,
            icon: icon,
            infoWindow: InfoWindow(
              title: '🏪 $restaurantName',
              snippet: '$orderCount paket',
            ),
          ),
        );
      }
    }
  }

  /// Sipariş detay modal aç (9. Düzeltme: Modern tasarım)
  void _showOrderBottomSheet(OrderModel order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ModernOrderDetailSheet(order: order),
    );
  }

  /// 🏪 Restoran marker icon oluştur (renk + sipariş sayısı)
  Future<BitmapDescriptor> _getRestaurantMarkerIcon(int orderCount, Color color) async {
    final cacheKey = '${color.value}_$orderCount';
    
    if (_restaurantMarkerIcons.containsKey(cacheKey)) {
      return _restaurantMarkerIcons[cacheKey]!;
    }

    // Canvas ile restoran marker icon oluştur
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = 90.0; // ⭐ Daha büyük daire

    // Renkli daire arka plan
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, paint);

    // Beyaz kenarlık
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0; // ⭐ Daha kalın kenarlık
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 2.0, borderPaint);

    // Sipariş sayısı metni
    final textPainter = TextPainter(
      text: TextSpan(
        text: orderCount.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36, // ⭐ Daha büyük font
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    // Picture'i image'e çevir
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());

    // Cache'e ekle
    _restaurantMarkerIcons[cacheKey] = icon;
    return icon;
  }

  /// Renk koduna göre Color döndür
  Color _getRestaurantColor(int orderCount) {
    if (orderCount == 0) {
      return Colors.grey; // 0 paket için gri (gösterilmeyecek)
    } else if (orderCount == 1) {
      return const Color(0xFFFACC15); // Sarı
    } else if (orderCount == 2) {
      return const Color(0xFFF97316); // Turuncu
    } else if (orderCount == 3) {
      return const Color(0xFFEF4444); // Kırmızı
    } else {
      return const Color(0xFF7C3AED); // Mor (4+)
    }
  }

  /// Numaralı pin ikonu oluştur (cache'lenmiş)
  Future<BitmapDescriptor> _getNumberedMarkerIcon(int number) async {
    if (_numberedMarkerIcons.containsKey(number)) {
      return _numberedMarkerIcons[number]!;
    }

    // Canvas ile numaralı pin oluştur
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = 80.0;

    // Mavi daire arka plan
    final paint = Paint()
      ..color = Colors.blue.shade600
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2, paint);

    // Beyaz kenarlık
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

    // Numara metni
    final textPainter = TextPainter(
      text: TextSpan(
        text: number.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final icon = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _numberedMarkerIcons[number] = icon;
    return icon;
  }

  /// Rota çizgisini güncelle (Gerçek yollar üzerinden)
  void _updateRoutePolyline() {
    _polylines.clear();

    if (_isRouteActive && _currentRoute != null && _currentRoute!.routePoints.isNotEmpty && _currentLocation != null) {
      List<LatLng> points;
      
      // Directions API'den gelen gerçek rota çizgisi varsa onu kullan
      if (_currentRoute!.routePolyline != null && _currentRoute!.routePolyline!.isNotEmpty) {
        points = _currentRoute!.routePolyline!;
      } else {
        // Fallback: Düz çizgi ile ara noktalar ekle (daha düzgün görünüm)
        points = <LatLng>[];
        LatLng previousPoint = _currentLocation!;
        points.add(previousPoint);
        
        for (var routePoint in _currentRoute!.routePoints) {
          // İki nokta arasına 10 ara nokta ekle (daha düzgün çizgi)
          final intermediatePoints = RouteService.interpolatePoints(
            previousPoint,
            routePoint.deliveryLocation,
            10,
          );
          // İlk noktayı atla (zaten previousPoint olarak eklendi)
          points.addAll(intermediatePoints.skip(1));
          previousPoint = routePoint.deliveryLocation;
        }
      }

      _polylines.add(
        Polyline(
          polylineId: const PolylineId('delivery_route'),
          points: points,
          color: Colors.blue.shade600,
          width: 5,
          patterns: [],
        ),
      );
    }
  }

  /// Dağıtıma çık - Rota oluştur
  Future<void> _startDeliveryRoute() async {
    print('🗺️ [ROTA] Dağıtıma çık başlatılıyor...');
    try {
      // Teslim alındı (s_stat=1) siparişleri filtrele
      final ordersToRoute = _orders.where((order) => order.sStat == 1).toList();

      if (ordersToRoute.isEmpty) {
        print('⚠️ [ROTA] Teslim alınmış sipariş bulunamadı');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Teslim alınmış sipariş bulunamadı'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (_currentLocation == null) {
        print('❌ [ROTA] Kurye konumu henüz alınamadı');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Konum alınamadı. Lütfen GPS\'i kontrol edin.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      print('🔄 [ROTA] ${ordersToRoute.length} sipariş için rota hesaplanıyor...');

      // Rota hesapla (Directions API ile gerçek yollar üzerinden)
      final route = await RouteService.calculateRoute(
        startLocation: _currentLocation!,
        orders: ordersToRoute,
      );

      print('✅ [ROTA] ${route.routePoints.length} durak, ${route.totalDistanceKm.toStringAsFixed(2)} km, ~${route.estimatedMinutes} dk');

      if (route.routePoints.isEmpty) {
        print('❌ [ROTA] Rota noktaları boş!');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Rota oluşturulamadı'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Numaralı pin ikonlarını önceden oluştur
      for (var routePoint in route.routePoints) {
        await _getNumberedMarkerIcon(routePoint.sequenceNumber);
      }

      setState(() {
        _currentRoute = route;
        _isRouteActive = true;
      });

      await _updateMarkers();
      _updateRoutePolyline();
      
      print('✅ [ROTA] Harita güncellendi ve rota aktif (kamera hareket ettirilmedi)');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Rota oluşturuldu: ${route.routePoints.length} durak'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ [ROTA] Hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Sipariş teslim edildiğinde rotayı yeniden hesapla
  Future<void> _recalculateRouteAfterDelivery() async {
    if (!_isRouteActive || _currentRoute == null) return;

    // Konum kontrolü
    if (_currentLocation == null) {
      print('⚠️ [ROTA] Konum alınamadı, rota yeniden hesaplanamıyor');
      return;
    }

    print('🔄 [ROTA] Teslim sonrası rota yeniden hesaplanıyor...');
    
    // Teslim alındı (s_stat=1) siparişleri filtrele
    final ordersToRoute = _orders.where((order) => order.sStat == 1).toList();

    if (ordersToRoute.isEmpty) {
      print('✅ [ROTA] Tüm siparişler teslim edildi, rota temizleniyor');
      // Rota yoksa rotayı temizle
      setState(() {
        _currentRoute = null;
        _isRouteActive = false;
      });
      await _updateMarkers();
      _updateRoutePolyline();
      return;
    }

      // Rota hesapla (Directions API ile gerçek yollar üzerinden)
      final route = await RouteService.calculateRoute(
        startLocation: _currentLocation!,
        orders: ordersToRoute,
      );

      if (route.routePoints.isEmpty) {
        print('⚠️ [ROTA] Yeni rota oluşturulamadı, rota temizleniyor');
        setState(() {
          _currentRoute = null;
          _isRouteActive = false;
        });
      } else {
        print('✅ [ROTA] Yeniden hesaplandı: ${route.routePoints.length} durak, ${route.totalDistanceKm.toStringAsFixed(2)} km');
        
        // Numaralı pin ikonlarını önceden oluştur
        for (var routePoint in route.routePoints) {
          await _getNumberedMarkerIcon(routePoint.sequenceNumber);
        }

        setState(() {
          _currentRoute = route;
        });
      }

      await _updateMarkers();
      _updateRoutePolyline();
  }

  /// Yeni sipariş rotaya ekleme popup'ı göster
  Future<void> _showRouteAddOrderPopup(OrderModel newOrder) async {
    // ⚙️ Rota özelliği kapalıysa popup gösterme
    if (!_autoRouteEnabled) {
      print('⚠️ [ROTA] Rota özelliği kapalı, yeni sipariş popup\'ı gösterilmeyecek');
      return;
    }
    
    if (!mounted || _currentRoute == null || _currentLocation == null) return;

    // Telefonu titreştir (sistem titreşimi - güçlü desen)
    try {
      if (await Vibration.hasVibrator() ?? false) {
        // Güçlü titreşim deseni: 800ms titreşim, 300ms bekleme, 800ms titreşim, 300ms bekleme, 800ms titreşim
        Vibration.vibrate(pattern: [0, 800, 300, 800, 300, 800]);
        print('📳 Telefon titreşimi tetiklendi (rota popup - sistem titreşimi)');
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

    // Ekstra mesafe ve süre hesapla
    final routeInfo = RouteService.calculateAdditionalRouteInfo(
      currentRoute: _currentRoute!,
      newOrder: newOrder,
      currentCourierLocation: _currentLocation!,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RouteAddOrderPopup(
        order: newOrder,
        extraDistanceKm: routeInfo['extraDistanceKm'] as double,
        extraMinutes: routeInfo['extraMinutes'] as int,
        estimatedSequence: routeInfo['estimatedSequence'] as int,
        onAccept: () {
          Navigator.pop(context);
          _addOrderToRoute(newOrder);
        },
        onReject: () {
          Navigator.pop(context);
          // Sipariş bekleyenler listesinde kalacak, mevcut rota bozulmayacak
        },
      ),
    );
  }

  /// Yeni siparişi rotaya ekle
  Future<void> _addOrderToRoute(OrderModel newOrder) async {
    if (!_isRouteActive || _currentRoute == null) return;

    try {
      // Siparişi kabul et (s_stat=1 yap)
      await FirebaseService.acceptOrder(newOrder.docId);
      await FirebaseService.updateOrderStatus(
        newOrder.docId,
        1,
        receivedTime: DateTime.now(),
      );

      // Rotayı yeniden hesapla (yeni sipariş dahil)
      await _recalculateRouteAfterDelivery();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sipariş rotaya eklendi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Sipariş rotaya ekleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Rota özelliği ayarını yeniden yükle
  Future<void> _reloadRouteSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _autoRouteEnabled = prefs.getBool('auto_route_enabled') ?? true; // Default: true
        });
      }
    } catch (e) {
      print('❌ Rota ayarı yüklenemedi: $e');
    }
  }

  /// Ana profil sayfasını aç
  Future<void> _openProfileMenu() async {
    // Profil sayfasından döndükten sonra ayarları yeniden yükle
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MainProfileScreen(
          courierId: _courierId!,
          courierName: _userName,
          bayId: _bayId,
        ),
      ),
    );
    // Ayarlardan döndükten sonra rota ayarını yeniden yükle
    await _reloadRouteSetting();
    
    // Eğer rota özelliği kapatıldıysa ve aktif rota varsa, rotayı temizle
    if (!_autoRouteEnabled && _isRouteActive) {
      setState(() {
        _currentRoute = null;
        _isRouteActive = false;
        _polylines.clear();
        _numberedMarkerIcons.clear();
      });
      await _updateMarkers();
      _updateRoutePolyline();
    }
  }

  /// Çıkış yap
  /// 📍 İlk açılış konum izni açıklama dialogu
  /// Apple Store & Google Play zorunlu özellik
  Future<void> _showFirstLaunchLocationDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false, // Kapatılamaz
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Colors.blue, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Konum İzni Gerekli',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ZirveGo, aşağıdaki amaçlar için konumunuza ihtiyaç duyar:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildPermissionReason(
                icon: Icons.delivery_dining,
                title: 'Sipariş Yönlendirme',
                description: 'Size yakın siparişleri otomatik olarak yönlendirmek için',
              ),
              const SizedBox(height: 12),
              _buildPermissionReason(
                icon: Icons.check_circle,
                title: 'Teslimat Doğrulama',
                description: 'Teslimatın doğru konumda yapıldığını doğrulamak için',
              ),
              const SizedBox(height: 12),
              _buildPermissionReason(
                icon: Icons.route,
                title: 'Rota Takibi',
                description: 'Katedilen mesafeyi hesaplamak ve kazancınızı doğru belirlemek için',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu uygulama, size sipariş yönlendirebilmek ve teslimatı doğrulamak için konumunuzu hem açık hem kapalı durumda toplar.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '🔒 Verileriniz güvenli bir şekilde saklanır ve üçüncü taraflarla paylaşılmaz.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }

  /// İzin nedeni widget'ı
  Widget _buildPermissionReason({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.blue, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Çıkış yapmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Background service durdur
      await LocationService.stopService();

      // Local storage temizle
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // ⭐ Harita (Tam Ekran) - İlk konum alınana kadar gösterilmez
          if (_currentLocation != null)
            GoogleMap(
              key: const ValueKey('main_map'), // ⭐ Widget key (rebuild optimizasyonu için)
              onMapCreated: (controller) {
                _mapController = controller;
                
                // ⭐ POI'leri gizle (Google Maps'in kendi işletmelerini kaldır)
                controller.setMapStyle('''
[
  {
    "featureType": "poi",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.business",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.attraction",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.place_of_worship",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.school",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "poi.sports_complex",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  }
]
''');
                
                // Harita oluşturulduğunda, eğer konum varsa merkeze al
                if (_currentLocation != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLngZoom(_currentLocation!, 16.0),
                  );
                }
              },
              initialCameraPosition: CameraPosition(
                target: _currentLocation!,
                zoom: 16,
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapType: MapType.normal,
              // ⭐ PERFORMANS: Camera hareketlerinde rebuild'i önle
              onCameraMoveStarted: () {
                // Camera hareket ederken hiçbir şey yapma (performans için)
              },
              onCameraMove: (position) {
                // Camera hareket ederken hiçbir şey yapma (performans için)
              },
            )
          else
            // Konum alınana kadar loading göster
            Container(
              color: Colors.grey[100],
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_initialLocationTimedOut) const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _initialLocationTimedOut
                          ? 'Konum alınamadı. GPS/Internet kontrol edin.'
                          : 'Konumunuz alınıyor...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (_initialLocationTimedOut) ...[
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _initialLocationTimedOut = false;
                            _isFirstLocation = true;
                          });
                          _startLocationTracking();
                          unawaited(_ensureInitialLocationReady());
                        },
                        child: const Text('Tekrar Dene'),
                      ),
                      TextButton(
                        onPressed: LocationService.openLocationSettings,
                        child: const Text('Konum Ayarlarini Ac'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // 🎨 Modern Header (Üstte - Sol/Sağ Butonlar Dahil)
          ModernHeader(
            userName: _userName,
            packageCount: _packageCount,
            statusText: _statusText,
            courierStatus: _courierStatus,
            isOnTheWay: _isOnTheWay,
            courierId: _courierId ?? 0, // ⭐ Vardiya bilgisi için
            onShiftPressed: _showShiftDialog, // ⭐ Vardiya menüsü
            onProfilePressed: _openProfileMenu, // ⭐ Profil menüsü
          ),
          
          // ⭐ Bildirimler (Bildirim butonunun eski yerinde - Sağ üstte)
          Positioned(
            top: 140, // ⭐ 80 → 140 (Daha aşağıya taşındı)
            right: 16,
            child: _buildNotificationPanel(),
          ),

          // 🗺️ Dağıtıma Çık Butonu ve Rota Bilgisi (Sol üstte)
          Positioned(
            top: 140,
            left: 16,
            child: _buildRouteControlPanel(),
          ),

          if (_poolPermissionEnabled)
            Positioned(
              top: 220,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _openPoolScreen,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, color: Color(0xFF1D4ED8)),
                          SizedBox(width: 6),
                          Text(
                            'Havuz',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (_externalOrderEntryEnabled)
            Positioned(
              top: _poolPermissionEnabled ? 280 : 220,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _openExternalOrderEntry,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_box_outlined, color: Color(0xFF047857)),
                          SizedBox(width: 6),
                          Text(
                            'Sistem Dışı',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 4. Düzeltme: Test konum butonu kaldırıldı

          // ⭐ Alt Sipariş Listesi (Horizontal Scroll)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 270,
              color: Colors.transparent,
              padding: const EdgeInsets.only(top: 20, bottom: 10),
              child: _filteredOrders.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 60, color: Colors.grey),
                          SizedBox(height: 10),
                          Text(
                            'Aktif sipariş yok',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        ListView.builder(
                          scrollDirection: Axis.horizontal, // ⭐ HORIZONTAL
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: _filteredOrders.length,
                          itemBuilder: (context, index) {
                            final order = _filteredOrders[index];
                            return ModernOrderCard(
                              order: order,
                              onTap: () => _showOrderBottomSheet(order),
                            );
                          },
                        ),
                        // ⭐ Sağa ok göstergesi (2'den fazla sipariş varsa)
                        if (_filteredOrders.length > 2)
                          Positioned(
                            right: 16,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Color(0xFF2196F3),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Statü rengi
  Color _getStatusColor(int stat) {
    switch (stat) {
      case 0:
        return Colors.green; // Hazır
      case 1:
        return Colors.blue; // Yolda
      case 2:
        return const Color(0xFF4CAF50); // Teslim Edildi (Yeşil)
      case 3:
        return Colors.red; // İptal
      case 4:
        return Colors.orange; // Hazırlanıyor
      default:
        return Colors.grey;
    }
  }

  /// Statü metni
  String _getStatusText(int stat) {
    switch (stat) {
      case 0:
        return 'HAZIR';
      case 1:
        return 'YOLDA';
      case 2:
        return 'TESLİM EDİLDİ';
      case 3:
        return 'İPTAL';
      case 4:
        return 'HAZIRLANIYOR';
      default:
        return 'BİLİNMİYOR';
    }
  }

  /// Filtre chip
  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _selectedFilter == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedFilter = value;
            _applyFilter();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black54,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ⭐ Bildirim Paneli (Onay bekleyen siparişler)
  Widget _buildNotificationPanel() {
    // Onay bekleyen siparişler
    final pendingOrders = _orders.where((order) => 
      order.sStat == 0 && 
      (order.sCourierAccepted == null || order.sCourierAccepted == false)
    ).toList();

    if (pendingOrders.isEmpty) {
      return const SizedBox.shrink(); // Bildirim yoksa gösterme
    }

    // ⭐ Yanıp sönme animasyonu (StatefulWidget olmadan basit opacity pulse)
    return Container(
        width: 240, // ⭐ 280 → 240 (Küçültüldü)
        constraints: const BoxConstraints(maxHeight: 160), // ⭐ 200 → 160
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12), // ⭐ 16 → 12
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header (⭐ Küçültüldü)
          Container(
            padding: const EdgeInsets.all(8), // ⭐ 12 → 8
            decoration: const BoxDecoration(
              color: Color(0xFFFFC107), // Sarı - Onay bekliyor
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12), // ⭐ 16 → 12
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active,
                  color: Colors.white,
                  size: 16, // ⭐ 20 → 16
                ),
                const SizedBox(width: 6), // ⭐ 8 → 6
                const Text(
                  'ONAY BEKLİYOR',
                  style: TextStyle(
                    fontSize: 11, // ⭐ 13 → 11
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3, // ⭐ 0.5 → 0.3
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), // ⭐ 8 → 6
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(6), // ⭐ 8 → 6
                  ),
                  child: Text(
                    '${pendingOrders.length}',
                    style: const TextStyle(
                      fontSize: 10, // ⭐ 12 → 10
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bildirim listesi
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemCount: pendingOrders.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final order = pendingOrders[index];
                return InkWell(
                  onTap: () => _showOrderBottomSheet(order),
                  borderRadius: BorderRadius.circular(6), // ⭐ 8 → 6
                  child: Padding(
                    padding: const EdgeInsets.all(6), // ⭐ 8 → 6
                    child: Row(
                      children: [
                        // Platform ikonu
                        Icon(
                          _getPlatformIcon(order.sOrderscr),
                          color: const Color(0xFFFFC107),
                          size: 16, // ⭐ 20 → 16
                        ),
                        const SizedBox(width: 6), // ⭐ 8 → 6
                        // Sipariş bilgisi
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order.sRestaurantName ?? order.sNameWork,
                                style: const TextStyle(
                                  fontSize: 10, // ⭐ 12 → 10
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF212121),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                order.ssFullname,
                                style: const TextStyle(
                                  fontSize: 9, // ⭐ 11 → 9
                                  color: Color(0xFF757575),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Tutar
                        Text(
                          '₺${order.ssPaycount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 10, // ⭐ 12 → 10
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPlatformIcon(int platformId) {
    switch (platformId) {
      case 1: return Icons.delivery_dining;
      case 2: return Icons.restaurant;
      case 3: return Icons.local_mall;
      case 4: return Icons.shopping_cart;
      default: return Icons.shopping_bag;
    }
  }

  /// 🗺️ Rota Kontrol Paneli (Dağıtıma Çık butonu ve rota bilgisi)
  Widget _buildRouteControlPanel() {
    // ⚙️ Rota özelliği kapalıysa hiçbir şey gösterme
    if (!_autoRouteEnabled) {
      return const SizedBox.shrink();
    }

    // Teslim alındı (s_stat=1) sipariş sayısı
    final ordersToRoute = _orders.where((order) => order.sStat == 1).length;

    if (!_isRouteActive) {
      // Rota yoksa - "Dağıtıma Çık" butonu
      if (ordersToRoute == 0) {
        return const SizedBox.shrink(); // Teslim alınmış sipariş yoksa gösterme
      }

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _startDeliveryRoute,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.directions,
                      color: Colors.blue.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Dağıtıma Çık',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF212121),
                        ),
                      ),
                      Text(
                        '$ordersToRoute sipariş',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      // Rota aktifse - Rota bilgisi göster
      if (_currentRoute == null || _currentRoute!.routePoints.isEmpty) {
        return const SizedBox.shrink();
      }

      return Container(
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.route,
                      color: Colors.blue.shade600,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Aktif Rota',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF212121),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      setState(() {
                        _currentRoute = null;
                        _isRouteActive = false;
                      });
                      _updateMarkers();
                      _updateRoutePolyline();
                    },
                    tooltip: 'Rotayı Kapat',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Rota bilgileri
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${_currentRoute!.routePoints.length} durak',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.straighten, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${_currentRoute!.totalDistanceKm.toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '~${_currentRoute!.estimatedMinutes} dk',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }


  /// Sipariş kartı
  Widget _buildOrderCard(OrderModel order) {
    // Platform ikonu
    IconData platformIcon;
    String platformName;

    switch (order.sOrderscr) {
      case 1:
        platformIcon = Icons.delivery_dining;
        platformName = 'Getir';
        break;
      case 2:
        platformIcon = Icons.restaurant;
        platformName = 'YemekSepeti';
        break;
      case 3:
        platformIcon = Icons.local_mall;
        platformName = 'Trendyol';
        break;
      case 4:
        platformIcon = Icons.shopping_cart;
        platformName = 'Migros';
        break;
      default:
        platformIcon = Icons.shopping_bag;
        platformName = 'Diğer';
    }

    // ⭐ Durum bazlı renk (Platform rengi YOK)
    final isWaitingForApproval = order.sStat == 0 && 
        (order.sCourierAccepted == null || order.sCourierAccepted == false);
    final isApproved = order.sStat == 0 && order.sCourierAccepted == true;
    final isOnTheWay = order.sStat == 1;

    Color statusColor;
    if (isWaitingForApproval) {
      statusColor = const Color(0xFFFFC107); // Onay bekliyor - SARI
    } else if (isApproved) {
      statusColor = const Color(0xFF4CAF50); // Onaylandı - YEŞİL
    } else if (isOnTheWay) {
      statusColor = const Color(0xFF2196F3); // Yolda - MAVİ
    } else {
      statusColor = const Color(0xFF757575); // Diğer durumlar - GRİ
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showOrderBottomSheet(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Platform ikonu
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(platformIcon, color: statusColor, size: 30),
              ),

              const SizedBox(width: 12),

              // Sipariş bilgileri
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.sRestaurantName ?? order.sNameWork,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: statusColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor(order.sStat),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _getStatusText(order.sStat),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.ssFullname,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      // ⭐ s_stat=0 veya 4 ise KM gösterme
                      order.sStat == 0 || order.sStat == 4
                          ? '₺${order.ssPaycount.toStringAsFixed(2)}'
                          : '${order.sDinstance} km • ₺${order.ssPaycount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              // Ok ikonu
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

