import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/ipo_model.dart';

/// Halka arz verilerini GitHub'dan çeker ve yerel Hive'a kaydeder.
class DataService {
  static const String _boxName = 'ipos';

  // GitHub raw URL — Kendi repo adresinizi buraya yazın
  static const String _rawUrl =
      'https://raw.githubusercontent.com/muhammedrbay/halkaarz/main/backend/data/ipos.json';

  // Fallback: Yerel asset (uygulama ilk açılış)
  static const String _fallbackAsset = 'assets/ipos.json';

  /// Hive kutusunu başlat
  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  /// GitHub'dan IPO verilerini çek
  static Future<List<IpoModel>> fetchFromRemote() async {
    try {
      final response = await http
          .get(Uri.parse(_rawUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        final ipos = jsonList.map((j) => IpoModel.fromJson(j)).toList();

        // Yerel Hive'a kaydet
        await _saveToLocal(ipos);

        return ipos;
      }
    } catch (e) {
      // Hata durumunda yerel veriden oku
      print('Remote veri çekilemedi: $e');
    }
    return loadFromLocal();
  }

  /// Yerel Hive'dan IPO verilerini oku
  static Future<List<IpoModel>> loadFromLocal() async {
    final box = Hive.box(_boxName);
    final data = box.get('ipos_data');
    if (data == null) return _getSampleData();
    try {
      final List<dynamic> jsonList = json.decode(data);
      return jsonList.map((j) => IpoModel.fromJson(j)).toList();
    } catch (_) {
      return _getSampleData();
    }
  }

  /// Verileri Hive'a kaydet
  static Future<void> _saveToLocal(List<IpoModel> ipos) async {
    final box = Hive.box(_boxName);
    final jsonStr = json.encode(ipos.map((i) => i.toJson()).toList());
    await box.put('ipos_data', jsonStr);
  }

  /// Duruma göre filtrele
  static List<IpoModel> filterByDurum(List<IpoModel> ipos, String durum) {
    return ipos.where((i) => i.durum == durum).toList();
  }

  /// Katılım endeksi filtresi
  static List<IpoModel> filterKatilimEndeksi(List<IpoModel> ipos) {
    return ipos.where((i) => i.katilimEndeksineUygun).toList();
  }

  /// Örnek veri (uygulama ilk açılışta veya hata durumunda)
  static List<IpoModel> _getSampleData() {
    final sampleJson = [
      {
        "sirket_kodu": "ORNEK",
        "sirket_adi": "Örnek Teknoloji A.Ş.",
        "arz_fiyati": 32.50,
        "toplam_lot": 75000,
        "dagitim_sekli": "Eşit",
        "konsorsiyum_lideri": "ABC Yatırım",
        "iskonto_orani": 20.0,
        "fon_kullanim_yeri": {
          "yatirim": 55,
          "borc_odeme": 30,
          "isletme_sermayesi": 15,
        },
        "katilim_endeksine_uygun": true,
        "talep_baslangic": "2026-03-01T09:00:00",
        "talep_bitis": "2026-03-03T17:00:00",
        "borsada_islem_tarihi": "2026-03-10",
        "durum": "talep_topluyor",
        "son_katilimci_sayilari": [125000, 98000, 145000],
        "guncelleme_zamani": "2026-02-20T18:00:00",
      },
      {
        "sirket_kodu": "DEMO",
        "sirket_adi": "Demo Enerji A.Ş.",
        "arz_fiyati": 15.75,
        "toplam_lot": 120000,
        "dagitim_sekli": "Oransal",
        "konsorsiyum_lideri": "XYZ Menkul",
        "iskonto_orani": 12.5,
        "fon_kullanim_yeri": {
          "yatirim": 40,
          "borc_odeme": 35,
          "isletme_sermayesi": 25,
        },
        "katilim_endeksine_uygun": false,
        "talep_baslangic": "2026-03-05T09:00:00",
        "talep_bitis": "2026-03-07T17:00:00",
        "borsada_islem_tarihi": "2026-03-14",
        "durum": "taslak",
        "son_katilimci_sayilari": [125000, 98000, 145000],
        "guncelleme_zamani": "2026-02-20T18:00:00",
      },
      {
        "sirket_kodu": "TEST",
        "sirket_adi": "Test Gıda Sanayi A.Ş.",
        "arz_fiyati": 48.00,
        "toplam_lot": 40000,
        "dagitim_sekli": "Eşit",
        "konsorsiyum_lideri": "Büyük Yatırım",
        "iskonto_orani": 18.0,
        "fon_kullanim_yeri": {
          "yatirim": 70,
          "borc_odeme": 20,
          "isletme_sermayesi": 10,
        },
        "katilim_endeksine_uygun": true,
        "talep_baslangic": "2026-02-10T09:00:00",
        "talep_bitis": "2026-02-12T17:00:00",
        "borsada_islem_tarihi": "2026-02-19",
        "durum": "islem_goruyor",
        "son_katilimci_sayilari": [110000, 87000, 132000],
        "guncelleme_zamani": "2026-02-19T10:00:00",
      },
    ];
    return sampleJson.map((j) => IpoModel.fromJson(j)).toList();
  }
}
