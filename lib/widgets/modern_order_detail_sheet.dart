import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order_model.dart';
import '../services/firebase_service.dart';
import '../services/platform_api_service.dart';
import '../services/sms_service.dart';
import '../services/javipos_api_service.dart';
import '../services/courier_cash_transaction_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 🎨 Modern & Kurumsal Sipariş Detay Sayfası (9. Düzeltme)
class ModernOrderDetailSheet extends StatefulWidget {
  final OrderModel order;

  const ModernOrderDetailSheet({super.key, required this.order});

  @override
  State<ModernOrderDetailSheet> createState() => _ModernOrderDetailSheetState();
}

class _ModernOrderDetailSheetState extends State<ModernOrderDetailSheet> {
  bool _isProcessing = false;
  Timer? _countdownTimer;
  int? _remainingTime;
  Timer? _buttonCountdownTimer; // ⭐ Buton countdown için
  
  // ⭐ Restoran bilgileri (t_work'ten çekilecek)
  String? _restaurantName;
  String? _restaurantAddress;
  String? _restaurantPhone;
  Map<String, dynamic>? _restaurantLocation;
  bool _isLoadingRestaurant = true;

  // ⭐ Kurye sipariş red etme ayarı (t_bay.s_settings'ten çekilecek)
  bool? _courierOrderRejectEnabled;
  bool? _orderAddressVisibleAfterOrder;
  bool _isLoadingRejectSetting = true;

  @override
  void initState() {
    super.initState();
    _startCountdownIfNeeded();
    _loadRestaurantInfo(); // Restoran bilgilerini çek
    _loadBayRejectSetting(); // ⭐ Bay red etme ayarını çek
    _startButtonCountdownTimer(); // ⭐ Buton countdown timer'ı başlat
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _buttonCountdownTimer?.cancel(); // ⭐ Buton countdown timer'ı temizle
    super.dispose();
  }

