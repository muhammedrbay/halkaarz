import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

/// Son 1 yılda işlem gören halka arz hisselerinin verisi
class HistoricalIpo {
  final String sirketKodu;
  final String sirketAdi;
  final double arzFiyati;
  final DateTime islemTarihi;
  final bool katilimEndeksi;

  // Canlı (güncellenebilir)
  double? guncelFiyat;
  double? ilkGunFiyati;     // İlk gün kapanış
  List<double> sparkline;   // Son 30 günlük fiyat serisri
  DateTime? sonGuncelleme;

  HistoricalIpo({
    required this.sirketKodu,
    required this.sirketAdi,
    required this.arzFiyati,
    required this.islemTarihi,
    this.katilimEndeksi = false,
    this.guncelFiyat,
    this.ilkGunFiyati,
    this.sparkline = const [],
    this.sonGuncelleme,
  });

  /// Arz fiyatına göre getiri yüzdesi
  double get getiviYuzde {
    if (guncelFiyat == null || arzFiyati <= 0) return 0;
    return ((guncelFiyat! - arzFiyati) / arzFiyati) * 100;
  }

  /// İlk günden beri değişim
  double get ilkGundenGetiri {
    if (guncelFiyat == null || ilkGunFiyati == null || ilkGunFiyati! <= 0) return 0;
    return ((guncelFiyat! - ilkGunFiyati!) / ilkGunFiyati!) * 100;
  }

  /// Bugün tavanda mı? (dünkü kapanışa göre %9.5+)
  bool get tavanMi {
    if (sparkline.length < 2 || guncelFiyat == null) return false;
    final prev = sparkline[sparkline.length - 2];
    if (prev <= 0) return false;
    return (guncelFiyat! - prev) / prev >= 0.095;
  }

