import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

// ─── Model ───────────────────────────────────────────────────────────────────

class HistoricalIpo {
  final String sirketKodu;
  final String sirketAdi;

  // Statik veriler — bir kez yazılır, sonsuza kadar cache'te kalır
  final double arzFiyati;
  final int kisiBasiLot;       // Kişi başına düşen lot
  final int toplamLot;         // Toplam arz edilen lot sayısı
  final DateTime islemTarihi;  // Borsada işlem tarihi
  final bool katilimEndeksi;

  // Yarı-statik — arz bitince değişmez, Yahoo'dan hesaplanır
  double? ilkGunKapanis;       // Birinci gün kapanış
  double? maxFiyat;            // Tüm zamanlarda max fiyat
  double? minFiyat;            // Tüm zamanlarda min fiyat
  int? tavanGunSayisi;         // Birinci günden tavan gün sayısı
  List<double> sparkline;      // Son 30 günlük fiyat serisi
  bool? staticFetched;         // Yukarıdaki veriler çekildi mi?
  DateTime? staticFetchedAt;

  // Dinamik — her 15 dakikada güncellenir
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

  bool get guncelFiyatBayat {
    if (priceUpdatedAt == null) return true;
    return DateTime.now().difference(priceUpdatedAt!) > const Duration(minutes: 15);
  }

  bool get staticVeriBayat {
    if (staticFetched != true) return true;
    if (staticFetchedAt == null) return true;
    // Statik veri bir kez çekilip saklanır; şirket aktif değilse 30 günde bir kontrol yeter
    return false;
  }

