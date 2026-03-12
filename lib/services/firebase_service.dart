import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'location_service.dart';

/// Firebase Firestore Servisi
/// React Native firebase.js karşılığı
class FirebaseService {
  static FirebaseFirestore get db => FirebaseFirestore.instance;

  /// Firebase'i başlat
  static Future<void> initialize() async {
    await Firebase.initializeApp();
  }

  /// Kurye login (t_courier tablosundan)
  static Future<Map<String, dynamic>?> loginCourier(
      String phone, String password) async {
    try {
      print('🔐 Login denemesi başladı');
      print('📱 Phone: "$phone"');
      print('🔑 Password: "${password.replaceAll(RegExp('.'), '*')}"');

      // Önce tüm kuryerleri çek ve kontrol et (debug için)
      final allCouriers = await db.collection('t_courier').get();
      print('📊 Toplam kurye sayısı: ${allCouriers.docs.length}');
      
      if (allCouriers.docs.isNotEmpty) {
        print('📝 İlk kurye örneği:');
        final firstCourier = allCouriers.docs.first.data();
        print('   s_phone: "${firstCourier['s_phone']}" (${firstCourier['s_phone'].runtimeType})');
        print('   s_password: "${firstCourier['s_password']}" (${firstCourier['s_password'].runtimeType})');
        print('   s_id: ${firstCourier['s_id']}');
      }

      final querySnapshot = await db
          .collection('t_courier')
          .where('s_phone', isEqualTo: phone)
          .where('s_password', isEqualTo: password)
          .get();

      print('🔍 Sorgu sonucu: ${querySnapshot.docs.length} kullanıcı bulundu');

      if (querySnapshot.docs.isEmpty) {
        // Alternatif: Sadece telefon ile ara
        final phoneOnlyQuery = await db
            .collection('t_courier')
            .where('s_phone', isEqualTo: phone)
            .get();
        
        if (phoneOnlyQuery.docs.isEmpty) {
          print('❌ Bu telefon numarasıyla kullanıcı bulunamadı');
        } else {
          print('⚠️ Telefon numarası doğru ama şifre yanlış');
        }
        return null;
      }

      final userData = querySnapshot.docs.first.data();
      userData['docId'] = querySnapshot.docs.first.id;

      print('✅ Login başarılı: ${userData['s_id']}');
      return userData;
    } catch (e) {
      print('❌ Login hatası: $e');
      print('Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  /// Siparişleri dinle (Real-time)
  /// s_stat: 0 = Hazırlandı (Alınacak), 4 = Hazırlanıyor, 1 = Teslim Alındı (Yolda), 2 = Teslim Edildi, 3 = İptal
  /// NOT: orderBy client-side yapılıyor (Firestore index hazır olana kadar)
  static Stream<List<Map<String, dynamic>>> watchOrders(int courierId) {
    print('👀 Siparişler dinleniyor: Kurye ID = $courierId');

    return db
        .collection('t_orders')
        .where('s_courier', isEqualTo: courierId)
        .where('s_stat', whereIn: [0, 1, 4]) // 0=Hazırlandı, 1=Yolda, 4=Hazırlanıyor
        // TODO: Index hazır olunca uncomment et -> .orderBy('s_cdate', descending: true)
        .snapshots()
        .map((snapshot) {
      print('📦 Aktif sipariş sayısı (filtrelemeden önce): ${snapshot.docs.length}');
      
      final orders = snapshot.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();
      
      // Filtreleme: s_stat 0, 1 veya 4 olan siparişler (zaten whereIn ile filtrelenmiş)
      final filteredOrders = orders.where((order) {
        final sStat = order['s_stat'] as int? ?? 0;
        return sStat == 0 || sStat == 1 || sStat == 4;
      }).toList();
      
      print('📦 Filtrelenmiş aktif sipariş sayısı: ${filteredOrders.length}');
      
      // Client-side sıralama (geçici - index hazır olana kadar)
      filteredOrders.sort((a, b) {
        final aStat = a['s_stat'] as int? ?? 0;
        final bStat = b['s_stat'] as int? ?? 0;
        
        // Önce stat'e göre sırala (4=Hazırlanıyor, 0=Hazır, 1=Yolda)
        if (aStat != bStat) {
          // 4 (Hazırlanıyor) en önce, sonra 0 (Hazır), sonra 1 (Yolda)
          final statOrder = {4: 0, 0: 1, 1: 2};
          final aOrder = statOrder[aStat] ?? 99;
          final bOrder = statOrder[bStat] ?? 99;
          if (aOrder != bOrder) {
            return aOrder.compareTo(bOrder);
          }
        }
        
        // Aynı stat ise tarihe göre sırala
        final aDate = a['s_cdate'] as Timestamp?;
        final bDate = b['s_cdate'] as Timestamp?;
        if (aDate == null || bDate == null) return 0;
        return bDate.compareTo(aDate); // Yeniden eskiye
      });
      
      return filteredOrders;
    }).handleError((error) {
      print('❌ Sipariş dinleme hatası: $error');
      return <Map<String, dynamic>>[];
    });
  }

  /// Sipariş statü ismi (debug için)
  static String _getStatName(int? stat) {
    switch (stat) {
      case 0:
        return 'Hazırlandı (Alınacak)';
      case 1:
        return 'Teslim Alındı (Yolda)';
      case 2:
        return 'Teslim Edildi';
      case 3:
        return 'İptal/Reddedildi';
      case 4:
        return 'Hazırlanıyor';
      default:
        return 'Bilinmeyen ($stat)';
    }
  }

  /// Sipariş durumunu güncelle
  static Future<void> updateOrderStatus(
    String orderId,
    int newStatus, {
    DateTime? receivedTime,
    DateTime? deliveredTime,
    Map<String, dynamic>? paymentData,
  }) async {
    try {
      final updateData = <String, dynamic>{'s_stat': newStatus};

      if (receivedTime != null) {
        updateData['s_received'] = Timestamp.fromDate(receivedTime);
      }

      if (deliveredTime != null) {
        updateData['s_delivered'] = Timestamp.fromDate(deliveredTime);
        updateData['s_ddate'] = Timestamp.fromDate(deliveredTime); // ⭐ Teslim tarihi (s_ddate)
      }

      if (paymentData != null) {
        updateData.addAll(paymentData);
      }

      await db.collection('t_orders').doc(orderId).update(updateData);

      print('✅ Sipariş durumu güncellendi: $orderId -> status: $newStatus');
    } catch (e) {
      print('❌ Sipariş güncelleme hatası: $e');
      rethrow;
    }
  }

  /// Sipariş kabul et
  static Future<void> acceptOrder(String orderId) async {
    try {
      await db.collection('t_orders').doc(orderId).update({
        's_courier_accepted': true,
        's_courier_response_time': Timestamp.now(),
      });
      print('✅ Sipariş kabul edildi: $orderId');
    } catch (e) {
      print('❌ Sipariş kabul hatası: $e');
      rethrow;
    }
  }

  /// Kurye onay ayarlarını getir (t_bay koleksiyonundan)
  static Future<Map<String, dynamic>> getApprovalSettings(int bayId) async {
    try {
      final querySnapshot = await db
          .collection('t_bay')
          .where('s_id', isEqualTo: bayId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        print('⚠️ Bay bulunamadı: $bayId');
        return {
          'courier_approval_enabled': false,
          'approval_timeout': 120,
        };
      }

      final bayData = querySnapshot.docs.first.data();
      final settings = bayData['s_settingcur'] as Map<String, dynamic>?;

      return {
        'courier_approval_enabled': settings?['ss_courier_approval'] ?? false,
        'approval_timeout': settings?['ss_approval_timeout'] ?? 120,
      };
    } catch (e) {
      print('❌ Onay ayarları getirme hatası: $e');
      return {
        'courier_approval_enabled': false,
        'approval_timeout': 120,
      };
    }
  }

  /// Sipariş reddet
  static Future<void> rejectOrder(String orderId, int courierId) async {
    try {
      final orderDoc = await db.collection('t_orders').doc(orderId).get();
      final orderData = orderDoc.data();

      final rejectedBy = List<int>.from(orderData?['s_rejected_by_couriers'] ?? []);
      rejectedBy.add(courierId);

      await db.collection('t_orders').doc(orderId).update({
        's_courier_accepted': false,
        's_courier_response_time': Timestamp.now(),
        's_courier': 0, // Siparişi serbest bırak
        's_rejected_by_couriers': rejectedBy,
      });

      print('🚫 Sipariş reddedildi: $orderId (Kurye: $courierId)');
    } catch (e) {
      print('❌ Sipariş red hatası: $e');
      rethrow;
    }
  }

  /// Kuryenin konumunu güncelle (Firestore'a)
  static Future<void> updateCourierLocation(
    int courierId,
    double latitude,
    double longitude,
  ) async {
    try {
      final querySnapshot = await db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        await querySnapshot.docs.first.reference.update({
          's_loc': {
            'latitude': latitude,
            'longitude': longitude,
          },
          's_loc_updated': Timestamp.now(),
        });
      }
    } catch (e) {
      print('❌ Konum güncelleme hatası: $e');
    }
  }

  /// Kurye bilgilerini ID ile getir
  static Future<Map<String, dynamic>?> getCourierById(int courierId) async {
    try {
      final querySnapshot = await db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      final data = querySnapshot.docs.first.data();
      data['docId'] = querySnapshot.docs.first.id;
      return data;
    } catch (e) {
      print('❌ Kurye bilgisi alma hatası: $e');
      return null;
    }
  }

  /// FCM token güncelle (Flutter için FCM, React Native için Expo)
  static Future<void> updateFCMToken(int courierId, String token) async {
    try {
      final querySnapshot = await db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // Hem expoPushToken hem fcmToken field'larına kaydet
        // Backend her iki field'ı da kontrol edebilir
        await querySnapshot.docs.first.reference.update({
          'expoPushToken': token,    // React Native ile uyumluluk için
          'fcmToken': token,          // Flutter FCM token
          's_notification': token,    // Genel field
        });
        print('✅ FCM token güncellendi (expoPushToken + fcmToken): $courierId');
        print('   Token: ${token.substring(0, 30)}...');
      }
    } catch (e) {
      print('❌ FCM token güncelleme hatası: $e');
    }
  }

  /// ⭐ Bugünkü teslim edilen sipariş sayısını getir
  /// Index: s_courier + s_stat + s_ddate (ASCENDING)
  static Future<int> getDeliveredOrdersCountToday(
    int courierId,
    DateTime startOfDay,
  ) async {
    try {
      print('📦 Bugünkü teslim edilen siparişler sorgulanıyor...');
      print('   Kurye ID: $courierId');
      print('   Başlangıç (00:00): $startOfDay');
      
      // ⭐ DOĞRU: s_courier + s_stat=2 + s_ddate (TESLİM TARİHİ)
      final snapshot = await db
          .collection('t_orders')
          .where('s_courier', isEqualTo: courierId)
          .where('s_stat', isEqualTo: 2) // 2 = Teslim edildi
          .where('s_ddate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .get();
      
      print('✅ Bugün teslim edilen: ${snapshot.docs.length} paket');
      return snapshot.docs.length;
    } catch (e) {
      print('❌ Teslim edilen paket sayısı sorgusu hatası: $e');
      return 0;
    }
  }

  /// ⭐ Vardiya süresince teslim edilen sipariş sayısını getir
  /// Index: s_courier + s_stat + s_ddate (ASCENDING) - Mevcut index kullanılabilir
  static Future<int> getDeliveredOrdersCountInShift(
    int courierId,
    DateTime shiftStartAt,
    DateTime shiftEndAt,
  ) async {
    try {
      print('📦 Vardiya süresince teslim edilen siparişler sorgulanıyor...');
      print('   Kurye ID: $courierId');
      print('   Vardiya başlangıç: $shiftStartAt');
      print('   Vardiya bitiş: $shiftEndAt');
      
      // ⭐ Index: s_courier + s_stat + s_ddate (ASCENDING) kullanılıyor
      final snapshot = await db
          .collection('t_orders')
          .where('s_courier', isEqualTo: courierId)
          .where('s_stat', isEqualTo: 2) // 2 = Teslim edildi
          .where('s_ddate', isGreaterThanOrEqualTo: Timestamp.fromDate(shiftStartAt))
          .where('s_ddate', isLessThanOrEqualTo: Timestamp.fromDate(shiftEndAt))
          .get();
      
      print('✅ Vardiya süresince teslim edilen: ${snapshot.docs.length} paket');
      return snapshot.docs.length;
    } catch (e) {
      print('❌ Vardiya süresince teslim edilen paket sayısı sorgusu hatası: $e');
      // ⭐ Index hatası olabilir, hata mesajını kontrol et
      if (e.toString().contains('index')) {
        print('⚠️ Index hatası: s_courier + s_stat + s_ddate (ASCENDING) index\'i gerekli');
      }
      return 0;
    }
  }

  /// ⭐ Bay ayarlarını çek (Genel ücretlendirme)
  static Future<Map<String, dynamic>?> getBaySettings(int bayId) async {
    try {
      print('🏢 Bay ayarları çekiliyor: Bay ID = $bayId');
      
      final bayQuery = await db
          .collection('t_bay')
          .where('s_id', isEqualTo: bayId)  // ✅ DÜZELTME: s_bay → s_id
          .limit(1)
          .get();

      if (bayQuery.docs.isEmpty) {
        print('⚠️ Bay bulunamadı: $bayId');
        return null;
      }

      final bayData = bayQuery.docs.first.data();
      final settingCur = bayData['s_settingcur'];

      if (settingCur == null) {
        print('⚠️ s_settingcur bulunamadı!');
        return null;
      }

      final settings = {
        'baseRate': settingCur['ss_curpay'] ?? 0,
        'perKmRate': settingCur['ss_kmpay'] ?? 0,
        'maxKm': settingCur['ss_maxkm'] ?? 0,
      };

      print('✅ Bay ayarları yüklendi:');
      print('   Temel Ücret: ${settings['baseRate']}₺');
      print('   KM Ücreti: ${settings['perKmRate']}₺/km');
      print('   Max KM: ${settings['maxKm']} km');

      return settings;
    } catch (e) {
      print('❌ Bay ayarları yükleme hatası: $e');
      return null;
    }
  }

  /// ⭐ Kurye özel fiyatlandırmayı çek
  static Future<Map<String, dynamic>?> getCourierPricing(int bayId, int courierId) async {
    try {
      print('💰 Özel fiyatlandırma kontrol ediliyor: Kurye ID = $courierId');
      
      final pricingQuery = await db
          .collection('t_courier_pricing')
          .where('s_bay', isEqualTo: bayId)
          .where('s_courier_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (pricingQuery.docs.isEmpty) {
        print('   ℹ️ Özel fiyatlandırma YOK, genel ayarlar kullanılacak');
        return null;
      }

      final pricingData = pricingQuery.docs.first.data();
      
      final pricing = {
        'baseRate': pricingData['baseRate'] ?? 0,
        'perKmRate': pricingData['perKmRate'] ?? 0,
        'maxKm': pricingData['maxKm'] ?? 0,
      };

      print('   ✅ ÖZEL fiyatlandırma bulundu:');
      print('      Temel Ücret: ${pricing['baseRate']}₺');
      print('      KM Ücreti: ${pricing['perKmRate']}₺/km');
      print('      Max KM: ${pricing['maxKm']} km');

      return pricing;
    } catch (e) {
      print('❌ Özel fiyatlandırma yükleme hatası: $e');
      return null;
    }
  }

  /// ⭐ Kurye ücretlendirme bilgisini t_courier.s_pricing'den çek
  /// Yeni sistem: s_fixed_fee, s_min_km, s_per_km_fee
  static Future<Map<String, dynamic>?> getCourierPricingFromCourier(int courierId) async {
    try {
      print('💰 Kurye ücretlendirme bilgisi çekiliyor: Kurye ID = $courierId');
      
      final courierQuery = await db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .limit(1)
          .get();

      if (courierQuery.docs.isEmpty) {
        print('   ❌ Kurye bulunamadı: $courierId');
        return null;
      }

      final courierData = courierQuery.docs.first.data();
      final sPricing = courierData['s_pricing'] as Map<String, dynamic>?;

      if (sPricing == null) {
        print('   ⚠️ s_pricing alanı bulunamadı!');
        return null;
      }

      final pricing = {
        's_fixed_fee': (sPricing['s_fixed_fee'] as num?)?.toDouble() ?? 0.0,
        's_min_km': (sPricing['s_min_km'] as num?)?.toDouble() ?? 0.0,
        's_per_km_fee': (sPricing['s_per_km_fee'] as num?)?.toDouble() ?? 0.0,
      };

      print('   ✅ Kurye ücretlendirme bilgisi yüklendi:');
      print('      Sabit Ücret (s_fixed_fee): ${pricing['s_fixed_fee']}₺');
      print('      Minimum KM (s_min_km): ${pricing['s_min_km']} km');
      print('      KM Başı Ücret (s_per_km_fee): ${pricing['s_per_km_fee']}₺/km');

      return pricing;
    } catch (e) {
      print('❌ Kurye ücretlendirme yükleme hatası: $e');
      return null;
    }
  }

  /// ⭐ Kurye statusunu dinle (Real-time)
  /// s_stat: 0=Çalışmıyor, 1=Müsait, 2=Meşgul, 3=Mola, 4=Kaza
  static Stream<int> watchCourierStatus(int courierId) {
    return db
        .collection('t_courier')
        .where('s_id', isEqualTo: courierId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        print('⚠️ Kurye bulunamadı: $courierId');
        return 1; // Default: Müsait
      }
      
      final courierData = snapshot.docs.first.data();
      final status = courierData['s_stat'] ?? 1;
      print('👤 Kurye statüsü: $status');
      return status as int;
    }).handleError((error) {
      print('❌ Kurye statü dinleme hatası: $error');
      return 1; // Default: Müsait
    });
  }

