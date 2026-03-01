import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
  List<String> sparklineDates;
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
    this.sparklineDates = const [],
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

  double get gunlukGetiriYuzde {
    if (guncelFiyat == null || sparkline.length < 2) return 0;
    
    // Grafiğin sonuna anlık fiyatı eklediğimiz/güncellediğimiz için,
    // dünkü kapanış bir önceki indisteki fiyattır.
    final dunuAralik = sparklineDates.isNotEmpty && sparklineDates.last.startsWith(
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
        );

    final prevIndex = dunuAralik ? sparkline.length - 2 : sparkline.length - 1;
    
    if (prevIndex < 0) return 0;
    
    final dunKapanis = sparkline[prevIndex];
    if (dunKapanis <= 0) return 0;
    return ((guncelFiyat! - dunKapanis) / dunKapanis) * 100;
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
      islemTarihi:
          DateTime.tryParse(
            j['borsada_islem_tarihi'] ?? j['islem_tarihi'] ?? '',
          ) ??
          DateTime.now(),
      katilimEndeksi: j['katilim_endeksine_uygun'] ?? j['katilim'] ?? false,
      sektor: j['sektor'] as String?,
      fonKullanim: j['fon_kullanim_yeri'] is String
          ? j['fon_kullanim_yeri']
          : null,
      ilkGunKapanis: (j['ilk_gun_kapanis'] as num?)?.toDouble(),
      maxFiyat: (j['max_fiyat'] as num?)?.toDouble(),
      minFiyat: (j['min_fiyat'] as num?)?.toDouble(),
      tavanGunSayisi: (j['tavan_gun'] as num?)?.toInt(),
      sparkline:
          (j['sparkline'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      sparklineDates:
          (j['sparkline_dates'] as List<dynamic>?)
              ?.map((e) => e.toString())
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
    'sparkline_dates': sparklineDates,
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

  // Firestore'dan kaç saatte bir taze veri çekilir
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
          .where(_isNotDummy)
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

  /// Deneme / test amaçlı girişleri filtrele
  static bool _isNotDummy(HistoricalIpo i) {
    final kodOk = i.sirketKodu.toUpperCase() != 'ORNEK';
    final adOk = !i.sirketAdi.toLowerCase().contains('örnek');
    return kodOk && adOk;
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

  // ─── Firestore Okuma ──────────────────────────────────────────────────────

  /// Firestore'daki 'ipos' koleksiyonundan islem_goruyor belgelerini çeker (24h cache)
  static Future<List<HistoricalIpo>?> _fetchFromFirestore() async {
    try {
      debugPrint('[Firestore] islem_goruyor belgeler çekiliyor...');
      final snapshot = await FirebaseFirestore.instance
          .collection('ipos')
          .where('durum', isEqualTo: 'islem_goruyor')
          .get(GetOptions(source: Source.serverAndCache));

      final cutoff = DateTime.now().subtract(const Duration(days: 365));
      final ipos = snapshot.docs
          .map((doc) => HistoricalIpo.fromJson(doc.data()))
          .where(_isNotDummy)
          .where((i) => i.islemTarihi.isAfter(cutoff))
          .toList()
        ..sort((a, b) => b.islemTarihi.compareTo(a.islemTarihi));

      debugPrint('[Firestore ✓] ${ipos.length} islem_goruyor IPO çekildi.');
      await _markStaticFetched();
      return ipos;
    } catch (e) {
      debugPrint('[Firestore] Okuma hatası: $e');
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

    // Firestore'dan taze veri çek
    final fresh = await _fetchFromFirestore();
    if (fresh == null || fresh.isEmpty) {
      // İndirme başarısız — cache'i kullan
      return cached;
    }

    // Artık ipos.json'un içerisinde semi-statik alanlar (sparkline, max, vb.) doğrudan yer alıyor.
    // Ancak eger GitHub'dan inen dosyada bazi alanlar bos ise diye onceki cache'den aktarmaca yapabiliriz.
    final cachedMap = {for (final i in cached) i.sirketKodu: i};
    for (final ipo in fresh) {
      if (ipo.staticFetched != true) {
        final old = cachedMap[ipo.sirketKodu];
        if (old != null && old.staticFetched == true) {
          ipo.ilkGunKapanis = old.ilkGunKapanis;
          ipo.maxFiyat = old.maxFiyat;
          ipo.minFiyat = old.minFiyat;
          ipo.tavanGunSayisi = old.tavanGunSayisi;
          ipo.sparkline = old.sparkline;
          ipo.staticFetched = old.staticFetched;
          ipo.staticFetchedAt = old.staticFetchedAt;
        }
      }

      // RTDB fiyatları ipos.json icinde gelmez, o yuzden eger varsa eski fiyatlari koru.
      // (Bunu loadAll cagrildiktan sonraki _fetchPrices asamasinda zaten tazeleyecegiz)
      final old = cachedMap[ipo.sirketKodu];
      if (old != null) {
        ipo.guncelFiyat = old.guncelFiyat;
        ipo.priceUpdatedAt = old.priceUpdatedAt;
      }
    }

    await saveToCache(fresh);
    return fresh;
  }

  static void applyRtdbPrices(
    List<HistoricalIpo> ipos,
    Map<String, double> prices,
  ) {
    for (final ipo in ipos) {
      final price = prices[ipo.sirketKodu];
      if (price != null) {
        ipo.guncelFiyat = price;
        ipo.priceUpdatedAt = DateTime.now();
        
        // Grafiğin de güncel fiyatla beslenmesi için son noktayı güncelle veya ekle
        if (ipo.sparkline.isNotEmpty) {
          final todayStr = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
          
          if (ipo.sparklineDates.isNotEmpty && ipo.sparklineDates.last.startsWith(todayStr)) {
            // Son nokta zaten bugünün verisi ise, üstüne yaz
            ipo.sparkline[ipo.sparkline.length - 1] = price;
          } else {
            // Bugünün verisi değilse, grafiğin sonuna bugünün anlık fiyatı olarak ekle
            ipo.sparkline.add(price);
            ipo.sparklineDates.add(DateTime.now().toIso8601String());
          }
        }
      }
    }
  }
}
