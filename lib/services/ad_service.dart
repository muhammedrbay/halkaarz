import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:permission_handler/permission_handler.dart';

/// AdMob reklam yönetim servisi
/// - App Open: Uygulama açılışında
/// - Interstitial: 3 dk sonra, her 3 dk'da bir
/// - Native: IPO listesinde kartlar arasında
class AdService {
  // ─── Production & Test Ad IDs ──────────────────────────────────────────────────
  static String get _appOpenAdUnitId {
    if (kReleaseMode) {
      if (Platform.isAndroid) return 'ca-app-pub-9576499265117171/3364879256';
      if (Platform.isIOS) return 'ca-app-pub-9576499265117171/1668885711';
    } else {
      if (Platform.isAndroid)
        return 'ca-app-pub-3940256099942544/9257395921'; // Test
      if (Platform.isIOS)
        return 'ca-app-pub-3940256099942544/5662855259'; // Test
    }
    return '';
  }

  static String get _interstitialAdUnitId {
    if (kReleaseMode) {
      if (Platform.isAndroid) return 'ca-app-pub-9576499265117171/5113075190';
      if (Platform.isIOS) return 'ca-app-pub-9576499265117171/3860623149';
    } else {
      if (Platform.isAndroid)
        return 'ca-app-pub-3940256099942544/1033173712'; // Test
      if (Platform.isIOS)
        return 'ca-app-pub-3940256099942544/4411468910'; // Test
    }
    return '';
  }

  static String get _nativeAdUnitId {
    if (kReleaseMode) {
      if (Platform.isAndroid) return 'ca-app-pub-9576499265117171/8338692698';
      if (Platform.isIOS) return 'ca-app-pub-9576499265117171/9651317517';
    } else {
      if (Platform.isAndroid)
        return 'ca-app-pub-3940256099942544/2247696110'; // Test
      if (Platform.isIOS)
        return 'ca-app-pub-3940256099942544/3986624511'; // Test
    }
    return '';
  }

  // ─── Interstitial ─────────────────────────────────────────────────────────
  static InterstitialAd? _interstitialAd;
  static bool _isInterstitialLoaded = false;
  static Timer? _interstitialTimer;
  static const Duration _interstitialInterval = Duration(minutes: 3);

  // ─── App Open ─────────────────────────────────────────────────────────────
  static AppOpenAd? _appOpenAd;
  static bool _isAppOpenLoaded = false;
  static bool _isShowingAd = false;

  // ─── Native (çoklu instance) ──────────────────────────────────────────────

  // ─── Web kontrolü ─────────────────────────────────────────────────────────
  static bool get _isWeb => kIsWeb;

  // ═══════════════════════════════════════════════════════════════════════════
  // INIT
  // ═══════════════════════════════════════════════════════════════════════════

  /// AdMob SDK'yı başlat (main.dart'ta çağrılır)
  static Future<void> init() async {
    if (_isWeb) {
      debugPrint('[AD] Web platformu — reklamlar devre dışı.');
      return;
    }

    await MobileAds.instance.initialize();
    debugPrint('[AD ✓] AdMob başlatıldı.');

    // Reklamları önceden yükle
    loadAppOpenAd();
    _startInterstitialTimer();
    loadNativeAd('home');
    loadNativeAd('historical');
  }