  /// ⏰ Buton countdown timer'ı başlat (2 dakika kontrolü için)
  void _startButtonCountdownTimer() {
    _buttonCountdownTimer?.cancel();
    _buttonCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // State güncellenmesi için boş setState (buton kontrolü build'de yapılacak)
        });
      } else {
        timer.cancel();
      }
    });
  }

  /// ⭐ Restoran bilgilerini t_work collection'ından çek
  Future<void> _loadRestaurantInfo() async {
    try {
      print('📍 Restoran bilgileri yükleniyor... s_work: ${widget.order.sWork}');
      
      final workQuery = await FirebaseFirestore.instance
          .collection('t_work')
          .where('s_id', isEqualTo: widget.order.sWork)
          .limit(1)
          .get();

      if (workQuery.docs.isNotEmpty) {
        final workData = workQuery.docs.first.data();
        
        setState(() {
          _restaurantName = workData['s_name'] ?? 'Restoran Adı Yok';
          _restaurantPhone = workData['s_phone'] ?? '';
          
          // Adres bilgisi
          final sLoc = workData['s_loc'];
          if (sLoc is Map) {
            _restaurantAddress = sLoc['ss_adres'] ?? '';
            
            // Konum bilgisi
            final ssLocation = sLoc['ss_location'];
            if (ssLocation is GeoPoint) {
              _restaurantLocation = {
                'latitude': ssLocation.latitude,
                'longitude': ssLocation.longitude,
              };
            }
          }
          
          _isLoadingRestaurant = false;
        });
        
        print('✅ Restoran bilgileri yüklendi:');
        print('   İsim: $_restaurantName');
        print('   Adres: $_restaurantAddress');
        print('   Telefon: $_restaurantPhone');
      } else {
        print('⚠️ t_work collection\'ında s_id=${widget.order.sWork} bulunamadı!');
        setState(() => _isLoadingRestaurant = false);
      }
    } catch (e) {
      print('❌ Restoran bilgileri yüklenirken hata: $e');
      setState(() => _isLoadingRestaurant = false);
    }
  }

  /// ⭐ Bay'ın kurye sipariş red etme ve adres görünürlük ayarlarını t_bay.s_settings'ten çek
  Future<void> _loadBayRejectSetting() async {
    try {
      final bayId = widget.order.sBay;
      if (bayId == 0) {
        print('⚠️ Bay ID 0, ayar yüklenemiyor');
        setState(() {
          _courierOrderRejectEnabled = false; // Güvenli default
          _orderAddressVisibleAfterOrder = true; // Default: adres görünür
          _isLoadingRejectSetting = false;
        });
        return;
      }

      print('🏢 Bay ayarları yükleniyor... s_bay: $bayId');
      
      final bayQuery = await FirebaseFirestore.instance
          .collection('t_bay')
          .where('s_id', isEqualTo: bayId)
          .limit(1)
          .get();

      if (bayQuery.docs.isNotEmpty) {
        final bayData = bayQuery.docs.first.data();
        final sSettings = bayData['s_settings'] as Map<String, dynamic>?;
        
        if (sSettings != null) {
          // courierOrderRejectEnabled ayarı
          final rejectEnabled = sSettings['courierOrderRejectEnabled'] as bool? ?? false;
          
          // orderAddressVisibleAfterOrder ayarı
          final addressVisible = sSettings['orderAddressVisibleAfterOrder'] as bool? ?? true; // Default: true
          
          setState(() {
            _courierOrderRejectEnabled = rejectEnabled;
            _orderAddressVisibleAfterOrder = addressVisible;
            _isLoadingRejectSetting = false;
          });
          
          print('✅ Bay ayarları yüklendi:');
          print('   courierOrderRejectEnabled = $rejectEnabled');
          print('   orderAddressVisibleAfterOrder = $addressVisible');
        } else {
          print('⚠️ s_settings bulunamadı, default değerler kullanılıyor');
          setState(() {
            _courierOrderRejectEnabled = false; // Güvenli default
            _orderAddressVisibleAfterOrder = true; // Default: adres görünür
            _isLoadingRejectSetting = false;
          });
        }
      } else {
        print('⚠️ t_bay collection\'ında s_id=$bayId bulunamadı!');
        setState(() {
          _courierOrderRejectEnabled = false; // Güvenli default
          _orderAddressVisibleAfterOrder = true; // Default: adres görünür
          _isLoadingRejectSetting = false;
        });
      }
    } catch (e) {
      print('❌ Bay ayarları yüklenirken hata: $e');
      setState(() {
        _courierOrderRejectEnabled = false; // Güvenli default
        _orderAddressVisibleAfterOrder = true; // Default: adres görünür
        _isLoadingRejectSetting = false;
      });
    }
  }

  void _startCountdownIfNeeded() {
    if (widget.order.sStat == 0 &&
        (widget.order.sCourierAccepted == null ||
            widget.order.sCourierAccepted == false)) {
      final createdAt = widget.order.sCdate;
      if (createdAt != null) {
        final elapsed = DateTime.now().difference(createdAt).inSeconds;
        final remaining = 120 - elapsed; // 2 dakika

        if (remaining > 0) {
          setState(() => _remainingTime = remaining);

          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (mounted) {
              setState(() {
                if (_remainingTime != null && _remainingTime! > 0) {
                  _remainingTime = _remainingTime! - 1;
                } else {
                  _autoRejectOrder();
                  timer.cancel();
                }
              });
            }
          });
        }
      }
    }
  }

  Future<void> _autoRejectOrder() async {
    // Otomatik red
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _acceptOrder() async {
    setState(() => _isProcessing = true);
    try {
      await FirebaseService.acceptOrder(widget.order.docId);
      
      // ⭐ JaviPos API çağrısı (Status: "2" = Hazırlanıyor)
      if (widget.order.javiPosid != null && widget.order.javiPosid!.isNotEmpty &&
          widget.order.clientId != null && widget.order.clientId!.isNotEmpty) {
        await JaviPosApiService.updateOrderStatus(
          javiPosid: widget.order.javiPosid!,
          clientId: widget.order.clientId!,
          status: '2', // Hazırlanıyor
        );
      } else {
        print('⚠️ JaviPos API: JaviPosid veya ClientId eksik');
        print('   JaviPosid: ${widget.order.javiPosid}');
        print('   ClientId: ${widget.order.clientId}');
      }
      
      _countdownTimer?.cancel();
      if (mounted) {
        Navigator.pop(context);
        _showTopRightNotification('✅ Sipariş onaylandı!', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        _showTopRightNotification('❌ Hata: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('❌ Siparişi Reddet'),
        content: const Text('Bu siparişi reddetmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reddet'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await FirebaseService.rejectOrder(widget.order.docId, widget.order.sCourier);
      if (mounted) {
        Navigator.pop(context);
        _showTopRightNotification('🚫 Sipariş reddedildi');
      }
    } catch (e) {
      if (mounted) {
        _showTopRightNotification('❌ Hata: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickupOrder() async {
    setState(() => _isProcessing = true);
    try {
      // ⭐ 1. Tracking Token Oluştur (unique)
      final trackingToken = '${widget.order.sId}_${DateTime.now().millisecondsSinceEpoch}';
      
      // ⭐ 2. Firebase güncelle (tracking token ile)
      await FirebaseFirestore.instance
          .collection('t_orders')
          .doc(widget.order.docId)
          .update({
        's_stat': 1, // Yolda
        's_received': Timestamp.now(),
        's_tracking_token': trackingToken, // ⭐ Tracking token ekle
      });

      // ⭐ 3. Posentegra API çağrısı (Teslim Al - 1. adım)
      if (widget.order.sOrderscr != 0) {
        final token = widget.order.sOrganizationToken ?? '';
        final orderId = widget.order.sPid;

        if (token.isNotEmpty && orderId.isNotEmpty) {
          print('🚀 TESLİM AL: Posentegra API çağrılıyor...');
          await PlatformApiService.callPlatformDeliveryApi(
            platformId: widget.order.sOrderscr,
            organizationToken: token,
            orderId: orderId,
          );
        } else {
          print('⚠️ TESLİM AL: Token veya OrderID eksik!');
          print('   Token: ${token.isEmpty ? "YOK" : "VAR"}');
          print('   OrderID: ${orderId.isEmpty ? "YOK" : "VAR"}');
        }
      }

      // ⭐ JaviPos API çağrısı (Teslim Al - Status: "3" = Yolda)
      if (widget.order.javiPosid != null && widget.order.javiPosid!.isNotEmpty &&
          widget.order.clientId != null && widget.order.clientId!.isNotEmpty) {
        await JaviPosApiService.updateOrderStatus(
          javiPosid: widget.order.javiPosid!,
          clientId: widget.order.clientId!,
          status: '3', // Yolda
        );
      } else {
        print('⚠️ JaviPos API (Teslim Al): JaviPosid veya ClientId eksik');
      }

      // 📍 4. SMS GÖNDER (s_sms_template kullanarak, trackingUrl ile)
      SmsService.sendTrackingSMS(widget.order.docId, trackingToken).then((success) {
        if (success) {
          print('✅ SMS müşteriye gönderildi (s_sms_template)');
        } else {
          print('⚠️ SMS gönderilemedi (arka planda hata)');
        }
      }).catchError((error) {
        print('❌ SMS gönderim hatası: $error');
      });

      if (mounted) {
        Navigator.pop(context);
        _showTopRightNotification('✅ Sipariş teslim alındı!', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        _showTopRightNotification('❌ Hata: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 💰 Ödeme yöntemi doğrulama ve teslim
  Future<void> _deliverOrder() async {
    // ⭐ Önce ödeme doğrulama dialogu göster
    final confirmed = await _showPaymentConfirmationDialog();
    
    if (confirmed != true) {
      print('❌ Teslim iptal edildi (Ödeme doğrulanamadı)');
      return;
    }
    
    // ⭐ Ödeme onaylandı, teslim et
    setState(() => _isProcessing = true);
    try {
      final deliveredTime = DateTime.now();
      
      // Siparişin güncel ödeme bilgilerini al (dialog'da güncellenmiş olabilir)
      final orderDoc = await FirebaseFirestore.instance
          .collection('t_orders')
          .doc(widget.order.docId)
          .get();
      
      final orderData = orderDoc.data();
      final sPay = orderData?['s_pay'] as Map<String, dynamic>?;
      final currentPayType = sPay?['ss_paytype'] ?? orderData?['ss_paytype'] ?? widget.order.ssPaytype;
      final currentPayCount = (sPay?['ss_paycount'] ?? orderData?['ss_paycount'] ?? widget.order.ssPaycount).toDouble();
      final payCash = (sPay?['payCash'] ?? 0).toDouble();
      final cashAmount = payCash > 0 ? payCash : (currentPayType == 0 ? currentPayCount : 0.0);
      
      await FirebaseFirestore.instance
          .collection('t_orders')
          .doc(widget.order.docId)
          .update({
        's_stat': 2, // Teslim edildi
        's_ddate': Timestamp.fromDate(deliveredTime),
        's_delivered': Timestamp.fromDate(deliveredTime),
      });

      // ⭐ Nakit transaction kaydı oluştur (eğer nakit ödeme varsa)
      if (cashAmount > 0) {
        await CourierCashTransactionService.createCashTransaction(
          orderId: widget.order.docId,
          orderPid: widget.order.sPid,
          courierId: widget.order.sCourier,
          bayId: widget.order.sBay,
          workId: widget.order.sWork > 0 ? widget.order.sWork : null, // Restoran ID varsa kaydet
          originalPaymentType: widget.order.ssPaytype,
          finalPaymentType: currentPayType,
          cashAmount: cashAmount,
          orderDeliveredAt: deliveredTime,
        );
      }

      // ⭐ Posentegra API çağrısı (Teslim Et - 2. adım)
      if (widget.order.sOrderscr != 0) {
        final token = widget.order.sOrganizationToken ?? '';
        final orderId = widget.order.sPid;

        if (token.isNotEmpty && orderId.isNotEmpty) {
          print('🚀 TESLİM ET: Posentegra API çağrılıyor...');
          await PlatformApiService.callPlatformDeliveryApi(
            platformId: widget.order.sOrderscr,
            organizationToken: token,
            orderId: orderId,
          );
        } else {
          print('⚠️ TESLİM ET: Token veya OrderID eksik!');
          print('   Token: ${token.isEmpty ? "YOK" : "VAR"}');
          print('   OrderID: ${orderId.isEmpty ? "YOK" : "VAR"}');
        }
      }

      // ⭐ JaviPos API çağrısı (Teslim Et - Status: "4" = Teslim Edildi)
      if (widget.order.javiPosid != null && widget.order.javiPosid!.isNotEmpty &&
          widget.order.clientId != null && widget.order.clientId!.isNotEmpty) {
        await JaviPosApiService.updateOrderStatus(
          javiPosid: widget.order.javiPosid!,
          clientId: widget.order.clientId!,
          status: '4', // Teslim Edildi
        );
      } else {
        print('⚠️ JaviPos API (Teslim Et): JaviPosid veya ClientId eksik');
      }

      // ⭐ Kurye durumunu güncelle: Başka aktif siparişi varsa meşgul, yoksa müsait
      await _updateCourierStatusAfterDelivery(widget.order.sCourier);

      if (mounted) {
        Navigator.pop(context);
        _showTopRightNotification('✅ Sipariş teslim edildi!', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        _showTopRightNotification('❌ Hata: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// ⭐ Teslim sonrası kurye durumunu güncelle
  /// Başka aktif siparişi varsa meşgul (2), yoksa müsait (1) yap
  Future<void> _updateCourierStatusAfterDelivery(int courierId) async {
    try {
      print('🔄 Teslim sonrası kurye durumu kontrol ediliyor: courierId=$courierId');
      
      // Kuryenin başka aktif siparişi var mı kontrol et
      // Aktif sipariş: s_stat in [0, 1, 4] (0=Hazır, 1=Yolda, 4=Hazırlanıyor)
      final activeOrdersQuery = await FirebaseFirestore.instance
          .collection('t_orders')
          .where('s_courier', isEqualTo: courierId)
          .where('s_stat', whereIn: [0, 1, 4])
          .get();

      final activeOrderCount = activeOrdersQuery.docs.length;
      print('📦 Aktif sipariş sayısı: $activeOrderCount');

      // Kurye durumunu belirle
      final newStatus = activeOrderCount > 0 ? 2 : 1; // 2=Meşgul, 1=Müsait
      
      // Kurye durumunu güncelle
      await FirebaseService.updateCourierStatus(courierId, newStatus);
      
      final statusText = newStatus == 2 ? 'Meşgul' : 'Müsait';
      print('✅ Kurye durumu güncellendi: $statusText (s_stat=$newStatus)');
    } catch (e) {
      print('❌ Kurye durumu güncellenirken hata: $e');
      // Hata durumunda sessizce devam et (kritik değil)
    }
  }

  /// 💳 Ödeme doğrulama dialogu
  Future<bool?> _showPaymentConfirmationDialog() async {
    // Mevcut ödeme bilgileri (OrderModel'den)
    final currentPaymentType = widget.order.ssPaytype;
    final currentTotal = widget.order.ssPaycount;
    
    // ⭐ Online ödeme ise direkt teslim et (dialog gösterme)
    if (currentPaymentType == 2) {
      print('   💳 Online ödeme - Direkt teslim ediliyor');
      return true;
    }
    
    // Ödeme tipine göre nakit/kart/online dağılımı
    double currentCash = 0;
    double currentCard = 0;
    double currentOnline = 0;
    
    if (currentPaymentType == 0) {
      currentCash = currentTotal;
    } else if (currentPaymentType == 1) {
      currentCard = currentTotal;
    }

    // Dialog state değişkenleri
    int selectedPaymentType = currentPaymentType;
    double newCash = currentCash;
    double newCard = currentCard;
    double newOnline = currentOnline;
    int? cardPaymentMethod; // null, 1=Pos Cihazı, 2=NFC

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.payment,
                      color: Colors.orange.shade700,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Ödeme Doğrulama',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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
                    // Uyarı mesajı
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange.shade700, size: 16),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Teslim etmeden önce ödeme yöntemini doğrulayın',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 10),
                    
                    // Toplam tutar
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade50, Colors.blue.shade100],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Toplam Tutar:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${currentTotal.toStringAsFixed(2)} ₺',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    
                    // Ödeme yöntemi seçimi
                    const Text(
                      'Ödeme Yöntemi:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Nakit
                    _buildPaymentOption(
                      icon: Icons.money,
                      label: 'Kapıda Nakit',
                      value: 0,
                      groupValue: selectedPaymentType,
                      color: Colors.green,
                      onChanged: (value) {
                        setDialogState(() {
                          selectedPaymentType = value!;
                          newCash = currentTotal;
                          newCard = 0;
                          newOnline = 0;
                        });
                      },
                    ),
                    
                    const SizedBox(height: 6),
                    
                    // Kart
                    _buildPaymentOption(
                      icon: Icons.credit_card,
                      label: 'Kapıda Kredi/Banka Kartı',
                      value: 1,
                      groupValue: selectedPaymentType,
                      color: Colors.blue,
                      onChanged: (value) {
                        setDialogState(() {
                          selectedPaymentType = value!;
                          newCash = 0;
                          newCard = currentTotal;
                          newOnline = 0;
                          cardPaymentMethod = null; // Reset card payment method
                        });
                      },
                    ),
                    
                    // ⭐ Kart ödeme yöntemi seçimi (sadece kart seçildiğinde göster)
                    if (selectedPaymentType == 1) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Kart Ödeme Yöntemi:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            
                            // Pos Cihazı
                            InkWell(
                              onTap: () {
                                setDialogState(() {
                                  cardPaymentMethod = 1;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: cardPaymentMethod == 1 
                                      ? Colors.blue.shade100 
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: cardPaymentMethod == 1 
                                        ? Colors.blue 
                                        : Colors.grey.shade300,
                                    width: cardPaymentMethod == 1 ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.point_of_sale,
                                      color: cardPaymentMethod == 1 
                                          ? Colors.blue 
                                          : Colors.grey,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Pos Cihazı',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (cardPaymentMethod == 1)
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.blue,
                                        size: 18,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 6),
                            
                            // NFC ile Ödeme Al
                            InkWell(
                              onTap: () async {
                                // ⭐ NFC özelliği henüz desteklenmiyor - hata mesajı göster
                                await _showNfcCardReadingDialog(context);
                                // Hata mesajından sonra NFC seçimini iptal et
                                setDialogState(() {
                                  cardPaymentMethod = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: cardPaymentMethod == 2 
                                      ? Colors.purple.shade100 
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: cardPaymentMethod == 2 
                                        ? Colors.purple 
                                        : Colors.grey.shade300,
                                    width: cardPaymentMethod == 2 ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.nfc,
                                      color: cardPaymentMethod == 2 
                                          ? Colors.purple 
                                          : Colors.grey,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'NFC ile Ödeme Al',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    if (cardPaymentMethod == 2)
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.purple,
                                        size: 18,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    // Değişiklik uyarısı
                    if (selectedPaymentType != currentPaymentType) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.red.shade700, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'UYARI: Ödeme yöntemi değiştirilecek!',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
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
                // İptal
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'İptal',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                
                // Onayla ve Teslim Et
                ElevatedButton(
                  onPressed: () async {
                    // ⭐ Kart ödeme seçildiyse yöntem kontrolü
                    if (selectedPaymentType == 1 && cardPaymentMethod == null) {
                      _showTopRightNotification('Lütfen kart ödeme yöntemini seçin (Pos Cihazı veya NFC)');
                      return;
                    }
                    
                    // Eğer ödeme değişmişse kaydet
                    if (selectedPaymentType != currentPaymentType) {
                      await _savePaymentChange(
                        originalType: currentPaymentType,
                        newType: selectedPaymentType,
                        originalCash: currentCash,
                        originalCard: currentCard,
                        originalOnline: currentOnline,
                        newCash: newCash,
                        newCard: newCard,
                        newOnline: newOnline,
                        total: currentTotal,
                      );
                      
                      // Firestore'da siparişin ödeme bilgisini güncelle
                      final updateData = {
                        'ss_paytype': selectedPaymentType,
                        'ss_paycount': currentTotal,
                        's_pay.ss_paytype': selectedPaymentType,
                        's_pay.ss_paycount': currentTotal,
                        's_pay.payCash': newCash,
                        's_pay.payCard': newCard,
                        's_pay.payOnline': newOnline,
                      };
                      
                      // ⭐ Kart ödeme yöntemi ve tutarı ekle
                      if (selectedPaymentType == 1 && cardPaymentMethod != null) {
                        updateData['s_pay.card_payment_method'] = cardPaymentMethod!;
                        updateData['s_pay.card_payment_amount'] = newCard;
                      }
                      
                      await FirebaseFirestore.instance
                          .collection('t_orders')
                          .doc(widget.order.docId)
                          .update(updateData);
                    } else if (selectedPaymentType == 1 && cardPaymentMethod != null) {
                      // ⭐ Ödeme tipi değişmedi ama kart yöntemi seçildi, sadece kart yöntemini kaydet
                      await FirebaseFirestore.instance
                          .collection('t_orders')
                          .doc(widget.order.docId)
                          .update({
                        's_pay.card_payment_method': cardPaymentMethod!,
                        's_pay.card_payment_amount': newCard,
                      });
                    }
                    
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text(
                    'Onayla ve Teslim Et',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 📱 NFC kart okutma dialogu - Hata mesajı göster
  Future<void> _showNfcCardReadingDialog(BuildContext parentContext) async {
    return showDialog<void>(
      context: parentContext,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'NFC Ödeme Hatası',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Kurye Şirketi NFC Özelliği Henüz Tanımlı Değildir.',
            style: TextStyle(
              fontSize: 16,
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Tamam',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 💳 Ödeme yöntemi seçim widget'ı
  Widget _buildPaymentOption({
    required IconData icon,
    required String label,
    required int value,
    required int groupValue,
    required Color color,
    required ValueChanged<int?> onChanged,
  }) {
    final isSelected = value == groupValue;
    
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade50,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Radio<int>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: color,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 6),
            Icon(icon, color: isSelected ? color : Colors.grey, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 💾 Ödeme değişikliğini Firestore'a kaydet
  Future<void> _savePaymentChange({
    required int originalType,
    required int newType,
    required double originalCash,
    required double originalCard,
    required double originalOnline,
    required double newCash,
    required double newCard,
    required double newOnline,
    required double total,
  }) async {
    try {
      // Ödeme tipi isimleri
      final paymentTypeNames = {
        0: 'Kapıda Nakit',
        1: 'Kapıda Kredi',
        2: 'Online Ödeme',
      };

      // Kurye adını ve bay adını al
      final prefs = await SharedPreferences.getInstance();
      final courierName = prefs.getString('courier_name') ?? 'Kurye';
      final bayId = prefs.getInt('courier_bay') ?? 0;
      
      // Bay adını almak için Firestore'dan çek
      String? bayName;
      try {
        final bayDoc = await FirebaseFirestore.instance
            .collection('t_bay')
            .where('s_id', isEqualTo: bayId)
            .limit(1)
            .get();
        
        if (bayDoc.docs.isNotEmpty) {
          bayName = bayDoc.docs.first.data()['s_name'];
        }
      } catch (e) {
        print('⚠️ Bay adı alınamadı: $e');
      }

      // Ödeme değişiklik sayısını hesapla (bugün yapılan toplam değişiklik)
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final changeCountQuery = await FirebaseFirestore.instance
          .collection('payment_changes')
          .where('changed_by_courier_id', isEqualTo: widget.order.sCourier)
          .where('changed_at', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .get();
      
      final changeCountToday = changeCountQuery.docs.length + 1; // +1 çünkü şu anki değişiklik henüz kaydedilmedi

      // payment_changes koleksiyonuna kaydet (mevcut yapıya uygun)
      await FirebaseFirestore.instance.collection('payment_changes').add({
        'app_version': '60.12.3', // Uygulama versiyonu
        'bay_id': null, // Null olarak kaydediliyor (mevcut yapıya uygun)
        'change_count_today': changeCountToday,
        'changed_at': FieldValue.serverTimestamp(),
        'changed_by_courier_id': widget.order.sCourier,
        'changed_by_courier_name': courierName,
        'courier_bay_id': bayId,
        'courier_bay_name': bayName, // Bay adı
        'created_at': FieldValue.serverTimestamp(),
        'customer_address': widget.order.ssAdres.isNotEmpty ? widget.order.ssAdres : null,
        'customer_name': widget.order.ssFullname.isNotEmpty ? widget.order.ssFullname : null,
        'customer_phone': widget.order.ssPhone.isNotEmpty ? widget.order.ssPhone : null,
        'is_suspicious': false,
        'new_amount_card': newCard,
        'new_amount_cash': newCash,
        'new_payment_type': newType,
        'new_payment_type_name': paymentTypeNames[newType],
        'new_total': total,
        'order_distance': double.tryParse(widget.order.sDinstance) ?? 0.0, // String'den double'a çevir
        'order_firestore_id': widget.order.docId,
        'order_id': widget.order.sId,
        'order_platform': widget.order.sOrderscr,
        'order_status_at_change': 1, // 1 = Yolda (Teslim etmeden önce)
        'original_amount_card': originalCard,
        'original_amount_cash': originalCash,
        'original_payment_type': originalType,
        'original_payment_type_name': paymentTypeNames[originalType],
        'original_total': total,
        'platform': 'android',
        'restaurant_id': widget.order.sWork,
        'restaurant_name': _restaurantName, // Restoran adı (t_work'ten çekiliyor)
      });

      print('💾 Ödeme değişikliği kaydedildi: $courierName tarafından');
      print('   📊 Bugün yapılan toplam değişiklik: $changeCountToday');
    } catch (e) {
      print('❌ Ödeme değişikliği kaydetme hatası: $e');
    }
  }

  Future<void> _openMap(double lat, double lng, String label) async {
    // Harita seçim dialogunu göster
    final mapChoice = await _showMapSelectionDialog(label);
    
    if (mapChoice == null) return; // Kullanıcı iptal etti
    
    Uri url;
    
    if (mapChoice == 'google') {
      // Google Maps - Navigasyon için
      url = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
      print('🗺️ Google Maps açılıyor: $url');
    } else if (mapChoice == 'yandex') {
      // Yandex Maps - Konumu göster (navigasyon kullanıcı tarafından başlatılabilir)
      url = Uri.parse(
          'https://yandex.com.tr/maps/?ll=$lat%2C$lng&z=16&l=map');
      print('🗺️ Yandex Maps açılıyor: $url');
    } else {
      return;
    }

    try {
      final result = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!result) {
        print('   ❌ Harita açılamadı');
        if (mounted) {
          _showTopRightNotification('❌ Harita açılamadı');
        }
      }
    } catch (e) {
      print('   ❌ Harita açma hatası: $e');
      if (mounted) {
        _showTopRightNotification('❌ Harita açılamadı: $e');
      }
    }
  }

  /// 🗺️ Harita seçim dialogu (Google Maps / Yandex Maps)
  Future<String?> _showMapSelectionDialog(String label) async {
    return await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon ve Başlık
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.map,
                  color: Colors.blue.shade700,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              
              const Text(
                'Harita Seçin',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$label konumunu açmak için harita uygulaması seçin',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              
              // Google Maps Seçeneği
              InkWell(
                onTap: () => Navigator.pop(context, 'google'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.map,
                          color: Colors.green.shade700,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Google Maps',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Navigasyon ile aç',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Yandex Maps Seçeneği
              InkWell(
                onTap: () => Navigator.pop(context, 'yandex'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.map_outlined,
                          color: Colors.red.shade700,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Yandex Maps',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Navigasyon ile aç',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // İptal Butonu
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text(
                  'İptal',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ⭐ Müşteri telefon arama (Getir mantığı - dialog göster)
  Future<void> _openCustomerPhone() async {
    String phone = widget.order.ssPhone;
    
    print('📞 Müşteri Aranıyor...');
    print('   Orijinal Format: $phone');
    
    // ⭐ PIN kodu ayırma (virgül veya slash ile)
    String cleanPhone = phone;
    String? pinCode;
    
    // 1. "/" varsa PIN ayır (0850 formatı)
    if (phone.contains('/')) {
      final parts = phone.split('/');
      cleanPhone = parts[0].trim();
      pinCode = parts[1].trim().replaceAll(RegExp(r'[^\d]'), '');
      print('   ✅ PIN kodu (/) tespit edildi: $pinCode');
    }
    // 2. "," varsa PIN ayır (Trendyol formatı)
    else if (phone.contains(',')) {
      final parts = phone.split(',');
      cleanPhone = parts[0].trim();
      pinCode = parts[1].trim().replaceAll(RegExp(r'[^\d]'), '');
      print('   ✅ PIN kodu (,) tespit edildi: $pinCode');
    }
    
    // Telefonu temizle (sadece rakamlar ve +)
    cleanPhone = cleanPhone.replaceAll(RegExp(r'[^\d+]'), '');
    
    // +90 ile başlıyorsa 0 ile başlayacak şekle çevir
    if (cleanPhone.startsWith('+90')) {
      cleanPhone = '0${cleanPhone.substring(3)}';
    } else if (cleanPhone.startsWith('90') && !cleanPhone.startsWith('905')) {
      cleanPhone = '0${cleanPhone.substring(2)}';
    } else if (cleanPhone.isNotEmpty && !cleanPhone.startsWith('0')) {
      cleanPhone = '0$cleanPhone';
    }
    
    print('   Temizlenmiş Telefon: $cleanPhone');
    
    // ⭐ PIN kodu varsa (Getir/Trendyol/0850) dialog göster
    if (pinCode != null && pinCode.isNotEmpty) {
      print('   📌 PIN kodu tespit edildi - Dialog gösteriliyor');
      print('   📞 Telefon: $cleanPhone');
      print('   🔑 PIN: $pinCode');
      // Dialog göster
      await _showCallDialog(cleanPhone, pinCode);
    } else {
      // Normal cep telefonu - direkt ara
      print('   ℹ️ Normal cep telefonu (05XX) - Direkt aranıyor');
      await _makePhoneCall(cleanPhone);
    }
  }

  /// ⭐ 0850 numaraları için profesyonel arama dialog'u
  Future<void> _showCallDialog(String phone, String orderCode) async {
    return showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              
              // Başlık
              const Text(
                'Müşteri Arama',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              // Telefon numarası
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.phone, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _formatPhoneNumber(phone),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Sipariş kodu bilgisi
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                ),
                child: Column(
                  children: [
                    const Text(
                      '🎵 PIN kodu otomatik girilecek:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '(2 saniye bekledikten sonra)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Sipariş kodu (büyük ve kopyalanabilir)
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: orderCode));
                        _showTopRightNotification('✅ Kod kopyalandı: $orderCode', isSuccess: true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              orderCode,
                              style: const TextStyle(
                                color: Color(0xFF2196F3),
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.content_copy, color: Color(0xFF2196F3), size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manuel girmek için dokun ve kopyala',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Butonlar
              Row(
                children: [
                  // İptal butonu
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.white.withOpacity(0.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'İptal',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Ara butonu
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _makePhoneCall(phone, pinCode: orderCode);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF2196F3),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.phone, size: 22),
                      label: const Text(
                        'ARA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ⭐ Telefon numarasını formatla (0850 123 45 67)
  String _formatPhoneNumber(String phone) {
    if (phone.length == 11 && phone.startsWith('0')) {
      return '${phone.substring(0, 4)} ${phone.substring(4, 7)} ${phone.substring(7, 9)} ${phone.substring(9)}';
    }
    return phone;
  }

  /// ⭐ Telefon araması yap (PIN kodu varsa otomatik DTMF ile gönder)
  Future<void> _makePhoneCall(String phone, {String? pinCode}) async {
    String dialString = phone;
    
    // ⭐ Eğer PIN kodu varsa, DTMF formatında ekle
    if (pinCode != null && pinCode.isNotEmpty) {
      // tel:08503469382,,915159
      // İki virgül (,,) = 2 saniye bekleme, sonra PIN tonları gönderilir
      dialString = '$phone,,$pinCode';
      print('   🔐 PIN kodu otomatik girilecek: $pinCode');
      print('   ⏱️ Bekleme süresi: 2 saniye (,,)');
    }
    
    final url = Uri.parse('tel:$dialString');
    print('   📱 Arama URL: $url');

    try {
      final result = await launchUrl(url);
      if (!result) {
        print('   ❌ launchUrl false döndü');
        if (mounted) {
          _showTopRightNotification('❌ Telefon uygulaması açılamadı');
        }
      } else {
        print('   ✅ Telefon uygulaması açıldı');
        if (pinCode != null && pinCode.isNotEmpty) {
          print('   🎵 DTMF tonları otomatik gönderilecek');
        }
      }
    } catch (e) {
      print('   ❌ Arama hatası: $e');
      if (mounted) {
        _showTopRightNotification('❌ Arama yapılamadı: $e');
      }
    }
  }

  /// ⭐ Restoran telefon arama (Getir mantığı - dialog göster)
  Future<void> _openPhone(String phone) async {
    print('📞 Restoran Aranıyor...');
    print('   Orijinal: $phone');
    
    // ⭐ PIN kodu ayırma (virgül veya slash ile)
    String cleanPhone = phone;
    String? pinCode;
    
    // 1. "/" varsa PIN ayır
    if (phone.contains('/')) {
      final parts = phone.split('/');
      cleanPhone = parts[0].trim();
      pinCode = parts[1].trim().replaceAll(RegExp(r'[^\d]'), '');
      print('   ✅ PIN kodu (/) tespit edildi: $pinCode');
    }
    // 2. "," varsa PIN ayır (Trendyol formatı)
    else if (phone.contains(',')) {
      final parts = phone.split(',');
      cleanPhone = parts[0].trim();
      pinCode = parts[1].trim().replaceAll(RegExp(r'[^\d]'), '');
      print('   ✅ PIN kodu (,) tespit edildi: $pinCode');
    }
    
    // Telefonu temizle
    cleanPhone = cleanPhone.replaceAll(RegExp(r'[^\d]'), '');
    
    // 0 ile başlamıyorsa ekle
    if (cleanPhone.isNotEmpty && !cleanPhone.startsWith('0')) {
      cleanPhone = '0$cleanPhone';
    }
    
    print('   Temizlenmiş Telefon: $cleanPhone');
    
    // ⭐ PIN kodu varsa dialog göster
    if (pinCode != null && pinCode.isNotEmpty) {
      print('   📌 PIN kodu tespit edildi - Dialog gösteriliyor');
      print('   🔑 PIN: $pinCode');
      await _showCallDialog(cleanPhone, pinCode);
      return;
    }

    // PIN kodu yoksa direkt ara
    final url = Uri.parse('tel:$cleanPhone');
    print('   ℹ️ Normal arama (PIN yok)');

    try {
      // ⭐ canLaunchUrl kontrolü kaldırıldı, direkt launch
      final result = await launchUrl(url);
      if (!result) {
        print('   ❌ launchUrl false döndü');
        if (mounted) {
          _showTopRightNotification('❌ Telefon uygulaması açılamadı');
        }
      } else {
        print('   ✅ Telefon uygulaması açıldı');
      }
    } catch (e) {
      print('   ❌ Arama hatası: $e');
      if (mounted) {
        _showTopRightNotification('❌ Arama yapılamadı: $e');
      }
    }
  }

  /// ⭐ Yukarı sağda bildirim göster (2 saniye sonra kaybolur)
  void _showTopRightNotification(String message, {bool isSuccess = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    final backgroundColor = isSuccess ? const Color(0xFF4CAF50) : Colors.red;
    final icon = isSuccess ? Icons.check_circle_outline : Icons.error_outline;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 100,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset((1 - value) * 50, 0),
                  child: child,
                ),
              );
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
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

    // 2 saniye sonra kaldır
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

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

  Color _getStatusColor(int stat) {
    switch (stat) {
      case 0:
        return Colors.green;
      case 1:
        return Colors.blue;
      case 2:
        return const Color(0xFF4CAF50); // Teslim Edildi (Yeşil)
      case 3:
        return Colors.red; // İptal
      case 4:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPreparing = widget.order.sStat == 4; // ⭐ Hazırlanıyor
    final isWaitingForApproval = widget.order.sStat == 0 &&
        (widget.order.sCourierAccepted == null ||
            widget.order.sCourierAccepted == false);
    final isWaitingForPickup =
        widget.order.sStat == 0 && widget.order.sCourierAccepted == true;
    final isOnDelivery = widget.order.sStat == 1;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ⭐ Countdown Banner KALDIRILDI (artık gösterilmiyor)
                  
                  const SizedBox(height: 12),

                  // Restoran Bilgileri (9. Düzeltme)
                  _buildRestaurantCard(),

                  const SizedBox(height: 12),

                  // Müşteri Bilgileri
                  _buildCustomerCard(),

                  const SizedBox(height: 12),

                  // Sipariş Bilgileri
                  _buildOrderInfoCard(),

                  const SizedBox(height: 80), // Action button için boşluk
                ],
              ),
            ),
          ),

          // Action Button (Fixed at bottom)
          _buildActionButton(
            isPreparing, // ⭐ Yeni parametre
            isWaitingForApproval,
            isWaitingForPickup,
            isOnDelivery,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_getStatusColor(widget.order.sStat), _getStatusColor(widget.order.sStat).withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sipariş Detayı',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '#${widget.order.sId}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                _getStatusText(widget.order.sStat),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownBanner() {
    final minutes = (_remainingTime! ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingTime! % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Onay Süresi',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$minutes:$seconds',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 9. Düzeltme: Restoran Kartı
  Widget _buildRestaurantCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFFF9800),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.restaurant, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Restoran Bilgileri',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Konum ve Telefon Butonları
                IconButton(
                  onPressed: _restaurantLocation != null
                      ? () => _openMap(
                            _restaurantLocation!['latitude'],
                            _restaurantLocation!['longitude'],
                            'Restoran',
                          )
                      : null,
                  icon: const Icon(Icons.location_on, color: Colors.white, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(32, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: _restaurantPhone != null && _restaurantPhone!.isNotEmpty
                      ? () => _openPhone(_restaurantPhone!)
                      : null,
                  icon: const Icon(Icons.phone, color: Colors.white, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(32, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _isLoadingRestaurant
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Column(
                        children: [
                          _buildInfoRow(
                            icon: Icons.store,
                            label: 'Restoran Adı',
                            value: _restaurantName ?? 'Restoran Adı Yok',
                            iconColor: const Color(0xFFFF9800),
                          ),
                          const Divider(height: 16),
                          _buildInfoRow(
                            icon: Icons.location_on,
                            label: 'Adres',
                            value: _restaurantAddress?.isEmpty ?? true
                                ? 'Adres bilgisi yok'
                                : _restaurantAddress!,
                            iconColor: Colors.green,
                          ),
                          const Divider(height: 16),
                          _buildInfoRow(
                            icon: Icons.phone,
                            label: 'Telefon',
                            value: _restaurantPhone?.isEmpty ?? true
                                ? 'Telefon bilgisi yok'
                                : _restaurantPhone!,
                            iconColor: Colors.blue,
                          ),
                        ],
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard() {
    // ⭐ Adres gizleme kontrolü: orderAddressVisibleAfterOrder ayarına göre
    // - false ise: Onaydan ÖNCE adres görünür, onaydan SONRA adres gizli
    // - true ise: Onaydan ÖNCE adres gizli, onaydan SONRA adres görünür
    // - null ise: Default olarak onaydan önce gizli (güvenli)
    final shouldHideAddress = _orderAddressVisibleAfterOrder == false
        ? widget.order.sCourierAccepted == true  // false: onaydan önce görünür, onaydan sonra gizli
        : _orderAddressVisibleAfterOrder == true
            ? widget.order.sCourierAccepted != true  // true: onaydan önce gizli, onaydan sonra görünür
            : widget.order.sCourierAccepted != true;  // null: default olarak onaydan önce gizli

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF2196F3),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Müşteri Bilgileri',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Konum ve Telefon Butonları
                if (!shouldHideAddress)
                  IconButton(
                    onPressed: widget.order.ssLoc != null
                        ? () => _openMap(
                              widget.order.ssLoc!['latitude'],
                              widget.order.ssLoc!['longitude'],
                              'Müşteri',
                            )
                        : null,
                    icon: const Icon(Icons.location_on, color: Colors.white, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (!shouldHideAddress) const SizedBox(width: 6),
                IconButton(
                  onPressed: widget.order.ssPhone.isNotEmpty
                      ? _openCustomerPhone // ⭐ Müşteri için özel arama fonksiyonu
                      : null,
                  icon: const Icon(Icons.phone, color: Colors.white, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(32, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildInfoRow(
                  icon: Icons.person,
                  label: 'Ad Soyad',
                  value: widget.order.ssFullname,
                  iconColor: const Color(0xFF2196F3),
                ),
                if (!shouldHideAddress) ...[
                  const Divider(height: 16),
                  _buildInfoRow(
                    icon: Icons.location_on,
                    label: 'Adres',
                    value: widget.order.ssAdres,
                    iconColor: Colors.green,
                    showCopyButton: true,
                  ),
                ],
                const Divider(height: 16),
                _buildInfoRow(
                  icon: Icons.phone,
                  label: 'Telefon',
                  value: widget.order.ssPhone,
                  iconColor: Colors.blue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderInfoCard() {
    // ⭐ KM gizleme kontrolü: s_stat=0 veya 4 ise gizle
    final shouldHideDistance = widget.order.sStat == 0 || widget.order.sStat == 4;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sipariş Bilgileri',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            icon: Icons.payments,
            label: 'Ödeme Tutarı',
            value: '₺${widget.order.ssPaycount.toStringAsFixed(2)}',
            iconColor: Colors.green,
          ),
          const Divider(height: 16),
          _buildInfoRow(
            icon: Icons.credit_card,
            label: 'Ödeme Yöntemi',
            value: widget.order.ssPaytype == 0 
                ? 'Nakit' 
                : widget.order.ssPaytype == 2 
                    ? 'Online Ödeme' 
                    : 'Kredi Kartı',
            iconColor: widget.order.ssPaytype == 2 ? Colors.orange : Colors.blue,
          ),
          if (!shouldHideDistance) ...[
            const Divider(height: 16),
            _buildInfoRow(
              icon: Icons.route,
              label: 'Mesafe',
              value: '${widget.order.sDinstance} KM',
              iconColor: Colors.purple,
            ),
          ],
          if (widget.order.ssNote.isNotEmpty) ...[
            const Divider(height: 16),
            _buildInfoRow(
              icon: Icons.note,
              label: 'Sipariş Notu',
              value: widget.order.ssNote,
              iconColor: Colors.orange,
            ),
          ],
          
          // ⭐ Sipariş İçeriği Butonu (Onaylandıktan sonra göster)
          if (widget.order.sCourierAccepted == true || widget.order.sStat == 1) ...[
            const Divider(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showOrderContent(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.shopping_bag, size: 18),
                label: const Text(
                  'Sipariş İçeriği',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    bool showCopyButton = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                  if (showCopyButton) ...[
                    const SizedBox(width: 4),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: value));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Adres kopyalandı'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.copy,
                            size: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF212121),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    bool isPreparing, // ⭐ Yeni parametre
    bool isWaitingForApproval,
    bool isWaitingForPickup,
    bool isOnDelivery,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: _isProcessing
            ? const Center(child: CircularProgressIndicator())
            : isPreparing
                // ⭐ Status 4 - Hazırlanıyor (Sadece bilgi amaçlı, buton yok)
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF9800),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.restaurant,
                          color: Color(0xFFFF9800),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'SİPARİŞ HAZIRLANIYOR',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF9800),
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  )
                : isWaitingForApproval
                ? Row(
                    children: [
                      // ⭐ Red et butonu sadece courierOrderRejectEnabled == true ise göster
                      if (_courierOrderRejectEnabled == true) ...[
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _rejectOrder,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'REDDET',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: _courierOrderRejectEnabled == true ? 2 : 1,
                        child: ElevatedButton(
                          onPressed: _acceptOrder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9800),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'ONAYLA',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : _buildPickupOrDeliverButton(isWaitingForPickup, isOnDelivery),
      ),
    );
  }

  /// ⏰ Teslim Al / Teslim Et butonu (2 dakika kontrolü ile)
  Widget _buildPickupOrDeliverButton(bool isWaitingForPickup, bool isOnDelivery) {
    // ⭐ 2 dakika kontrolü
    bool isButtonEnabled = true;
    int? remainingSeconds;
    String? waitMessage;

    if (isWaitingForPickup) {
      // Onayla → Teslim Al: sCourierResponseTime kontrolü
      if (widget.order.sCourierResponseTime != null) {
        final timeDiff = DateTime.now().difference(widget.order.sCourierResponseTime!);
        final requiredMinutes = 2;
        if (timeDiff.inMinutes < requiredMinutes) {
          isButtonEnabled = false;
          remainingSeconds = (requiredMinutes * 60) - timeDiff.inSeconds;
          final remainingMinutes = remainingSeconds ~/ 60;
          final remainingSecs = remainingSeconds % 60;
          waitMessage = '$remainingMinutes:${remainingSecs.toString().padLeft(2, '0')}';
        }
      }
    } else if (isOnDelivery) {
      // Teslim Al → Teslim Et: sReceived kontrolü
      if (widget.order.sReceived != null) {
        final timeDiff = DateTime.now().difference(widget.order.sReceived!);
        final requiredMinutes = 2;
        if (timeDiff.inMinutes < requiredMinutes) {
          isButtonEnabled = false;
          remainingSeconds = (requiredMinutes * 60) - timeDiff.inSeconds;
          final remainingMinutes = remainingSeconds ~/ 60;
          final remainingSecs = remainingSeconds % 60;
          waitMessage = '$remainingMinutes:${remainingSecs.toString().padLeft(2, '0')}';
        }
      }
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isButtonEnabled
            ? (isWaitingForPickup ? _pickupOrder : _deliverOrder)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isButtonEnabled
              ? (isWaitingForPickup
                  ? const Color(0xFF4CAF50)  // ⭐ Yeşil - Teslim Al
                  : const Color(0xFF2196F3)) // ⭐ Mavi - Teslim Et
              : Colors.grey, // ⭐ Disabled rengi
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isWaitingForPickup ? 'TESLİM AL' : 'TESLİM ET',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isButtonEnabled ? Colors.white : Colors.white70,
              ),
            ),
            if (!isButtonEnabled && waitMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                '⏰ $waitMessage sonra aktif olacak',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 📦 Sipariş İçeriğini Göster
  Future<void> _showOrderContent(BuildContext context) async {
    try {
      // Firebase'den sipariş içeriğini çek
      final orderDoc = await FirebaseFirestore.instance
          .collection('t_orders')
          .doc(widget.order.docId)
          .get();

      if (!orderDoc.exists) {
        _showErrorDialog(context, 'Sipariş bulunamadı');
        return;
      }

      final orderData = orderDoc.data()!;
      // ⭐ s_items kullan (s_products yerine)
      final items = orderData['s_items'] as List<dynamic>?;

      if (items == null || items.isEmpty) {
        _showErrorDialog(context, 'Sipariş içeriği bulunamadı');
        return;
      }

      // Dialog göster
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF45A049)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shopping_bag,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Sipariş İçeriği',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final itemData = items[index] as Map<String, dynamic>;
                      final item = itemData['item'] as Map<String, dynamic>? ?? {};
                      
                      // ⭐ Item bilgileri
                      final name = item['name'] ?? 'Ürün Adı Yok';
                      final quantity = item['qty'] ?? 1;
                      final unitPrice = (item['unitPrice'] ?? 0.0) as num;
                      final lineTotal = (item['lineTotal'] ?? unitPrice * quantity) as num;
                      final note = item['note'] as String?;
                      
                      // ⭐ Extras ve Options
                      final extras = itemData['extras'] as List<dynamic>? ?? [];
                      final options = itemData['options'] as List<dynamic>? ?? [];
                      final removed = itemData['removed'] as List<dynamic>? ?? [];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Miktar badge
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      quantity.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Ürün adı ve fiyat
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.toString(),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF212121),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₺${lineTotal.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            // ⭐ Not varsa göster
                            if (note != null && note.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.note, size: 16, color: Colors.orange.shade700),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        note,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange.shade900,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            
                            // ⭐ Options varsa göster
                            if (options.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: options.map<Widget>((option) {
                                  final opt = option as Map<String, dynamic>;
                                  final choice = opt['choice'] ?? '';
                                  final price = (opt['price'] ?? 0.0) as num;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.blue.shade200,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      '$choice${price > 0 ? ' (+₺${price.toStringAsFixed(2)})' : ''}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                            
                            // ⭐ Extras varsa göster
                            if (extras.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: extras.map<Widget>((extra) {
                                  final ext = extra as Map<String, dynamic>;
                                  final choice = ext['choice'] ?? '';
                                  final price = (ext['price'] ?? 0.0) as num;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.green.shade200,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      '$choice${price > 0 ? ' (+₺${price.toStringAsFixed(2)})' : ''}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade900,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                            
                            // ⭐ Removed varsa göster
                            if (removed.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: removed.map<Widget>((rem) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.close, size: 12, color: Colors.red.shade700),
                                        const SizedBox(width: 4),
                                        Text(
                                          rem.toString(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.red.shade900,
                                            decoration: TextDecoration.lineThrough,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Toplam:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '₺${widget.order.ssPaycount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      _showErrorDialog(context, 'Hata: $e');
    }
  }

  /// ❌ Hata Dialogu
  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Hata'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}

/// 📱 NFC Kart Okutma Dialog Widget
class _NfcCardReadingDialog extends StatefulWidget {
  @override
  State<_NfcCardReadingDialog> createState() => _NfcCardReadingDialogState();
}

class _NfcCardReadingDialogState extends State<_NfcCardReadingDialog> {
  bool _isReading = true;
  bool _isSuccess = false;
  
  @override
  void initState() {
    super.initState();
    // Animasyon başlat - 2 saniye sonra başarılı göster
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _isReading = false;
          _isSuccess = true;
        });
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // NFC ikonu ve animasyon
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: _isReading 
                  ? Colors.blue.shade100 
                  : (_isSuccess ? Colors.green.shade100 : Colors.grey.shade100),
              shape: BoxShape.circle,
              border: Border.all(
                color: _isReading 
                    ? Colors.blue 
                    : (_isSuccess ? Colors.green : Colors.grey),
                width: 3,
              ),
            ),
            child: Icon(
              Icons.nfc,
              size: 60,
              color: _isReading 
                  ? Colors.blue 
                  : (_isSuccess ? Colors.green : Colors.grey),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Durum mesajı
          Text(
            _isReading 
                ? 'Kart Okunuyor...' 
                : (_isSuccess ? 'Kart Okundu!' : 'Hata'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _isReading 
                  ? Colors.blue 
                  : (_isSuccess ? Colors.green : Colors.red),
            ),
          ),
          
          const SizedBox(height: 12),
          
          Text(
            _isReading 
                ? 'Lütfen kartı telefonun arkasına yaklaştırın' 
                : (_isSuccess ? 'Ödeme başarıyla alındı' : 'Kart okunamadı'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          
          if (_isReading) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
          
          if (_isSuccess) ...[
            const SizedBox(height: 24),
            Icon(
              Icons.check_circle,
              size: 48,
              color: Colors.green,
            ),
          ],
        ],
      ),
      actions: [
        if (_isSuccess)
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 12,
              ),
            ),
            child: const Text(
              'Tamam',
              style: TextStyle(color: Colors.white),
            ),
          ),
      ],
    );
  }
}
