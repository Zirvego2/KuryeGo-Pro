import CoreLocation
import Flutter
import Foundation
import UIKit

/// App kill sonrası sürekli canlı GPS yok; significant-change ile event-driven uyandırma (Apple limitation).
/// Tracking lifecycle Flutter ile senkron; kapalıyken bile ağ üzerinden API denenebilir.
final class LocationWakeManager: NSObject, CLLocationManagerDelegate {
  static let shared = LocationWakeManager()

  private let ud = UserDefaults.standard
  private let minDistanceM: CLLocationDistance = 50
  private let minRepeatSendMs: Int64 = 25_000
  private let servisURL = URL(string: "https://zirvego.app/api/servis")!

  private enum K {
    static let tracking = "zg_native_courier_tracking"
    static let courierId = "zg_native_courier_id"
    static let apiToken = "zg_native_api_token"
    static let lastLat = "zg_shared_last_lat"
    static let lastLon = "zg_shared_last_lon"
    static let lastSendMs = "zg_shared_last_send_ms"
    static let pending = "zg_native_pending_queue_json"
  }

  private let manager = CLLocationManager()
  private var channel: FlutterMethodChannel?
  private var channelConfigured = false
  private var isOneShotFix = false

  private override init() {
    super.init()
    manager.delegate = self
    manager.allowsBackgroundLocationUpdates = true
    manager.pausesLocationUpdatesAutomatically = false
  }