  /// ⭐ Kurye statusunu güncelle
  /// 0=Çalışmıyor, 1=Müsait, 2=Meşgul, 3=Mola, 4=Kaza
  static Future<void> updateCourierStatus(int courierId, int status) async {
    try {
      print('📝 📝 📝 updateCourierStatus çağrıldı: courierId=$courierId, status=$status');
      
      final querySnapshot = await db
          .collection('t_courier')
          .where('s_id', isEqualTo: courierId)
          .get();

      print('📝 Sorgu sonucu: ${querySnapshot.docs.length} belge bulundu');

      if (querySnapshot.docs.isNotEmpty) {
        final docRef = querySnapshot.docs.first.reference;
        final docId = querySnapshot.docs.first.id;
        print('📝 Güncellenecek belge ID: $docId');
        
        await docRef.update({
          's_stat': status,
          's_stat_updated': Timestamp.now(),
        });
        
        print('📝 Firestore güncellemesi tamamlandı');
        
        // 💾 Cache'i invalidate et
        LocationService.invalidateStatusCache();
        
        print('✅ ✅ ✅ Kurye statüsü güncellendi: $courierId -> $status');
        
        // ⭐ Doğrulama: Güncellenmiş değeri oku
        final verifySnapshot = await docRef.get();
        final verifyData = verifySnapshot.data();
        final verifyStatus = verifyData?['s_stat'] as int?;
        print('📝 📝 📝 Doğrulama: Güncellenmiş statü = $verifyStatus (beklenen: $status)');
        
        if (verifyStatus == status) {
          print('✅ ✅ ✅ Doğrulama başarılı! Statü doğru güncellendi.');
        } else {
          print('⚠️ ⚠️ ⚠️ Doğrulama uyarısı: Statü beklenen değerle eşleşmiyor!');
          // ⭐ KRİTİK: Doğrulama başarısızsa tekrar dene (max 2 deneme)
          if (verifyStatus != null && verifyStatus != status) {
            print('🔄 Doğrulama başarısız, tekrar deniyor...');
            try {
              await docRef.update({
                's_stat': status,
                's_stat_updated': Timestamp.now(),
              });
              
              // İkinci doğrulama
              final verifySnapshot2 = await docRef.get();
              final verifyData2 = verifySnapshot2.data();
              final verifyStatus2 = verifyData2?['s_stat'] as int?;
              
              if (verifyStatus2 == status) {
                print('✅ ✅ ✅ İkinci deneme başarılı! Statü doğru güncellendi.');
              } else {
                print('❌ ❌ ❌ İkinci deneme de başarısız! Statü: $verifyStatus2 (beklenen: $status)');
                throw Exception('Statü güncellenemedi: Doğrulama başarısız');
              }
            } catch (retryError) {
              print('❌ ❌ ❌ Tekrar deneme hatası: $retryError');
              throw Exception('Statü güncellenemedi: $retryError');
            }
          }
        }
      } else {
        print('⚠️ ⚠️ ⚠️ Kurye bulunamadı: $courierId');
      }
    } catch (e, stackTrace) {
      print('❌ ❌ ❌ Kurye statü güncelleme HATASI: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow; // Hata yukarıya fırlatılsın
    }
  }
}

