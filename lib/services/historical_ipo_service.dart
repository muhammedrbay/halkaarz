import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

// ─── Model ───────────────────────────────────────────────────────────────────

class HistoricalIpo {
  final String sirketKodu;
  final String sirketAdi;

  // Statik (GitHub ipos.json'dan, sonsuza kadar cache)
  final double arzFiyati;
  final int kisiBasiLot;
  final int toplamLot;
  final DateTime islemTarihi;
  final bool katilimEndeksi;
  final String? sektor;
  final String? fonKullanim;

  // Yarı-statik (Yahoo Finance'den, sadece 1 kez çekilir)
  double? ilkGunKapanis;
  double? maxFiyat;
  double? minFiyat;
  int? tavanGunSayisi;
  List<double> sparkline;
  bool? staticFetched;
  DateTime? staticFetchedAt;

  // Dinamik (RTDB'den — RealtimePriceService tarafından doldurulur)
  double? guncelFiyat;
  DateTime? priceUpdatedAt;

  HistoricalIpo({
    required this.sirketKodu,
    required this.sirketAdi,
    required this.arzFiyati,
    required this.kisiBasiLot,
    required this.toplamLot,
    required this.islemTarihi,
    this.katilimEndeksi = false,
    this.sektor,
    this.fonKullanim,
    this.ilkGunKapanis,
    this.maxFiyat,
    this.minFiyat,
    this.tavanGunSayisi,
    this.sparkline = const [],
    this.staticFetched,
    this.staticFetchedAt,
    this.guncelFiyat,
    this.priceUpdatedAt,
  });

  // — Hesaplanan alanlar —

  double get getiviYuzde {
    if (guncelFiyat == null || arzFiyati <= 0) return 0;
    return ((guncelFiyat! - arzFiyati) / arzFiyati) * 100;
  }

  double get ilkGunGetiri {
    if (ilkGunKapanis == null || arzFiyati <= 0) return 0;
    return ((ilkGunKapanis! - arzFiyati) / arzFiyati) * 100;
  }

  bool get tavanMi {
    if (sparkline.length < 2 || guncelFiyat == null) return false;
    final prev = sparkline[sparkline.length - 2];
    if (prev <= 0) return false;
    return (guncelFiyat! - prev) / prev >= 0.095;
  }

