import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Firebase ve bildirim servisi
class FirebaseService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _topicSubscribed = false;

  /// Firebase'i başlat
  static Future<bool> init() async {
    // Web platformunda Firebase yapılandırması farklı, şimdilik atla
    if (kIsWeb) {
      print('Web platformu — Firebase atlanıyor (bildirimler devre dışı)');
      _initialized = false;
      return false;
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
      // FCM kurulumunu ayrı try-catch'e al — APNS token henüz hazır olmayabilir
      try {
        await _setupFCM();
      } catch (fcmError) {
        print('FCM kurulumu başarısız (APNS token hazır olmayabilir): $fcmError');
      }
      await _setupLocalNotifications();
      return true;
    } catch (e) {
      print('Firebase başlatılamadı: $e');
      _initialized = false;
      return false;
    }
  }

  /// Firebase başlatılmış mı?
  static bool get isInitialized => _initialized;

  /// FCM kurulumu
  static Future<void> _setupFCM() async {
    final messaging = FirebaseMessaging.instance;

    // iOS'ta APNS token hazır olana kadar bekle
    if (Platform.isIOS) {
      String? apnsToken;
      for (int i = 0; i < 10; i++) {
        try {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken != null) break;
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 1));
      }
      if (apnsToken == null) {
        print('[FCM] APNS token 10 sn içinde alınamadı, topic subscription erteleniyor.');
        // Foreground dinleyicilerini yine de ayarla
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
        FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);
        FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
        return;
      }
      print('[FCM] APNS token alındı ✓');
    }

    // 'halka_arz' topic'ine abone ol
    await messaging.subscribeToTopic('halka_arz');
    _topicSubscribed = true;
    print('[FCM] halka_arz topic abone olundu ✓');

    // Token al (debug için)
    final token = await messaging.getToken();
    print('[FCM] Token: $token');

    // Foreground mesajları
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Background mesaj handler
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

    // Bildirime tıklanınca
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  /// Yerel bildirim kurulumu
  static Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      settings: settings,
    );
  }

  /// Foreground bildirim göster
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'halka_arz_channel',
          'Halka Arz Bildirimleri',
          channelDescription: 'Halka arz fiyat ve süre bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Background mesaj handler (top-level fonksiyon olmalı)
  @pragma('vm:entry-point')
  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    print('Background mesaj alındı: ${message.messageId}');
  }

  /// Bildirime tıklanınca
  static void _handleMessageOpenedApp(RemoteMessage message) {
    print('Bildirime tıklandı: ${message.data}');
    // Gerekirse ilgili sayfaya yönlendir
  }

  /// Harici olarak çağırılır — UI yüklendikten sonra izinleri istemek için
  static Future<void> requestNotificationPermission() async {
    if (kIsWeb) return;

    // İzin iste (permission_handler ile daha sağlam)
    if (Platform.isIOS) {
      final status = await Permission.notification.status;
      debugPrint('[FCM] Mevcut bildirim izni: $status');
      if (status.isDenied || status.isProvisional || status == PermissionStatus.restricted) {
        final result = await Permission.notification.request();
        debugPrint('[FCM] Bildirim izni istendi (yeni UI): $result');
      }
    }

    // Firebase başlatılamadıysa (örn: simülatör) messaging objesini çağırma, atla
    if (!_initialized) return;

    // Firebase'in push token alması için Apple APNs onayı
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Eğer başlangıçta APNS token geciktiği için topic aboneliği yapılamadıysa, şimdi tekrar dene
    if (!_topicSubscribed) {
      try {
        await messaging.subscribeToTopic('halka_arz');
        _topicSubscribed = true;
        debugPrint('[FCM] İzin sonrası halka_arz topic abone olundu ✓');
      } catch (e) {
        debugPrint('[FCM] İzin sonrası topic aboneliği de başarısız: $e');
      }
    }
  }
}