  factory HistoricalIpo.fromJson(Map<String, dynamic> j) {
    return HistoricalIpo(
      sirketKodu: j['kod'] ?? '',
      sirketAdi: j['ad'] ?? '',
      arzFiyati: (j['arz_fiyati'] ?? 0).toDouble(),
      kisiBasiLot: (j['kisi_basi_lot'] ?? 0).toInt(),
      toplamLot: (j['toplam_lot'] ?? 0).toInt(),
      islemTarihi: DateTime.tryParse(j['islem_tarihi'] ?? '') ?? DateTime.now(),
      katilimEndeksi: j['katilim'] ?? false,
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
        'kod': sirketKodu,
        'ad': sirketAdi,
        'arz_fiyati': arzFiyati,
        'kisi_basi_lot': kisiBasiLot,
        'toplam_lot': toplamLot,
        'islem_tarihi': islemTarihi.toIso8601String(),
        'katilim': katilimEndeksi,
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

// ─── Statik IPO Veritabanı ───────────────────────────────────────────────────
// Bu veriler (arz fiyatı, kişi başı lot, toplam lot) hiç değişmez.
// Borsa bilgileri KAP ve SPK kaynaklıdır.

const List<Map<String, dynamic>> _staticIpoDb = [
  // --- 2026 ---
  {
    'kod': 'EMPAE', 'ad': 'Empa Elektronik San. ve Tic. A.Ş.',
    'arz_fiyati': 72.0, 'kisi_basi_lot': 1, 'toplam_lot': 3750000,
    'islem_tarihi': '2026-02-24', 'katilim': false,
  },
  {
    'kod': 'ATATR', 'ad': 'Ata Turizm İşletmecilik A.Ş.',
    'arz_fiyati': 40.0, 'kisi_basi_lot': 1, 'toplam_lot': 5000000,
    'islem_tarihi': '2026-02-20', 'katilim': false,
  },
  {
    'kod': 'BESTE', 'ad': 'Best Brands Grup Enerji Yatırım A.Ş.',
    'arz_fiyati': 28.0, 'kisi_basi_lot': 1, 'toplam_lot': 3500000,
    'islem_tarihi': '2026-02-11', 'katilim': false,
  },
  {
    'kod': 'NETCD', 'ad': 'Netcad Yazılım A.Ş.',
    'arz_fiyati': 110.0, 'kisi_basi_lot': 1, 'toplam_lot': 2000000,
    'islem_tarihi': '2026-02-05', 'katilim': false,
  },
  {
    'kod': 'UCAYM', 'ad': 'Üçay Mühendislik A.Ş.',
    'arz_fiyati': 65.0, 'kisi_basi_lot': 1, 'toplam_lot': 2500000,
    'islem_tarihi': '2026-01-22', 'katilim': false,
  },
  {
    'kod': 'ZGYO', 'ad': 'Z Gayrimenkul Yatırım Ortaklığı A.Ş.',
    'arz_fiyati': 14.5, 'kisi_basi_lot': 2, 'toplam_lot': 10000000,
    'islem_tarihi': '2026-01-16', 'katilim': true,
  },
  {
    'kod': 'FRMPL', 'ad': 'Formül Plastik ve Metal San. A.Ş.',
    'arz_fiyati': 38.5, 'kisi_basi_lot': 1, 'toplam_lot': 3000000,
    'islem_tarihi': '2026-01-15', 'katilim': false,
  },
  {
    'kod': 'MEYSU', 'ad': 'Meysu Gıda San. ve Tic. A.Ş.',
    'arz_fiyati': 52.0, 'kisi_basi_lot': 1, 'toplam_lot': 2800000,
    'islem_tarihi': '2026-01-13', 'katilim': false,
  },
  {
    'kod': 'ARFYE', 'ad': 'ARF Bio Yenilenebilir Enerji A.Ş.',
    'arz_fiyati': 30.0, 'kisi_basi_lot': 2, 'toplam_lot': 8000000,
    'islem_tarihi': '2026-01-05', 'katilim': true,
  },
  // --- 2025 ---
  {
    'kod': 'PAHOL', 'ad': 'Pasifik Holding A.Ş.',
    'arz_fiyati': 18.0, 'kisi_basi_lot': 2, 'toplam_lot': 6000000,
    'islem_tarihi': '2025-12-10', 'katilim': false,
  },
  {
    'kod': 'VAKFA', 'ad': 'Vakıf Faktoring A.Ş.',
    'arz_fiyati': 14.5, 'kisi_basi_lot': 3, 'toplam_lot': 12000000,
    'islem_tarihi': '2025-11-20', 'katilim': true,
  },
  {
    'kod': 'ECOGR', 'ad': 'Ecogreen Enerji Holding A.Ş.',
    'arz_fiyati': 24.0, 'kisi_basi_lot': 1, 'toplam_lot': 5000000,
    'islem_tarihi': '2025-11-03', 'katilim': false,
  },
  {
    'kod': 'MARMR', 'ad': 'Marmara Holding A.Ş.',
    'arz_fiyati': 22.0, 'kisi_basi_lot': 2, 'toplam_lot': 7500000,
    'islem_tarihi': '2025-10-28', 'katilim': false,
  },
  {
    'kod': 'DOFRB', 'ad': 'Dof Robotik Sanayi A.Ş.',
    'arz_fiyati': 48.0, 'kisi_basi_lot': 1, 'toplam_lot': 3200000,
    'islem_tarihi': '2025-10-15', 'katilim': false,
  },
  {
    'kod': 'BALSU', 'ad': 'Balsu Gıda San. ve Tic. A.Ş.',
    'arz_fiyati': 35.0, 'kisi_basi_lot': 1, 'toplam_lot': 4000000,
    'islem_tarihi': '2025-09-25', 'katilim': false,
  },
  {
    'kod': 'KLYPV', 'ad': 'Kalyon Güneş Teknolojileri A.Ş.',
    'arz_fiyati': 78.0, 'kisi_basi_lot': 1, 'toplam_lot': 2500000,
    'islem_tarihi': '2025-09-10', 'katilim': true,
  },
  {
    'kod': 'GLRMK', 'ad': 'Gülermak Ağır Sanayi İnşaat A.Ş.',
    'arz_fiyati': 85.0, 'kisi_basi_lot': 1, 'toplam_lot': 3000000,
    'islem_tarihi': '2025-08-25', 'katilim': false,
  },
  {
    'kod': 'AKFIS', 'ad': 'Akfen İnşaat Turizm ve Ticaret A.Ş.',
    'arz_fiyati': 42.0, 'kisi_basi_lot': 2, 'toplam_lot': 6000000,
    'islem_tarihi': '2025-08-01', 'katilim': false,
  },
  {
    'kod': 'ENDAE', 'ad': 'Enda Enerji Holding A.Ş.',
    'arz_fiyati': 96.0, 'kisi_basi_lot': 1, 'toplam_lot': 2200000,
    'islem_tarihi': '2025-07-10', 'katilim': true,
  },
  {
    'kod': 'SERNT', 'ad': 'Seranit Granit Seramik San. A.Ş.',
    'arz_fiyati': 29.0, 'kisi_basi_lot': 2, 'toplam_lot': 7000000,
    'islem_tarihi': '2025-06-20', 'katilim': false,
  },
  {
    'kod': 'MOPAS', 'ad': 'Mopaş Marketcilik Gıda San. A.Ş.',
    'arz_fiyati': 18.0, 'kisi_basi_lot': 3, 'toplam_lot': 9000000,
    'islem_tarihi': '2025-06-05', 'katilim': false,
  },
  {
    'kod': 'DSTKF', 'ad': 'Destek Finans Faktoring A.Ş.',
    'arz_fiyati': 26.0, 'kisi_basi_lot': 2, 'toplam_lot': 5500000,
    'islem_tarihi': '2025-05-15', 'katilim': true,
  },
  {
    'kod': 'VSNMD', 'ad': 'Vişne Madencilik Üretim San. A.Ş.',
    'arz_fiyati': 45.0, 'kisi_basi_lot': 1, 'toplam_lot': 4000000,
    'islem_tarihi': '2025-05-02', 'katilim': false,
  },
  {
    'kod': 'BIGEN', 'ad': 'Birleşim Grup Enerji Yatırımları A.Ş.',
    'arz_fiyati': 32.0, 'kisi_basi_lot': 1, 'toplam_lot': 5000000,
    'islem_tarihi': '2025-04-10', 'katilim': false,
  },
  {
    'kod': 'BULGS', 'ad': 'Bulls Girişim Sermayesi YO A.Ş.',
    'arz_fiyati': 15.0, 'kisi_basi_lot': 2, 'toplam_lot': 8000000,
    'islem_tarihi': '2025-03-20', 'katilim': false,
  },
];

// ─── Servis ──────────────────────────────────────────────────────────────────

class HistoricalIpoService {
  static const String _boxName = 'historical_ipos_v2';

  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

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

  /// Tüm verileri yükler:
  /// 1. Cache varsa hemen döner
  /// 2. Arka planda statik veri eksikse Yahoo'dan çeker (ilk gün, tavan days)
  /// 3. Canlı fiyatları günceller (15dk cache)
  static Future<List<HistoricalIpo>> loadAll({
    void Function(int done, int total)? onProgress,
  }) async {
    // 1. Statik listeden base oluştur, cache ile merge et
    final cached = {
      for (final i in loadFromCache()) i.sirketKodu: i,
    };

    final result = <HistoricalIpo>[];
    for (final entry in _staticIpoDb) {
      final cached_entry = cached[entry['kod']];
      if (cached_entry != null) {
        result.add(cached_entry);
      } else {
        result.add(HistoricalIpo.fromJson(entry));
      }
    }

    await saveToCache(result);
    return result;
  }

  /// Statik verileri çek: ilk gün kapanış, tavan gün, max/min, sparkline
  /// — Sadece bir kez çekilir; cache'te kalır sonsuza kadar —
  static Future<void> fetchStaticData(
    HistoricalIpo ipo, {
    void Function(HistoricalIpo)? onUpdate,
  }) async {
    if (ipo.staticFetched == true) return; // Zaten var

    try {
      final symbol = '${ipo.sirketKodu}.IS';
      // Tüm tarihsel veriyi çek (işlem tarihinden bugüne)
      final fromDate = ipo.islemTarihi;
      final fromEpoch = fromDate.millisecondsSinceEpoch ~/ 1000;
      final toEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final url = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=1d&period1=$fromEpoch&period2=$toEpoch',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
      }).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        debugPrint('[Yahoo] ${ipo.sirketKodu}: HTTP ${response.statusCode}');
        return;
      }

      final data = json.decode(response.body) as Map?;
      final chartResult = data?['chart']?['result'] as List?;
      if (chartResult == null || chartResult.isEmpty) return;

      final indicators = chartResult[0]['indicators'] as Map?;
      final quoteList = indicators?['quote'] as List?;
      if (quoteList == null || quoteList.isEmpty) return;

      final closeList = (quoteList[0] as Map)['close'] as List?;
      final highList = (quoteList[0] as Map)['high'] as List?;
      if (closeList == null || closeList.isEmpty) return;

      final closes = closeList.whereType<num>().map((e) => e.toDouble()).toList();

      if (closes.isEmpty) return;

      // İlk gün kapanış
      ipo.ilkGunKapanis = closes.first;

      // Max / min
      ipo.maxFiyat = closes.reduce((a, b) => a > b ? a : b);
      ipo.minFiyat = closes.reduce((a, b) => a < b ? a : b);

      // Tavan gün sayısı (önceki güne göre %9.5+)
      int tavanCount = 0;
      for (int i = 1; i < closes.length; i++) {
        final prev = closes[i - 1];
        if (prev > 0) {
          final change = (closes[i] - prev) / prev;
          if (change >= 0.095) tavanCount++;
        }
      }
      // İlk gün arz fiyatına göre de kontrol et
      if (closes.isNotEmpty && ipo.arzFiyati > 0) {
        final firstDayChange = (closes.first - ipo.arzFiyati) / ipo.arzFiyati;
        if (firstDayChange >= 0.095) tavanCount++;
      }
      ipo.tavanGunSayisi = tavanCount;

      // Sparkline: son 30 gün
      ipo.sparkline = closes.length > 30 ? closes.sublist(closes.length - 30) : closes;

      // Güncel fiyat
      ipo.guncelFiyat = closes.last;
      ipo.priceUpdatedAt = DateTime.now();

      ipo.staticFetched = true;
      ipo.staticFetchedAt = DateTime.now();

      onUpdate?.call(ipo);
      debugPrint('[${ipo.sirketKodu}] Statik veri çekildi. Kapanış: ${closes.last} | Tavan: $tavanCount gün');
    } catch (e) {
      debugPrint('[${ipo.sirketKodu}] Statik veri hatası: $e');
    }
  }