  func configureChannel(messenger: FlutterBinaryMessenger) {
    guard !channelConfigured else { return }
    channelConfigured = true
    let ch = FlutterMethodChannel(name: "com.zirvego/native_location", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    channel = ch
  }

  /// Uygulama açıldığında / location ile relaunch — izin varsa monitörü aç
  func bootstrapAfterLaunch() {
    DispatchQueue.main.async { [weak self] in
      self?.refreshMonitoringIfNeeded()
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setTrackingState":
      guard let args = call.arguments as? [String: Any],
            let enabled = args["enabled"] as? Bool else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      let courierId = (args["courierId"] as? Int)
        ?? (args["courierId"] as? NSNumber)?.intValue
        ?? 0
      let token = args["apiToken"] as? String
      applyTrackingState(enabled: enabled, courierId: courierId, apiToken: token)
      result(nil)
    case "syncLastSentFromFlutter":
      guard let args = call.arguments as? [String: Any],
            let lat = args["lat"] as? Double,
            let lon = args["lon"] as? Double else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      let ts: Int64
      if let t = args["timestampMs"] as? Int64 {
        ts = t
      } else if let t = args["timestampMs"] as? Int {
        ts = Int64(t)
      } else if let n = args["timestampMs"] as? NSNumber {
        ts = n.int64Value
      } else {
        ts = Int64(Date().timeIntervalSince1970 * 1000)
      }
      persistLastSent(lat: lat, lon: lon, sendMs: ts)
      result(nil)
    case "getSharedLastSent":
      if let lat = ud.object(forKey: K.lastLat) as? Double,
         let lon = ud.object(forKey: K.lastLon) as? Double {
        result(["lat": lat, "lon": lon])
      } else {
        result(nil)
      }
    case "drainNativePendingQueue":
      let raw = ud.string(forKey: K.pending) ?? ""
      ud.removeObject(forKey: K.pending)
      result(raw.isEmpty ? "[]" : raw)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applyTrackingState(enabled: Bool, courierId: Int, apiToken: String?) {
    ud.set(enabled, forKey: K.tracking)
    ud.set(courierId, forKey: K.courierId)
    if let t = apiToken { ud.set(t, forKey: K.apiToken) } else { ud.removeObject(forKey: K.apiToken) }
    DispatchQueue.main.async { [weak self] in
      self?.refreshMonitoringIfNeeded()
    }
  }

  private func refreshMonitoringIfNeeded() {
    guard ud.bool(forKey: K.tracking), currentCourierId() > 0 else {
      manager.stopMonitoringSignificantLocationChanges()
      return
    }
    guard authAllowsAlways() else { return }
    manager.startMonitoringSignificantLocationChanges()
  }

  private func currentCourierId() -> Int {
    ud.integer(forKey: K.courierId)
  }

  private func authAllowsAlways() -> Bool {
    if #available(iOS 14.0, *) {
      return manager.authorizationStatus == .authorizedAlways
    }
    return CLLocationManager.authorizationStatus() == .authorizedAlways
  }

  // MARK: - CLLocationManagerDelegate

  @available(iOS 14.0, *)
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    refreshMonitoringIfNeeded()
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    if #available(iOS 14.0, *) {
      // iOS 14+ için locationManagerDidChangeAuthorization kullanılır
    } else {
      refreshMonitoringIfNeeded()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let loc = locations.last else { return }
    guard ud.bool(forKey: K.tracking), currentCourierId() > 0, authAllowsAlways() else { return }

    let courierId = currentCourierId()
    let lat = loc.coordinate.latitude
    let lon = loc.coordinate.longitude

    if let lastLat = ud.object(forKey: K.lastLat) as? Double,
       let lastLon = ud.object(forKey: K.lastLon) as? Double {
      let prev = CLLocation(latitude: lastLat, longitude: lastLon)
      let d = loc.distance(from: prev)
      if d < minDistanceM {
        if isOneShotFix { isOneShotFix = false; manager.stopUpdatingLocation() }
        return
      }
    }

    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
    let prevSend: Int64
    if let n = ud.object(forKey: K.lastSendMs) as? NSNumber {
      prevSend = n.int64Value
    } else {
      prevSend = Int64(ud.integer(forKey: K.lastSendMs))
    }
    if prevSend > 0, nowMs - prevSend < minRepeatSendMs {
      if isOneShotFix { isOneShotFix = false; manager.stopUpdatingLocation() }
      return
    }

    let speedKmh = loc.speed >= 0 ? loc.speed * 3.6 : nil
    let km = (speedKmh ?? 0) < 3.0 ? nil : speedKmh

    submitLocation(lat: lat, lon: lon, courierId: courierId, speedKmh: km, timestampMs: nowMs) { [weak self] ok in
      guard let self = self else { return }
      if ok {
        self.persistLastSent(lat: lat, lon: lon, sendMs: nowMs)
      } else {
        self.enqueuePending(lat: lat, lon: lon, courierId: courierId, speedKmh: km, timestampMs: nowMs)
      }
      if self.isOneShotFix {
        self.isOneShotFix = false
        self.manager.stopUpdatingLocation()
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("LocationWakeManager error: \(error.localizedDescription)")
  }

  // MARK: - API (CourierLocationApi ile aynı sözleşme)

  private func submitLocation(
    lat: Double,
    lon: Double,
    courierId: Int,
    speedKmh: Double?,
    timestampMs: Int64,
    completion: @escaping (Bool) -> Void
  ) {
    var bgTask: UIBackgroundTaskIdentifier = .invalid
    bgTask = UIApplication.shared.beginBackgroundTask {
      UIApplication.shared.endBackgroundTask(bgTask)
      bgTask = .invalid
    }

    let finish: (Bool) -> Void = { ok in
      DispatchQueue.main.async {
        if bgTask != .invalid {
          UIApplication.shared.endBackgroundTask(bgTask)
          bgTask = .invalid
        }
        completion(ok)
      }
    }

    var body: [String: Any] = [
      "latitude": lat,
      "longitude": lon,
      "timestamp": timestampMs,
      "courierId": courierId,
      "s_id": courierId,
    ]
    if let s = speedKmh { body["speedKmh"] = s }

    var request = URLRequest(url: servisURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let tok = ud.string(forKey: K.apiToken), !tok.isEmpty {
      request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
      guard let self = self else { finish(false); return }
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      if code == 200 || code == 201 {
        finish(true)
        return
      }
      self.tryLegacyGet(lat: lat, lon: lon, courierId: courierId, speedKmh: speedKmh, timestampMs: timestampMs, completion: finish)
    }.resume()
  }

  private func tryLegacyGet(
    lat: Double,
    lon: Double,
    courierId: Int,
    speedKmh: Double?,
    timestampMs: Int64,
    completion: @escaping (Bool) -> Void
  ) {
    var comp = URLComponents(url: servisURL, resolvingAgainstBaseURL: false)!
    var q = [
      URLQueryItem(name: "x", value: "\(lat)"),
      URLQueryItem(name: "y", value: "\(lon)"),
      URLQueryItem(name: "s_id", value: "\(courierId)"),
      URLQueryItem(name: "t", value: "\(timestampMs)"),
    ]
    if let km = speedKmh {
      q.append(URLQueryItem(name: "km", value: String(format: "%.2f", km)))
    }
    comp.queryItems = q
    guard let url = comp.url else { completion(false); return }
    URLSession.shared.dataTask(with: url) { _, response, _ in
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      completion(code == 200)
    }.resume()
  }

  private func persistLastSent(lat: Double, lon: Double, sendMs: Int64) {
    ud.set(lat, forKey: K.lastLat)
    ud.set(lon, forKey: K.lastLon)
    ud.set(Int(sendMs), forKey: K.lastSendMs)
  }

  private func enqueuePending(lat: Double, lon: Double, courierId: Int, speedKmh: Double?, timestampMs: Int64) {
    var items = loadPending()
    var obj: [String: Any] = [
      "latitude": lat,
      "longitude": lon,
      "timestamp": timestampMs,
    ]
    if let s = speedKmh { obj["speedKmh"] = s }
    items.append(obj)
    while items.count > 50 { items.removeFirst() }
    if let data = try? JSONSerialization.data(withJSONObject: items),
       let s = String(data: data, encoding: .utf8) {
      ud.set(s, forKey: K.pending)
    }
  }

  private func loadPending() -> [[String: Any]] {
    guard let s = ud.string(forKey: K.pending),
          let d = s.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else {
      return []
    }
    return arr
  }

  /// Öldürülmüş uygulama significant-change ile açıldığında tek seferlik fix iste
  func requestOneShotIfLaunchedForLocation() {
    guard ud.bool(forKey: K.tracking), currentCourierId() > 0, authAllowsAlways() else { return }
    isOneShotFix = true
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.requestLocation()
  }
}