  /// UI yüklendikten SONRA izinleri iste ve App Open reklamını göster
  static Future<void> requestTrackingAndShowAppOpenAd() async {
    if (_isWeb) return;

    // iOS'ta ATT (App Tracking Transparency) izni iste
    await _requestTrackingPermission();

    // İzinler istendikten sonra hazırsa App Open reklamını göster
    showAppOpenAd();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APP OPEN AD
  // ═══════════════════════════════════════════════════════════════════════════

  static void loadAppOpenAd() {
    if (_isWeb) return;

    AppOpenAd.load(
      adUnitId: _appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _isAppOpenLoaded = true;
          debugPrint('[AD ✓] App Open reklam yüklendi.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AD ✗] App Open yüklenemedi: ${error.message}');
          _isAppOpenLoaded = false;
        },
      ),
    );
  }

  static void showAppOpenAd() {
    if (!_isAppOpenLoaded || _appOpenAd == null || _isShowingAd) return;

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAd = true;
      },
      onAdDismissedFullScreenContent: (ad) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        _isAppOpenLoaded = false;
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        _isAppOpenLoaded = false;
      },
    );

    _appOpenAd!.show();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERSTITIAL AD — 3 dk timer
  // ═══════════════════════════════════════════════════════════════════════════

  static void _startInterstitialTimer() {
    if (_isWeb) return;

    // İlk interstitial 3 dk sonra
    _interstitialTimer = Timer.periodic(_interstitialInterval, (_) {
      showInterstitialAd();
    });

    // 3 dk sonrası için önceden yükle
    _loadInterstitialAd();
  }

  static void _loadInterstitialAd() {
    if (_isWeb) return;

    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoaded = true;
          debugPrint('[AD ✓] Interstitial reklam yüklendi.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AD ✗] Interstitial yüklenemedi: ${error.message}');
          _isInterstitialLoaded = false;
        },
      ),
    );
  }

  static void showInterstitialAd() {
    if (!_isInterstitialLoaded || _interstitialAd == null || _isShowingAd) {
      // Yüklü değilse tekrar yükle, bir sonraki cycle'da gösterilir
      _loadInterstitialAd();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAd = true;
        debugPrint('[AD] Interstitial gösterildi.');
      },
      onAdDismissedFullScreenContent: (ad) {
        _isShowingAd = false;
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialLoaded = false;
        // Bir sonraki gösterim için tekrar yükle
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowingAd = false;
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialLoaded = false;
        _loadInterstitialAd();
      },
    );

    _interstitialAd!.show();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NATIVE AD — IPO listelerinde kartlar arasında
  // ═══════════════════════════════════════════════════════════════════════════

  static final Map<String, NativeAd> _nativeAds = {};
  static final Map<String, bool> _nativeAdLoaded = {};

  /// Belirli bir key için native reklam yüklendi mi?
  static bool isNativeAdLoaded([String key = 'default']) =>
      _nativeAdLoaded[key] == true && _nativeAds[key] != null;

  /// Yüklenmiş native reklam objesi
  static NativeAd? getNativeAd([String key = 'default']) => _nativeAds[key];

  static void loadNativeAd([String key = 'default']) {
    if (_isWeb) return;

    // Zaten yüklüyse tekrar yükleme
    if (_nativeAdLoaded[key] == true) return;

    final ad = NativeAd(
      adUnitId: _nativeAdUnitId,
      // nativeTemplateStyle kullan — native Swift factory'ye gerek yok
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
      ),
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          _nativeAdLoaded[key] = true;
          debugPrint('[AD ✓] Native reklam ($key) yüklendi.');
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AD ✗] Native ($key) yüklenemedi: ${error.message}');
          _nativeAdLoaded[key] = false;
          ad.dispose();
          _nativeAds.remove(key);
        },
      ),
    );

    _nativeAds[key] = ad;
    ad.load();
  }

  /// Native reklam widget'ı — tüm ekranlarda aynı görünüm
  static final Map<String, GlobalKey> _adWidgetKeys = {};

  static Widget buildNativeAdWidget(String key) {
    if (!isNativeAdLoaded(key) || getNativeAd(key) == null) {
      return const SizedBox.shrink();
    }

    // Her key için tek bir GlobalKey oluştur — widget tree'de çakışma önlenir
    _adWidgetKeys.putIfAbsent(key, () => GlobalKey());

    return KeyedSubtree(
      key: _adWidgetKeys[key],
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF1A1F38),
          border: Border.all(
            color: const Color(0xFFFFFFFF).withAlpha(13), // ~0.05
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AdWidget(ad: getNativeAd(key)!),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APP TRACKING TRANSPARENCY (iOS)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _requestTrackingPermission() async {
    try {
      if (!kIsWeb && Platform.isIOS) {
        // Doğrudan app_tracking_transparency eklentisini kullan
        final status =
            await AppTrackingTransparency.trackingAuthorizationStatus;
        debugPrint('[ATT] Mevcut durum: $status');

        if (status == TrackingStatus.notDetermined) {
          final result =
              await AppTrackingTransparency.requestTrackingAuthorization();
          debugPrint('[ATT] İstek sonucu: $result');
        } else {
          // Zaten karar verilmişse (denied, authorized vb.) handler ile logla
          final handlerStatus = await Permission.appTrackingTransparency.status;
          debugPrint(
            '[ATT] permission_handler ile tekrar kontrol: $handlerStatus',
          );
        }
      }
    } catch (e) {
      debugPrint('[ATT] Hata: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  static void dispose() {
    _interstitialTimer?.cancel();
    _interstitialAd?.dispose();
    _appOpenAd?.dispose();
    for (final ad in _nativeAds.values) {
      ad.dispose();
    }
    _nativeAds.clear();
    _nativeAdLoaded.clear();
  }
}
