import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/order_model.dart';
import '../services/firebase_service.dart';
import '../services/platform_api_service.dart';
import '../services/sms_service.dart';
import '../services/javipos_api_service.dart';
import '../services/sepettakip_status_service.dart';
import '../utils/payment_change_logger.dart';
import '../utils/network_utils.dart';
import '../services/courier_cash_transaction_service.dart';

/// Sipariş Detay Modal (Bottom Sheet)
/// React Native Page_Center.js karşılığı
class OrderBottomSheet extends StatefulWidget {
  final OrderModel order;

  const OrderBottomSheet({super.key, required this.order});

  @override
  State<OrderBottomSheet> createState() => _OrderBottomSheetState();
}

class _OrderBottomSheetState extends State<OrderBottomSheet> {
  bool _isProcessing = false;
  int _currentStep = 1;
  bool _paymentConfirmed = false;
  final _cashController = TextEditingController();
  final _cardController = TextEditingController();
  String _paymentMethod = 'cash';
  
  // ⏰ YENİ: Onay timeout geri sayımı
  int? _remainingTime; // Kalan süre (saniye)
  Timer? _countdownTimer;
  Timer? _buttonCountdownTimer; // ⭐ Buton countdown için
  bool _courierApprovalEnabled = false; // Kurye onay sistemi aktif mi?
  int _approvalTimeout = 120; // Varsayılan 120 saniye

  /// Online (ön ödemeli) sipariş mi? → kapıda doğrulama gerekmez
  /// "Online" kelimesi içeren tüm ödeme türleri + ssPaytype==2
  bool _isOnlinePayment() {
    if (widget.order.ssPaytype == 2) return true;
    return (widget.order.sOdemeAdi ?? '').toLowerCase().contains('online');
  }

  /// Nakit ödeme mi? → Nakit/Kart tutar doğrulaması gerekir
  bool _isCashPayment() {
    if (widget.order.ssPaytype == 0) return true;
    return (widget.order.sOdemeAdi ?? '').toLowerCase() == 'nakit';
  }

  @override
  void initState() {
    super.initState();
    _updateStep();
    _loadApprovalSettings();
    _startCountdownIfNeeded();
    _startButtonCountdownTimer(); // ⭐ Buton countdown timer'ı başlat

    // Ödeme tutarlarını doldur
    if (widget.order.ssPaytype == 0) {
      _cashController.text = widget.order.ssPaycount.toString();
      _paymentMethod = 'cash';
    } else if (widget.order.ssPaytype == 1) {
      _cardController.text = widget.order.ssPaycount.toString();
      _paymentMethod = 'card';
    }
  }

