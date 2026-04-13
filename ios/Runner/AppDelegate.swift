import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleMaps
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API Key başlatma – Zorunlu!
    if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
       let plist = NSDictionary(contentsOfFile: path),
       let apiKey = plist["GMSApiKey"] as? String {
      GMSServices.provideAPIKey(apiKey)
    }
    
    // Firebase başlangıcı – ZirveGo Kurye iOS için eklendi
    FirebaseApp.configure()
    
    // Kısa uygulama içi / bildirim tonları (foreground). UIBackgroundModes audio yok (App Store 2.5.4).
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
      try audioSession.setActive(true)
      print("✅ Audio session (ambient) — foreground uyarı sesleri")
    } catch {
      print("❌ Audio session yapılandırma hatası: \(error.localizedDescription)")
    }
    
    // Push notification kayıt işlemi
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      
      // Notification Categories oluştur (Android channel'larına benzer)
      let ordersCategory = UNNotificationCategory(
        identifier: "orders2",
        actions: [],
        intentIdentifiers: [],
        options: [.customDismissAction]
      )
      
      let defaultCategory = UNNotificationCategory(
        identifier: "default",
        actions: [],
        intentIdentifiers: [],
        options: [.customDismissAction]
      )
      
      // Category'leri kaydet
      UNUserNotificationCenter.current().setNotificationCategories([
        ordersCategory,
        defaultCategory
      ])
      
      let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
      UNUserNotificationCenter.current().requestAuthorization(
        options: authOptions,
        completionHandler: { _, _ in }
      )
    } else {
      let settings: UIUserNotificationSettings =
        UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
      application.registerUserNotificationSettings(settings)
    }
    
    application.registerForRemoteNotifications()
    
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    DispatchQueue.main.async { [weak self] in
      guard let self = self,
            let controller = self.window?.rootViewController as? FlutterViewController else {
        return
      }
      LocationWakeManager.shared.configureChannel(messenger: controller.binaryMessenger)
      LocationWakeManager.shared.bootstrapAfterLaunch()
    }

    if launchOptions?[UIApplication.LaunchOptionsKey.location] != nil {
      LocationWakeManager.shared.requestOneShotIfLaunchedForLocation()
    }

    return ok
  }
  
  // APNS token alındığında Firebase'e kaydet
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
  }
  
  // APNS token alınamazsa
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ APNS token kayıt hatası: \(error.localizedDescription)")
  }
  
  // Background notification handling - iOS için kritik!
  override func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("📱 Background notification alındı: \(userInfo)")
    
    // Firebase mesajını işle
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // Background fetch sonucunu bildir
    completionHandler(.newData)
  }
  
  // Silent push notification handling (content-available: 1)
  override func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
    print("📱 Remote notification alındı (foreground/background): \(userInfo)")
    Messaging.messaging().appDidReceiveMessage(userInfo)
  }
  
  // Notification presentation (foreground'da bildirim göster)
  @available(iOS 10.0, *)
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let userInfo = notification.request.content.userInfo
    print("📱 Foreground notification alındı: \(userInfo)")
    
    // Firebase mesajını işle
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    // iOS 14+ için yeni API - Bildirim göster ve ses çal (APNs payload'ındaki sound kullanılır)
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .badge, .sound])
    } else {
      completionHandler([.alert, .badge, .sound])
    }
  }
  
  // Notification'a tıklandığında
  @available(iOS 10.0, *)
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    print("👆 Notification'a tıklandı: \(userInfo)")
    
    // Firebase mesajını işle
    Messaging.messaging().appDidReceiveMessage(userInfo)
    
    completionHandler()
  }
}