  factory HistoricalIpo.fromJson(Map<String, dynamic> j) {
    return HistoricalIpo(
      sirketKodu: (j['sirket_kodu'] ?? j['kod'] ?? '').toString().toUpperCase(),
      sirketAdi: j['sirket_adi'] ?? j['ad'] ?? '',
      arzFiyati: (j['arz_fiyati'] ?? 0).toDouble(),
      kisiBasiLot: (j['kisi_basi_lot'] ?? 0).toInt(),
      toplamLot: (j['toplam_lot'] ?? 0).toInt(),
      islemTarihi: DateTime.tryParse(j['borsada_islem_tarihi'] ?? j['islem_tarihi'] ?? '') ?? DateTime.now(),
      katilimEndeksi: j['katilim_endeksine_uygun'] ?? j['katilim'] ?? false,
      sektor: j['sektor'] as String?,
      fonKullanim: j['fon_kullanim_yeri'] is String ? j['fon_kullanim_yeri'] : null,
      ilkGunKapanis: (j['ilk_gun_kapanis'] as num?)?.toDouble(),
      maxFiyat: (j['max_fiyat'] as num?)?.toDouble(),
      minFiyat: (j['min_fiyat'] as num?)?.toDouble(),
      tavanGunSayisi: (j['tavan_gun'] as num?)?.toInt(),
      sparkline: (j['sparkline'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      staticFetched: j['static_fetched'] as bool?,
      staticFetchedAt: j['static_fetched_at'] != null
          ? DateTime.tryParse(j['static_fetched_at'])
          : null,
      guncelFiyat: (j['guncel_fiyat'] as num?)?.toDouble(),
      priceUpdatedAt: j['price_updated_at'] != null
          ? DateTime.tryParse(j['price_updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'sirket_kodu': sirketKodu,
        'sirket_adi': sirketAdi,
        'arz_fiyati': arzFiyati,
        'kisi_basi_lot': kisiBasiLot,
        'toplam_lot': toplamLot,
        'borsada_islem_tarihi': islemTarihi.toIso8601String(),
        'katilim_endeksine_uygun': katilimEndeksi,
        'sektor': sektor,
        'fon_kullanim_yeri': fonKullanim,
        'ilk_gun_kapanis': ilkGunKapanis,
        'max_fiyat': maxFiyat,
        'min_fiyat': minFiyat,
        'tavan_gun': tavanGunSayisi,
        'sparkline': sparkline,
        'static_fetched': staticFetched,
        'static_fetched_at': staticFetchedAt?.toIso8601String(),
        'guncel_fiyat': guncelFiyat,
        'price_updated_at': priceUpdatedAt?.toIso8601String(),
      };
}

// ─── Servis ──────────────────────────────────────────────────────────────────

class HistoricalIpoService {
  static const String _boxName = 'historical_ipos_v3';
  static const String _metaBoxName = 'historical_ipos_meta';

  // GitHub raw URL — scraper.py'nin ürettiği dosya
  static const String _githubJsonUrl =
      'https://raw.githubusercontent.com/muhammedrbay/halkaarz/main/backend/data/ipos.json';

  // Statik JSON ne kadar süre cache'te kalır (24 saat)
  static const Duration _staticCacheTtl = Duration(hours: 24);

  static Future<void> init() async {
    await Hive.openBox(_boxName);
    await Hive.openBox(_metaBoxName);
  }

  // ─── Cache IO ──────────────────────────────────────────────────────────────

  static List<HistoricalIpo> loadFromCache() {
    final box = Hive.box(_boxName);
    final raw = box.get('data');
    if (raw == null) return [];
    try {
      final list = json.decode(raw as String) as List;
      return list
          .map((e) => HistoricalIpo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Cache okuma hatası: $e');
      return [];
    }
  }

  static Future<void> saveToCache(List<HistoricalIpo> ipos) async {
    final box = Hive.box(_boxName);
    await box.put('data', json.encode(ipos.map((e) => e.toJson()).toList()));
  }

  static DateTime? _lastStaticFetch() {
    final box = Hive.box(_metaBoxName);
    final raw = box.get('static_fetched_at') as String?;
    return raw != null ? DateTime.tryParse(raw) : null;
  }

  static Future<void> _markStaticFetched() async {
    final box = Hive.box(_metaBoxName);
    await box.put('static_fetched_at', DateTime.now().toIso8601String());
  }

  static bool get _staticCacheExpired {
    final last = _lastStaticFetch();
    if (last == null) return true;
    return DateTime.now().difference(last) > _staticCacheTtl;
  }

  // ─── GitHub JSON İndirme ───────────────────────────────────────────────────

  /// GitHub'daki ipos.json'u indirir (24 saatte bir)
  static Future<List<HistoricalIpo>?> _fetchFromGitHub() async {
    try {
      debugPrint('[GitHub] ipos.json indiriliyor...');
      final resp = await http.get(
        Uri.parse(_githubJsonUrl),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        debugPrint('[GitHub] HTTP ${resp.statusCode}');
        return null;
      }

      final list = json.decode(resp.body) as List;
      final ipos = list
          .map((e) => HistoricalIpo.fromJson(e as Map<String, dynamic>))
          .where((i) {
            // Sadece son 1 yılın arzlarını göster
            final cutoff = DateTime.now().subtract(const Duration(days: 365));
            return i.islemTarihi.isAfter(cutoff);
          })
          .toList()
        ..sort((a, b) => b.islemTarihi.compareTo(a.islemTarihi)); // Yeniden eskiye

      debugPrint('[GitHub ✓] ${ipos.length} IPO indirildi.');
      await _markStaticFetched();
      return ipos;
    } catch (e) {
      debugPrint('[GitHub] İndirme hatası: $e');
      return null;
    }
  }

  // ─── Ana Yükleme ───────────────────────────────────────────────────────────

  /// Cache'ten hemen yükle, arka planda GitHub'dan güncelle
  static Future<List<HistoricalIpo>> loadAll() async {
    final cached = loadFromCache();

    // Cache geçerliyse hemen dön
    if (cached.isNotEmpty && !_staticCacheExpired) {
      debugPrint('[HistoricalIpo] Cache geçerli, direkt kullanılıyor.');
      return cached;
    }

    // GitHub'dan taze veri çek
    final fresh = await _fetchFromGitHub();
    if (fresh == null || fresh.isEmpty) {
      // İndirme başarısız — cache'i kullan
      return cached;
    }

    // Cache'teki yarı-statik veriyi (sparkline, tavan, ilk gün) koru
    final cachedMap = {for (final i in cached) i.sirketKodu: i};
    for (final ipo in fresh) {
      final old = cachedMap[ipo.sirketKodu];
      if (old != null) {
        ipo.ilkGunKapanis = old.ilkGunKapanis;
        ipo.maxFiyat = old.maxFiyat;
        ipo.minFiyat = old.minFiyat;
        ipo.tavanGunSayisi = old.tavanGunSayisi;
        ipo.sparkline = old.sparkline;
        ipo.staticFetched = old.staticFetched;
        ipo.staticFetchedAt = old.staticFetchedAt;
        ipo.guncelFiyat = old.guncelFiyat;
        ipo.priceUpdatedAt = old.priceUpdatedAt;
      }
    }

    await saveToCache(fresh);
    return fresh;
  }

  // ─── Sparkline / Tavan Hesaplama (Yahoo Finance — sadece 1 kez) ────────────

  /// İlk gün kapanış, tavan gün, max/min, sparkline çeker.
  /// staticFetched == true ise bir daha çekilmez.
  static Future<void> fetchStaticYahooData(
    HistoricalIpo ipo, {
    void Function(HistoricalIpo)? onUpdate,
  }) async {
    if (ipo.staticFetched == true) return;

    try {
      final symbol = '${ipo.sirketKodu}.IS';
      final fromEpoch = ipo.islemTarihi.millisecondsSinceEpoch ~/ 1000;
      final toEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final url = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=1d&period1=$fromEpoch&period2=$toEpoch',
      );

      final resp = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
      }).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return;

      final data = json.decode(resp.body) as Map?;
      final chartResult = data?['chart']?['result'] as List?;
      if (chartResult == null || chartResult.isEmpty) return;

      final quote = ((chartResult[0]['indicators'] as Map?)
              ?['quote'] as List?)
          ?.firstOrNull as Map?;
      if (quote == null) return;

      final closes = (quote['close'] as List?)
              ?.whereType<num>()
              .map((e) => e.toDouble())
              .toList() ??
          [];
      if (closes.isEmpty) return;

      ipo.ilkGunKapanis = closes.first;
      ipo.maxFiyat = closes.reduce((a, b) => a > b ? a : b);
      ipo.minFiyat = closes.reduce((a, b) => a < b ? a : b);

      // Tavan gün say (önceki güne göre >=9.5%)
      int tavanCount = 0;
      // İlk gün: arz fiyatına göre
      if (ipo.arzFiyati > 0 && (closes.first - ipo.arzFiyati) / ipo.arzFiyati >= 0.095) {
        tavanCount++;
      }
      for (int i = 1; i < closes.length; i++) {
        if (closes[i - 1] > 0 && (closes[i] - closes[i - 1]) / closes[i - 1] >= 0.095) {
          tavanCount++;
        }
      }
      ipo.tavanGunSayisi = tavanCount;
      ipo.sparkline = closes.length > 30 ? closes.sublist(closes.length - 30) : closes;
      ipo.staticFetched = true;
      ipo.staticFetchedAt = DateTime.now();

      onUpdate?.call(ipo);
      debugPrint('[Yahoo ✓] ${ipo.sirketKodu}: kapanış=${closes.last.toStringAsFixed(2)}, tavan=${tavanCount}g');
    } catch (e) {
      debugPrint('[Yahoo] ${ipo.sirketKodu} hata: $e');
    }
  }

  /// Tüm IPO'ların Yahoo verilerini çek + kaydet (arka planda)
  static Future<void> fetchAllStaticYahoo(
    List<HistoricalIpo> ipos, {
    void Function(int done, int total)? onProgress,
  }) async {
    int done = 0;
    for (final ipo in ipos) {
      if (ipo.staticFetched != true) {
        await fetchStaticYahooData(ipo);
        await Future.delayed(const Duration(milliseconds: 350));
      }
      done++;
      onProgress?.call(done, ipos.length);
    }
    await saveToCache(ipos);
  }

  /// RTDB'den gelen fiyatları IPO listesine uygula
  static void applyRtdbPrices(
    List<HistoricalIpo> ipos,
    Map<String, double> prices,
  ) {
    for (final ipo in ipos) {
      final price = prices[ipo.sirketKodu];
      if (price != null) {
        ipo.guncelFiyat = price;
        ipo.priceUpdatedAt = DateTime.now();
      }
    }
  }
}