  @override
  void dispose() {
    _cashController.dispose();
    _cardController.dispose();
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

  /// Adım durumunu güncelle
  void _updateStep() {
    if (widget.order.sStat == 1) {
      setState(() => _currentStep = 3);
    } else {
      setState(() => _currentStep = 2);
    }
  }

  /// ⏰ Kurye onay ayarlarını yükle (Firestore'dan)
  Future<void> _loadApprovalSettings() async {
    try {
      final settings = await FirebaseService.getApprovalSettings(widget.order.sBay);
      if (mounted) {
        setState(() {
          _courierApprovalEnabled = settings['courier_approval_enabled'] ?? false;
          _approvalTimeout = settings['approval_timeout'] ?? 120;
        });
        print('⚙️ Kurye onay ayarları: enabled=$_courierApprovalEnabled, timeout=$_approvalTimeout');
      }
    } catch (e) {
      print('⚠️ Onay ayarları yüklenemedi: $e');
    }
  }

  /// ⏰ Countdown başlat (eğer stat 0 ve onay sistemi aktifse)
  void _startCountdownIfNeeded() {
    if (widget.order.sStat == 0 && _courierApprovalEnabled) {
      // Sipariş oluşturulma zamanından bu yana geçen süreyi hesapla
      final createdAt = widget.order.sCdate;
      if (createdAt != null) {
        final elapsed = DateTime.now().difference(createdAt).inSeconds;
        final remaining = _approvalTimeout - elapsed;
        
        if (remaining > 0) {
          setState(() => _remainingTime = remaining);
          
          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (mounted) {
              setState(() {
                if (_remainingTime != null && _remainingTime! > 0) {
                  _remainingTime = _remainingTime! - 1;
                } else {
                  timer.cancel();
                  // Timeout! Sipariş otomatik red edilsin mi?
                  print('⏰ Sipariş onay süresi doldu!');
                  _autoRejectOrder();
                }
              });
            }
          });
        } else {
          print('⏰ Sipariş onay süresi zaten dolmuş!');
          _autoRejectOrder();
        }
      }
    }
  }

  /// 🚫 Sipariş otomatik reddet (timeout)
  Future<void> _autoRejectOrder() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Sipariş onay süresi doldu'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context);
    }
  }

  /// Sipariş kabul et
  Future<void> _acceptOrder() async {
    setState(() => _isProcessing = true);

    try {
      _countdownTimer?.cancel(); // Countdown'u durdur
      await FirebaseService.acceptOrder(widget.order.docId);

      if (SepettakipStatusService.isSepettakipOrder(widget.order.sSource)) {
        unawaited(
          SepettakipStatusService.notifyAssigned(
            orderId: widget.order.sId,
            courierId: widget.order.sCourier,
          ).catchError((e) {
            print('⚠️ Sepettakip assigned bildirimi hatasi: $e');
          }),
        );
      }

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sipariş kabul edildi'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e')),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// 🚫 Sipariş reddet
  Future<void> _rejectOrder() async {
    // Onay dialogu göster
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Siparişi Reddet'),
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
      _countdownTimer?.cancel(); // Countdown'u durdur
      await FirebaseService.rejectOrder(widget.order.docId, widget.order.sCourier);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚫 Sipariş reddedildi'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e')),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// ⭐ Work'ten POS entegrasyon bilgisini çek
  Future<Map<String, dynamic>?> _getWorkPosIntegration(int workId) async {
    try {
      // 1. workId kontrolü
      if (workId <= 0) {
        print('⚠️ Work ID geçersiz: $workId');
        return null;
      }
      
      // 2. t_work dokümanını çek
      final workQuery = await FirebaseFirestore.instance
          .collection('t_work')
          .where('s_id', isEqualTo: workId)
          .limit(1)
          .get();
      
      if (workQuery.docs.isEmpty) {
        print('⚠️ Work bulunamadı: $workId');
        return null;
      }
      
      // 3. s_pos_integration kontrolü
      final workData = workQuery.docs.first.data();
      final posIntegration = workData['s_pos_integration'];
      
      if (posIntegration == null) {
        print('ℹ️ Work $workId için s_pos_integration bilgisi yok');
        return null;
      }
      
      // 4. Map kontrolü
      if (posIntegration is! Map<String, dynamic>) {
        print('⚠️ s_pos_integration map formatında değil');
        return null;
      }
      
      // 5. active kontrolü
      final active = posIntegration['active'] as bool? ?? false;
      if (!active) {
        print('ℹ️ Work $workId için POS entegrasyon aktif değil');
        return null;
      }
      
      // 6. Gerekli alanlar kontrolü
      final url = posIntegration['url'] as String?;
      final key = posIntegration['key'] as String?;
      
      if (url == null || url.isEmpty || key == null || key.isEmpty) {
        print('⚠️ Work $workId için url veya key eksik');
        return null;
      }
      
      print('✅ POS entegrasyon bilgisi bulundu: ${posIntegration['name']}');
      return posIntegration;
      
    } catch (e) {
      print('❌ POS entegrasyon bilgisi çekilirken hata: $e');
      return null; // Hata olsa bile null döndür, ana işlem devam etsin
    }
  }

  /// ⭐ URL formatını düzelt (sonunda / varsa kaldır)
  String _normalizeUrl(String url) {
    url = url.trim();
    // Sonunda / varsa kaldır
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// ⭐ POS entegrasyon API çağrısı
  Future<bool> _callPosIntegrationApi({
    required String url,
    required String apiKey,
    required String orderId,
    required int orderStatus, // 3 = Yola Çıkar, 4 = Teslim Edildi
    Map<String, dynamic>? additionalData, // order_payment gibi ek alanlar
  }) async {
    try {
      // 1. URL kontrolü
      if (url.isEmpty) {
        print('⚠️ POS entegrasyon URL boş');
        return false;
      }
      
      // 2. API Key kontrolü
      if (apiKey.isEmpty) {
        print('⚠️ POS entegrasyon API Key boş');
        return false;
      }
      
      // 3. OrderId kontrolü
      if (orderId.isEmpty) {
        print('⚠️ Order ID (s_pid) boş');
        return false;
      }
      
      // 4. Endpoint oluştur
      final normalizedUrl = _normalizeUrl(url);
      final normalizedLower = normalizedUrl.toLowerCase();
      final endpoint = normalizedLower.endsWith('/v1/couries')
          ? '$normalizedUrl/$orderId'
          : '$normalizedUrl/v1/couries/$orderId';
      
      // 5. Request body oluştur
      final bodyMap = <String, dynamic>{
        'order_status': orderStatus,
      };
      
      // 6. Ek veriler varsa ekle (order_payment gibi)
      if (additionalData != null) {
        bodyMap.addAll(additionalData);
      }
      
      final body = json.encode(bodyMap);
      
      // 7. Headers
      final headers = {
        'x-api-key': apiKey,
        'Content-Type': 'application/json',
      };
      
      // 8. POST isteği
      print('🚀 POS Entegrasyon API çağrılıyor...');
      print('   Endpoint: $endpoint');
      print('   Order ID: $orderId');
      print('   Status: $orderStatus');
      print('   Body: $body');
      
      final response = await http.post(
        Uri.parse(endpoint),
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 10));
      
      // 9. Response logla (ham + parse edilmiş)
      final rawBody = response.body.trim();
      print('📨 POS entegrasyon API dönüşü alındı');
      print('   Status Code: ${response.statusCode}');
      print('   Reason: ${response.reasonPhrase ?? "-"}');
      print('   Headers: ${response.headers}');
      if (rawBody.isEmpty) {
        print('   Body: <empty>');
      } else {
        print('   Raw Body: $rawBody');
        try {
          final decoded = json.decode(rawBody);
          print('   Parsed Body: $decoded');
        } catch (_) {
          print('   Parsed Body: <json parse edilemedi>');
        }
      }
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ POS entegrasyon API başarılı');
        return true;
      } else {
        print('⚠️ POS entegrasyon API hatası: ${response.statusCode}');
        return false;
      }
      
    } on TimeoutException catch (e) {
      print('❌ POS entegrasyon API timeout: $e');
      return false;
    } on SocketException catch (e) {
      print('❌ POS entegrasyon API ağ hatası: $e');
      return false;
    } catch (e) {
      print('❌ POS entegrasyon API çağrısı hatası: $e');
      return false; // Hata olsa bile ana işlem devam etsin
    }
  }

  /// Teslim al/Teslim et
  Future<void> _updateOrderStatus() async {
    final hasInternet = await NetworkUtils.hasInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.'),
          ),
        );
      }
      return;
    }

    if (widget.order.sStat == 0) {
      // TESLIM AL
      // Onay kontrolü (eğer onay sistemi aktifse)
      if (widget.order.sCourierAccepted == null || widget.order.sCourierAccepted == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Lütfen önce siparişi kabul edin')),
        );
        return;
      }

      setState(() => _isProcessing = true);

      try {
        // ⭐ 1. Tracking Token Oluştur
        final trackingToken = '${widget.order.sId}_${DateTime.now().millisecondsSinceEpoch}';
        
        await FirebaseService.updateOrderStatus(
          widget.order.docId,
          1,
          receivedTime: DateTime.now(),
        );

        if (SepettakipStatusService.isSepettakipOrder(widget.order.sSource)) {
          unawaited(
            SepettakipStatusService.notifyPickedUp(
              orderId: widget.order.sId,
              courierId: widget.order.sCourier,
            ).catchError((e) {
              print('⚠️ Sepettakip picked_up bildirimi hatasi: $e');
            }),
          );
        }

        // Kurye için yeni alan: teslim alındığında yolda=true
        await FirebaseService.updateCourierOnTheWay(widget.order.sCourier, true);

        // ⭐ 2. Tracking token'ı Firestore'a kaydet
        await FirebaseFirestore.instance
            .collection('t_orders')
            .doc(widget.order.docId)
            .update({'s_tracking_token': trackingToken});

        // Platform API çağrısı (Teslim Al)
        if (widget.order.sOrderscr >= 1 && widget.order.sOrderscr <= 4) {
          await PlatformApiService.callPlatformDeliveryApi(
            platformId: widget.order.sOrderscr,
            organizationToken: widget.order.sOrganizationToken,
            orderId: widget.order.sOrderid,
          );
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

        // 📍 3. SMS GÖNDER (s_sms_template kullanarak, trackingUrl ile)
        SmsService.sendTrackingSMS(widget.order.docId, trackingToken).then((success) {
          if (success) {
            print('✅ SMS müşteriye gönderildi (s_sms_template)');
          } else {
            print('⚠️ SMS gönderilemedi (arka planda hata)');
          }
        }).catchError((error) {
          print('❌ SMS gönderim hatası: $error');
        });

        // ⭐ 4. POS Entegrasyon API çağrısı (Teslim Al - order_status = 3)
        if (widget.order.sWork > 0 && widget.order.sPid.isNotEmpty) {
          final posIntegration = await _getWorkPosIntegration(widget.order.sWork);
          if (posIntegration != null) {
            final url = posIntegration['url'] as String;
            final key = posIntegration['key'] as String;
            final orderId = widget.order.sPid;
            
            // Async çağrı (await etmeden, arka planda çalışsın)
            _callPosIntegrationApi(
              url: url,
              apiKey: key,
              orderId: orderId,
              orderStatus: 3, // Yola Çıkar
              additionalData: null,
            ).then((success) {
              if (success) {
                print('✅ POS entegrasyon API başarılı (Teslim Al)');
              } else {
                print('⚠️ POS entegrasyon API başarısız (Teslim Al) - Ana işlem devam ediyor');
              }
            }).catchError((error) {
              print('❌ POS entegrasyon API hatası (Teslim Al): $error');
            });
          } else {
            print('ℹ️ Bu işletme için POS entegrasyon yok, atlanıyor');
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Sipariş teslim alındı!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Hata: $e')),
          );
        }
      } finally {
        setState(() => _isProcessing = false);
      }
    } else {
      // TESLİM ET
      // 3 dakika kontrolü
      if (widget.order.sReceived != null) {
        final timeDiff = DateTime.now().difference(widget.order.sReceived!);
        if (timeDiff.inMinutes < 3) {
          final remaining = 3 - timeDiff.inMinutes;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Teslim edebilmek için $remaining dakika daha beklemeniz gerekiyor.')),
          );
          return;
        }
      }

      // Online (ön ödemeli) ise direkt teslim et
      if (_isOnlinePayment()) {
        setState(() => _isProcessing = true);

        try {
          await FirebaseService.updateOrderStatus(
            widget.order.docId,
            2,
            deliveredTime: DateTime.now(),
          );

          if (SepettakipStatusService.isSepettakipOrder(widget.order.sSource)) {
            unawaited(
              SepettakipStatusService.notifyDelivered(
                orderId: widget.order.sId,
                courierId: widget.order.sCourier,
              ).catchError((e) {
                print('⚠️ Sepettakip delivered bildirimi hatasi: $e');
              }),
            );
          }

          // Kurye için yeni alan: teslim sonrası s_stat=1 sipariş kaldı mı kontrol et
          await FirebaseService.refreshCourierOnTheWayFromOrders(widget.order.sCourier);

          // Platform API çağrısı (Teslim Et - Online)
          if (widget.order.sOrderscr >= 1 && widget.order.sOrderscr <= 4) {
            await PlatformApiService.callPlatformDeliveryApi(
              platformId: widget.order.sOrderscr,
              organizationToken: widget.order.sOrganizationToken,
              orderId: widget.order.sOrderid,
            );
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
            print('⚠️ JaviPos API (Teslim Et - Online): JaviPosid veya ClientId eksik');
          }

          // ⭐ POS Entegrasyon API çağrısı (Teslim Et - Online - order_status = 4)
          if (widget.order.sWork > 0 && widget.order.sPid.isNotEmpty) {
            final posIntegration = await _getWorkPosIntegration(widget.order.sWork);
            if (posIntegration != null) {
              final url = posIntegration['url'] as String;
              final key = posIntegration['key'] as String;
              final orderId = widget.order.sPid;
              
              // Async çağrı (await etmeden, arka planda çalışsın)
              _callPosIntegrationApi(
                url: url,
                apiKey: key,
                orderId: orderId,
                orderStatus: 4, // Teslim Edildi
                additionalData: {
                  'order_payment': null,
                },
              ).then((success) {
                if (success) {
                  print('✅ POS entegrasyon API başarılı (Teslim Et - Online)');
                } else {
                  print('⚠️ POS entegrasyon API başarısız (Teslim Et - Online) - Ana işlem devam ediyor');
                }
              }).catchError((error) {
                print('❌ POS entegrasyon API hatası (Teslim Et - Online): $error');
              });
            } else {
              print('ℹ️ Bu işletme için POS entegrasyon yok, atlanıyor');
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Sipariş teslim edildi!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('❌ Hata: $e')),
            );
          }
        } finally {
          setState(() => _isProcessing = false);
        }
      } else {
        // Kapıda ödeme - doğrulama gerekli
        if (!_paymentConfirmed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lütfen ödemeyi doğrulayın')),
          );
          return;
        }

        // Nakit ise tutar doğrulaması
        double cash = 0;
        double card = 0;
        if (_isCashPayment()) {
          cash = double.tryParse(_cashController.text) ?? 0;
          card = double.tryParse(_cardController.text) ?? 0;
          final total = cash + card;
          if (total != widget.order.ssPaycount) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'Toplam Ödeme ₺${widget.order.ssPaycount} olmalıdır.')),
            );
            return;
          }
        }

        setState(() => _isProcessing = true);

        try {
          final deliveredTime = DateTime.now();

          if (_isCashPayment()) {
            // ── NAKİT: Tutar doğrula, logla, Firestore güncelle ──────────
            final oldPayment = {
              'cash': widget.order.ssPaytype == 0 ? widget.order.ssPaycount : 0.0,
              'card': widget.order.ssPaytype == 1 ? widget.order.ssPaycount : 0.0,
              'online': 0.0,
              'type': widget.order.ssPaytype,
              'total': widget.order.ssPaycount,
            };
            final newPayment = {
              'cash': cash,
              'card': card,
              'online': 0.0,
              'type': _paymentMethod == 'cash' ? 0 : 1,
              'total': cash + card,
            };
            if (oldPayment['type'] != newPayment['type'] ||
                oldPayment['total'] != newPayment['total'] ||
                oldPayment['cash'] != newPayment['cash'] ||
                oldPayment['card'] != newPayment['card']) {
              await PaymentChangeLogger.logPaymentChange(
                orderId: widget.order.docId,
                courierId: widget.order.sCourier,
                orderPid: widget.order.sPid,
                oldPayment: oldPayment,
                newPayment: newPayment,
              );
            }
            await FirebaseService.updateOrderStatus(
              widget.order.docId,
              2,
              deliveredTime: deliveredTime,
              paymentData: {
                's_pay.ss_paycount': _paymentMethod == 'cash' ? cash : card,
                's_pay.ss_paycountdiv': _paymentMethod == 'cash' ? card : cash,
                's_pay.payType': _paymentMethod == 'cash' ? 0 : 1,
                if (widget.order.ssPaytype != 3) 's_pay.ss_paytype': _paymentMethod == 'cash' ? 0 : 1,
              },
            );
            if (SepettakipStatusService.isSepettakipOrder(widget.order.sSource)) {
              unawaited(
                SepettakipStatusService.notifyDelivered(
                  orderId: widget.order.sId,
                  courierId: widget.order.sCourier,
                ).catchError((e) {
                  print('⚠️ Sepettakip delivered bildirimi hatasi: $e');
                }),
              );
            }
            // Nakit transaction kaydı
            if (cash > 0) {
              await CourierCashTransactionService.createCashTransaction(
                orderId: widget.order.docId,
                orderPid: widget.order.sPid,
                courierId: widget.order.sCourier,
                bayId: widget.order.sBay,
                workId: widget.order.sWork > 0 ? widget.order.sWork : null,
                originalPaymentType: widget.order.ssPaytype,
                finalPaymentType: _paymentMethod == 'cash' ? 0 : 1,
                cashAmount: cash,
                orderDeliveredAt: deliveredTime,
              );
            }
          } else {
            // ── DİĞER KAPIDA ÖDEME (Multinet, Sodexo, Ticket, SetCard vb.) ──
            // Ödeme verisi değiştirilmez, sadece durum güncellenir
            await FirebaseService.updateOrderStatus(
              widget.order.docId,
              2,
              deliveredTime: deliveredTime,
              paymentData: {},
            );
            if (SepettakipStatusService.isSepettakipOrder(widget.order.sSource)) {
              unawaited(
                SepettakipStatusService.notifyDelivered(
                  orderId: widget.order.sId,
                  courierId: widget.order.sCourier,
                ).catchError((e) {
                  print('⚠️ Sepettakip delivered bildirimi hatasi: $e');
                }),
              );
            }
          }

          // Platform API çağrısı (Teslim Et - Kapıda Ödeme)
          // ⭐ JaviPos API çağrısı (Teslim Et - Status: "4" = Teslim Edildi)
          if (widget.order.javiPosid != null && widget.order.javiPosid!.isNotEmpty &&
              widget.order.clientId != null && widget.order.clientId!.isNotEmpty) {
            await JaviPosApiService.updateOrderStatus(
              javiPosid: widget.order.javiPosid!,
              clientId: widget.order.clientId!,
              status: '4', // Teslim Edildi
            );
          } else {
            print('⚠️ JaviPos API (Teslim Et - Kapıda Ödeme): JaviPosid veya ClientId eksik');
          }

          // Platform API çağrısı (Teslim Et - Kapıda Ödeme)
          if (widget.order.sOrderscr >= 1 && widget.order.sOrderscr <= 4) {
            await PlatformApiService.callPlatformDeliveryApi(
              platformId: widget.order.sOrderscr,
              organizationToken: widget.order.sOrganizationToken,
              orderId: widget.order.sOrderid,
            );
          }

          // ⭐ JaviPos API çağrısı (Teslim Et - Kapıda Ödeme - Status: "4" = Teslim Edildi)
          if (widget.order.javiPosid != null && widget.order.javiPosid!.isNotEmpty &&
              widget.order.clientId != null && widget.order.clientId!.isNotEmpty) {
            await JaviPosApiService.updateOrderStatus(
              javiPosid: widget.order.javiPosid!,
              clientId: widget.order.clientId!,
              status: '4', // Teslim Edildi
            );
          } else {
            print('⚠️ JaviPos API (Teslim Et - Kapıda Ödeme): JaviPosid veya ClientId eksik');
          }

          // ⭐ POS Entegrasyon API çağrısı (Teslim Et - Kapıda Ödeme - order_status = 4)
          if (widget.order.sWork > 0 && widget.order.sPid.isNotEmpty) {
            final posIntegration = await _getWorkPosIntegration(widget.order.sWork);
            if (posIntegration != null) {
              final url = posIntegration['url'] as String;
              final key = posIntegration['key'] as String;
              final orderId = widget.order.sPid;
              
              // Async çağrı (await etmeden, arka planda çalışsın)
              _callPosIntegrationApi(
                url: url,
                apiKey: key,
                orderId: orderId,
                orderStatus: 4, // Teslim Edildi
                additionalData: {
                  'order_payment': null,
                },
              ).then((success) {
                if (success) {
                  print('✅ POS entegrasyon API başarılı (Teslim Et - Kapıda Ödeme)');
                } else {
                  print('⚠️ POS entegrasyon API başarısız (Teslim Et - Kapıda Ödeme) - Ana işlem devam ediyor');
                }
              }).catchError((error) {
                print('❌ POS entegrasyon API hatası (Teslim Et - Kapıda Ödeme): $error');
              });
            } else {
              print('ℹ️ Bu işletme için POS entegrasyon yok, atlanıyor');
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Sipariş teslim edildi!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('❌ Hata: $e')),
            );
          }
        } finally {
          setState(() => _isProcessing = false);
        }
      }
    }
  }

  /// Haritayı aç
  Future<void> _openMap(double lat, double lng, String label) async {
    print('🗺️ Harita açılıyor: $label ($lat, $lng)');
    
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
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Harita uygulaması açılamadı')),
          );
        }
      }
    } catch (e) {
      print('❌ Harita açma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e')),
        );
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

  /// Telefon aç (Otomatik DTMF ile)
  Future<void> _openPhone(String phone) async {
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Telefon numarası bulunamadı')),
      );
      return;
    }
    
    // ⭐ TRENDYOL MANTIĞI: Virgülden sonra PIN kodu otomatik girilecek
    // Örnek: "02123653403,10709185058" → "tel:02123653403,,10709185058"
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d,]'), '');
    
    // Tek virgül varsa çift virgül yap (DTMF için 2 saniye bekletme)
    if (cleanPhone.contains(',') && !cleanPhone.contains(',,')) {
      cleanPhone = cleanPhone.replaceFirst(',', ',,');
    }
    
    // 0 ile başlamıyorsa ekle (virgülden önceki kısım için)
    if (cleanPhone.contains(',')) {
      final parts = cleanPhone.split(',');
      String mainPhone = parts[0];
      if (!mainPhone.startsWith('0') && mainPhone.length >= 10) {
        mainPhone = '0$mainPhone';
      }
      cleanPhone = '$mainPhone,${parts.skip(1).join(',')}';
    } else if (!cleanPhone.startsWith('0') && cleanPhone.length >= 10) {
      cleanPhone = '0$cleanPhone';
    }
    
    print('📞 Aranıyor (Otomatik DTMF): $cleanPhone');
    print('   Orijinal: $phone');
    
    final url = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Telefon uygulaması açılamadı')),
          );
        }
      }
    } catch (e) {
      print('❌ Telefon açma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Onay sistemi kontrolü (onay bekliyorsa)
    final bool isWaitingForApproval =
        widget.order.sCourierAccepted == null && widget.order.sStat == 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.all(20),
                color: Colors.blue,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sipariş Detayları',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // İçerik
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(18),
                  children: [
                    // Durum timeline
                    _buildStatusTimeline(),

                    const SizedBox(height: 20),

                    // Ödeme doğrulama (stat=1 ve online ödeme DEĞİLSE)
                    if (widget.order.sStat == 1 && !_isOnlinePayment())
                      _buildPaymentConfirmation(),

                    // Restoran kartı
                    _buildRestaurantCard(),

                    const SizedBox(height: 12),

                    // Müşteri kartı
                    _buildCustomerCard(),

                    const SizedBox(height: 12),

                    // Sipariş detayları kartı
                    _buildOrderDetailsCard(),

                    const SizedBox(height: 100),
                  ],
                ),
              ),

              // Footer (onay veya teslim butonları)
              Container(
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
                child: isWaitingForApproval
                    ? _buildApprovalButtons()
                    : _buildDeliveryButton(),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Durum timeline
  Widget _buildStatusTimeline() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildTimelineStep('Oluştu', 1, true),
            _buildTimelineLine(_currentStep >= 2),
            _buildTimelineStep('Hazır', 2, _currentStep >= 2),
            _buildTimelineLine(_currentStep >= 3),
            _buildTimelineStep('Alındı', 3, _currentStep >= 3),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineStep(String label, int step, bool active) {
    return Column(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: active ? Colors.blue : Colors.grey[300],
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? Colors.black : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineLine(bool active) {
    return Expanded(
      child: Container(
        height: 3,
        color: active ? Colors.blue : Colors.grey[300],
        margin: const EdgeInsets.only(bottom: 25),
      ),
    );
  }

  /// Ödeme doğrulama
  /// - Nakit: Nakit/Kart radio + tutar alanları + onay
  /// - Diğer kapıda ödeme (Multinet, Sodexo, Ticket vb.): Ödeme adı + onay
  Widget _buildPaymentConfirmation() {
    final payLabel = (widget.order.sOdemeAdi?.isNotEmpty == true)
        ? widget.order.sOdemeAdi!
        : widget.order.ssPaytype == 1
            ? 'Kredi Kartı'
            : 'Kapıda Ödeme';

    if (_isCashPayment()) {
      // ── NAKİT MODU ──────────────────────────────────────────────────
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ödeme Doğrula',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Radio<String>(
                    value: 'cash',
                    groupValue: _paymentMethod,
                    onChanged: (value) {
                      setState(() {
                        _paymentMethod = value!;
                        final total = (double.tryParse(_cashController.text) ?? 0) +
                            (double.tryParse(_cardController.text) ?? 0);
                        _cashController.text = total.toString();
                        _cardController.text = '0';
                      });
                    },
                  ),
                  const Text('Nakit'),
                  const SizedBox(width: 20),
                  Radio<String>(
                    value: 'card',
                    groupValue: _paymentMethod,
                    onChanged: (value) {
                      setState(() {
                        _paymentMethod = value!;
                        final total = (double.tryParse(_cashController.text) ?? 0) +
                            (double.tryParse(_cardController.text) ?? 0);
                        _cardController.text = total.toString();
                        _cashController.text = '0';
                      });
                    },
                  ),
                  const Text('Kart'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cashController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nakit',
                        prefixIcon: Icon(Icons.money),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _cardController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Kart',
                        prefixIcon: Icon(Icons.credit_card),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _paymentConfirmed,
                onChanged: (value) => setState(() => _paymentConfirmed = value!),
                title: const Text('Ödemeyi Doğruluyorum'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      );
    }

    // ── DİĞER KAPIDA ÖDEME MODU (Multinet, Sodexo, Ticket, SetCard vb.) ──
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ödeme Doğrula',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payment, color: Color(0xFF2563EB), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ödeme Türü',
                          style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                        ),
                        Text(
                          payLabel,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₺${widget.order.ssPaycount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _paymentConfirmed,
              onChanged: (value) => setState(() => _paymentConfirmed = value!),
              title: Text('$payLabel ödemesini müşteriden aldım'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }

  /// Restoran kartı
  Widget _buildRestaurantCard() {
    // Adres ve aksiyonlar her zaman gösterilsin
    final hideAddress = false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Restoran Detayı',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (widget.order.ssLocationWork != null) {
                          _openMap(
                            widget.order.ssLocationWork!['latitude'],
                            widget.order.ssLocationWork!['longitude'],
                            'Restoran',
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Konum bilgisi yok')),
                          );
                        }
                      },
                      icon: const Icon(Icons.location_on, color: Colors.green),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.green.withOpacity(0.1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _openPhone(widget.order.sPhonework),
                      icon: const Icon(Icons.phone, color: Colors.blue),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.store, color: Colors.blue),
              title: const Text('Restoran Adı'),
              subtitle: Text(widget.order.sNameWork.isNotEmpty ? widget.order.sNameWork : 'İşletme'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.green),
              title: const Text('Adres'),
              subtitle: Text(widget.order.sWorkAdres.isEmpty ? 'Adres bulunamadı' : widget.order.sWorkAdres),
            ),
          ],
        ),
      ),
    );
  }

  /// Müşteri kartı
  Widget _buildCustomerCard() {
    // Her zaman göster
    final hideAddress = false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Müşteri Detayı',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (widget.order.ssLoc != null) {
                          _openMap(
                            widget.order.ssLoc!['latitude'],
                            widget.order.ssLoc!['longitude'],
                            'Müşteri',
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Konum bilgisi yok')),
                          );
                        }
                      },
                      icon: const Icon(Icons.location_on, color: Colors.red),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => _openPhone(widget.order.ssPhone),
                      icon: const Icon(Icons.phone, color: Colors.blue),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.blue),
              title: const Text('Müşteri Adı'),
              subtitle: Text(widget.order.ssFullname),
            ),
            ListTile(
              leading: const Icon(Icons.location_on, color: Colors.red),
              title: const Text('Adres'),
              subtitle: Text(widget.order.ssAdres.isEmpty ? 'Adres bulunamadı' : widget.order.ssAdres),
            ),
          ],
        ),
      ),
    );
  }

  /// Sipariş detayları kartı
  Widget _buildOrderDetailsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sipariş Detayı',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.confirmation_number, color: Colors.blue),
              title: const Text('Sipariş No'),
              subtitle: Text('#${widget.order.sId}'),
            ),
            ListTile(
              leading: const Icon(Icons.note, color: Colors.orange),
              title: const Text('Açıklama'),
              subtitle: Text(widget.order.ssNote.isEmpty ? 'Yok' : widget.order.ssNote),
            ),
            ListTile(
              leading: const Icon(Icons.navigation, color: Colors.red),
              title: const Text('Tahmini Mesafe'),
              subtitle: Text('${widget.order.sDinstance} KM'),
            ),
          ],
        ),
      ),
    );
  }

  /// Onay butonları (Kabul/Reddet)
  Widget _buildApprovalButtons() {
    return Column(
      children: [
        const Text(
          '🔔 Sipariş Onayı Bekleniyor',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        // ⏰ Countdown göstergesi
        if (_remainingTime != null && _remainingTime! > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _remainingTime! > 30 ? Colors.orange : Colors.red,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${_remainingTime! ~/ 60}:${(_remainingTime! % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Bu siparişi kabul ediyor musunuz?',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _acceptOrder,
                icon: const Icon(Icons.check_circle),
                label: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('KABUL ET'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _rejectOrder,
                icon: const Icon(Icons.cancel),
                label: const Text('REDDET'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Teslim butonu
  /// ⏰ Teslim Al / Teslim Et butonu (2 dakika kontrolü ile)
  Widget _buildDeliveryButtonWithTimeCheck(String buttonText) {
    // ⭐ 2 dakika kontrolü
    bool isButtonEnabled = true;
    int? remainingSeconds;
    String? waitMessage;

    if (widget.order.sStat == 1) {
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

    return ElevatedButton.icon(
      onPressed: (_isProcessing || !isButtonEnabled) ? null : _updateOrderStatus,
      icon: _isProcessing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.check_circle),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(buttonText),
          if (!isButtonEnabled && waitMessage != null)
            Text(
              '⏰ $waitMessage',
              style: const TextStyle(fontSize: 10),
            ),
        ],
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isButtonEnabled ? Colors.blue : Colors.grey,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildDeliveryButton() {
    final paymentTypeText = (widget.order.sOdemeAdi?.isNotEmpty == true)
        ? widget.order.sOdemeAdi!
        : widget.order.ssPaytype == 0
            ? 'Kapıda Nakit'
            : widget.order.ssPaytype == 1
                ? 'Kapıda Kredi'
                : 'Online Ödeme';

    final buttonText = widget.order.sStat == 0 ? 'TESLİM AL' : 'TESLİM ET';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.payment, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  const Text('Ödeme Türü', style: TextStyle(fontSize: 12)),
                ],
              ),
              Text(
                paymentTypeText,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.attach_money, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  const Text('Tutar', style: TextStyle(fontSize: 12)),
                ],
              ),
              Text(
                '₺${widget.order.ssPaycount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _buildDeliveryButtonWithTimeCheck(buttonText),
      ],
    );
  }
}