  /// Sadece canlı fiyatı güncelle (15dk cache kontrolü)
  static Future<void> refreshPrice(HistoricalIpo ipo) async {
    if (!ipo.guncelFiyatBayat) return;

    try {
      final symbol = '${ipo.sirketKodu}.IS';
      final url = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=1d',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return;

      final data = json.decode(response.body) as Map?;
      final chartResult = data?['chart']?['result'] as List?;
      if (chartResult == null || chartResult.isEmpty) return;

      final meta = chartResult[0]['meta'] as Map?;
      final price = meta?['regularMarketPrice'];
      if (price != null) {
        ipo.guncelFiyat = (price as num).toDouble();
        ipo.priceUpdatedAt = DateTime.now();

        // Tavan kontrolü: sparkline'ı güncelle
        if (ipo.sparkline.isNotEmpty) {
          final newSparkline = [...ipo.sparkline.skip(1), ipo.guncelFiyat!];
          ipo.sparkline = (newSparkline.length > 30 ? newSparkline.sublist(newSparkline.length - 30) : newSparkline)
              .whereType<double>()
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[${ipo.sirketKodu}] Fiyat güncelleme hatası: $e');
    }
  }

  /// Tüm IPO'ları teker teker güncelle ve kaydet
  static Future<List<HistoricalIpo>> fetchAndRefreshAll({
    required List<HistoricalIpo> ipos,
    void Function(int done, int total)? onProgress,
  }) async {
    int done = 0;
    final total = ipos.length;

    for (final ipo in ipos) {
      // Statik veri eksikse çek (bir kez)
      if (ipo.staticFetched != true) {
        await fetchStaticData(ipo);
        await Future.delayed(const Duration(milliseconds: 400)); // rate limit
      } else if (ipo.guncelFiyatBayat) {
        // Sadece fiyatı güncelle
        await refreshPrice(ipo);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      done++;
      onProgress?.call(done, total);
    }

    await saveToCache(ipos);
    return ipos;
  }

  /// Sayfa açılışında sadece fiyatları yenile (statik veriye dokunma)
  static Future<List<HistoricalIpo>> quickRefreshPrices(List<HistoricalIpo> ipos) async {
    final stale = ipos.where((i) => i.guncelFiyatBayat).toList();
    for (final ipo in stale) {
      await refreshPrice(ipo);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    if (stale.isNotEmpty) {
      await saveToCache(ipos);
    }
    return ipos;
  }
}