  /// JSON'dan oku (Hive cache)
  factory HistoricalIpo.fromJson(Map<String, dynamic> j) {
    return HistoricalIpo(
      sirketKodu: j['sirket_kodu'] ?? '',
      sirketAdi: j['sirket_adi'] ?? '',
      arzFiyati: (j['arz_fiyati'] ?? 0).toDouble(),
      islemTarihi: DateTime.tryParse(j['islem_tarihi'] ?? '') ?? DateTime.now(),
      katilimEndeksi: j['katilim_endeksi'] ?? false,
      guncelFiyat: j['guncel_fiyat']?.toDouble(),
      ilkGunFiyati: j['ilk_gun_fiyati']?.toDouble(),
      sparkline: (j['sparkline'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
      sonGuncelleme: j['son_guncelleme'] != null ? DateTime.tryParse(j['son_guncelleme']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'sirket_kodu': sirketKodu,
    'sirket_adi': sirketAdi,
    'arz_fiyati': arzFiyati,
    'islem_tarihi': islemTarihi.toIso8601String(),
    'katilim_endeksi': katilimEndeksi,
    'guncel_fiyat': guncelFiyat,
    'ilk_gun_fiyati': ilkGunFiyati,
    'sparkline': sparkline,
    'son_guncelleme': sonGuncelleme?.toIso8601String(),
  };
}

/// Son 1 yılın halka arz verisini yöneten servis
class HistoricalIpoService {
  static const String _boxName = 'historical_ipos';

  // Bilinen son 1 yılın halka arzları — statik sabit liste.
  // Scraper bu listeyi güncel tutar; uygulama buradan başlar.
  static const List<Map<String, dynamic>> _knownIpos = [
    // 2026
    {'kod': 'ATATR', 'ad': 'Ata Turizm İşletmecilik A.Ş.', 'fiyat': 40.0, 'tarih': '2026-02-20', 'katilim': false},
    {'kod': 'BESTE', 'ad': 'Best Brands Grup Enerji A.Ş.', 'fiyat': 28.0, 'tarih': '2026-02-11', 'katilim': false},
    {'kod': 'NETCD', 'ad': 'Netcad Yazılım A.Ş.', 'fiyat': 110.0, 'tarih': '2026-02-05', 'katilim': false},
    {'kod': 'UCAYM', 'ad': 'Üçay Mühendislik A.Ş.', 'fiyat': 65.0, 'tarih': '2026-01-22', 'katilim': false},
    {'kod': 'ZGYO', 'ad': 'Z Gayrimenkul Yatırım Ortaklığı', 'fiyat': 14.5, 'tarih': '2026-01-16', 'katilim': false},
    {'kod': 'FRMPL', 'ad': 'Formül Plastik ve Metal San. A.Ş.', 'fiyat': 38.5, 'tarih': '2026-01-15', 'katilim': false},
    {'kod': 'MEYSU', 'ad': 'Meysu Gıda San. ve Tic. A.Ş.', 'fiyat': 52.0, 'tarih': '2026-01-13', 'katilim': false},
    {'kod': 'ARFYE', 'ad': 'ARF Bio Yenilenebilir Enerji A.Ş.', 'fiyat': 30.0, 'tarih': '2026-01-05', 'katilim': false},
    // 2025
    {'kod': 'VAKFA', 'ad': 'Vakıf Faktoring A.Ş.', 'fiyat': 14.5, 'tarih': '2025-11-20', 'katilim': false},
    {'kod': 'ECOGR', 'ad': 'Ecogreen Enerji Holding A.Ş.', 'fiyat': 24.0, 'tarih': '2025-11-03', 'katilim': false},
    {'kod': 'DOFRI', 'ad': 'Dof Robotik Sanayi A.Ş.', 'fiyat': 48.0, 'tarih': '2025-10-15', 'katilim': false},
    {'kod': 'GLRMK', 'ad': 'Gülermak Ağır Sanayi A.Ş.', 'fiyat': 85.0, 'tarih': '2025-09-20', 'katilim': false},
    {'kod': 'AKFEN', 'ad': 'Akfen İnşaat Turizm A.Ş.', 'fiyat': 42.0, 'tarih': '2025-08-15', 'katilim': false},
    {'kod': 'ENDRA', 'ad': 'Enda Enerji Holding A.Ş.', 'fiyat': 96.0, 'tarih': '2025-07-10', 'katilim': false},
    {'kod': 'GWIND', 'ad': 'Galata Wind Enerji A.Ş.', 'fiyat': 75.0, 'tarih': '2025-06-05', 'katilim': true},
    {'kod': 'ODAS', 'ad': 'Odaş Elektrik Üretim A.Ş.', 'fiyat': 38.0, 'tarih': '2025-05-22', 'katilim': false},
    {'kod': 'RBAIN', 'ad': 'RBA İnşaat A.Ş.', 'fiyat': 22.0, 'tarih': '2025-04-10', 'katilim': false},
    {'kod': 'KARYE', 'ad': 'Karya Enerji A.Ş.', 'fiyat': 16.0, 'tarih': '2025-03-20', 'katilim': true},
    {'kod': 'DMRGD', 'ad': 'Demir Global Girişim A.Ş.', 'fiyat': 34.0, 'tarih': '2025-03-01', 'katilim': false},
    {'kod': 'EUREN', 'ad': 'Eur-Enerji A.Ş.', 'fiyat': 19.5, 'tarih': '2025-02-15', 'katilim': false},
  ];

  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  /// Cache'den mevcut veriyi oku
  static List<HistoricalIpo> loadFromCache() {
    final box = Hive.box(_boxName);
    final raw = box.get('data');
    if (raw == null) return [];
    try {
      final list = json.decode(raw as String) as List;
      return list.map((e) => HistoricalIpo.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveToCache(List<HistoricalIpo> ipos) async {
    final box = Hive.box(_boxName);
    await box.put('data', json.encode(ipos.map((e) => e.toJson()).toList()));
  }

  /// Fiyat cache'inin bayat olup olmadığını kontrol et (>15 dk)
  static bool _isPriceStale(HistoricalIpo ipo) {
    if (ipo.sonGuncelleme == null) return true;
    return DateTime.now().difference(ipo.sonGuncelleme!) > const Duration(minutes: 15);
  }

  /// Sparkline'ın bayat olup olmadığını kontrol et (>1 gün)
  static bool _isSparklineStale(HistoricalIpo ipo) {
    if (ipo.sonGuncelleme == null || ipo.sparkline.isEmpty) return true;
    return DateTime.now().difference(ipo.sonGuncelleme!) > const Duration(hours: 24);
  }

  /// Yahoo Finance'den güncel fiyat + sparkline çek
  static Future<_PriceResult?> _fetchYahooData(String ticker, {bool withHistory = false}) async {
    try {
      final symbol = '${ticker.toUpperCase()}.IS';
      final range = withHistory ? '1mo' : '1d';
      final interval = withHistory ? '1d' : '1d';
      final url = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol'
        '?interval=$interval&range=$range',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; HalkaArzTakip/1.0)',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final result = data['chart']?['result'];
      if (result == null || (result as List).isEmpty) return null;

      final meta = result[0]['meta'] as Map?;
      final currentPrice = (meta?['regularMarketPrice'] as num?)?.toDouble();
      if (currentPrice == null) return null;

      List<double> closes = [];
      if (withHistory) {
        final indicators = result[0]['indicators'] as Map?;
        final quoteList = indicators?['quote'] as List?;
        if (quoteList != null && quoteList.isNotEmpty) {
          final closeList = (quoteList[0] as Map)['close'] as List?;
          if (closeList != null) {
            closes = closeList
                .whereType<num>()
                .map((e) => e.toDouble())
                .toList();
          }
        }
      }

      return _PriceResult(currentPrice: currentPrice, closes: closes);
    } catch (e) {
      debugPrint('Yahoo veri hatası ($ticker): $e');
      return null;
    }
  }

  /// İlk yükleme: statik listeyi merge et, eksik fiyatları çek
  static Future<List<HistoricalIpo>> fetchAll({
    void Function(int done, int total)? onProgress,
  }) async {
    // Mevcut cache'i yükle
    final cached = {for (final i in loadFromCache()) i.sirketKodu: i};

    // Statik listeyi base olarak al
    final result = <HistoricalIpo>[];
    int done = 0;

    for (final known in _knownIpos) {
      final kod = known['kod'] as String;
      final existing = cached[kod];

      final ipo = existing ?? HistoricalIpo(
        sirketKodu: kod,
        sirketAdi: known['ad'] as String,
        arzFiyati: (known['fiyat'] as num).toDouble(),
        islemTarihi: DateTime.parse(known['tarih'] as String),
        katilimEndeksi: known['katilim'] as bool,
      );

      // Fiyat ya bayatsa ya da hiç yoksa çek
      final needsPrice = _isPriceStale(ipo);
      final needsSparkline = _isSparklineStale(ipo);

      if (needsPrice || needsSparkline) {
        final priceData = await _fetchYahooData(kod, withHistory: needsSparkline);
        if (priceData != null) {
          ipo.guncelFiyat = priceData.currentPrice;
          ipo.sonGuncelleme = DateTime.now();
          if (needsSparkline && priceData.closes.isNotEmpty) {
            ipo.sparkline = priceData.closes;
            // İlk gün fiyatı: sparkline'ın ilk değeri (yaklaşım)
            if (ipo.ilkGunFiyati == null) {
              ipo.ilkGunFiyati = priceData.closes.first;
            }
          }
        }
        await Future.delayed(const Duration(milliseconds: 300)); // rate limit
      }

      result.add(ipo);
      done++;
      onProgress?.call(done, _knownIpos.length);
    }

    await _saveToCache(result);
    return result;
  }

  /// Sadece canlı fiyatları güncelle (sparkline dokunma)
  static Future<List<HistoricalIpo>> refreshPrices(List<HistoricalIpo> ipos) async {
    for (final ipo in ipos) {
      if (!_isPriceStale(ipo)) continue;
      final priceData = await _fetchYahooData(ipo.sirketKodu, withHistory: false);
      if (priceData != null) {
        ipo.guncelFiyat = priceData.currentPrice;
        ipo.sonGuncelleme = DateTime.now();
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _saveToCache(ipos);
    return ipos;
  }
}

class _PriceResult {
  final double currentPrice;
  final List<double> closes;
  _PriceResult({required this.currentPrice, required this.closes});
}
