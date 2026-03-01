import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/ipo_model.dart';

/// Halka arz verilerini GitHub'dan çeker ve yerel Hive'a kaydeder.
class DataService {
  static const String _boxName = 'ipos';

  // GitHub raw URL — Kendi repo adresinizi buraya yazın
  static const String _rawUrl =
      'https://raw.githubusercontent.com/muhammedrbay/halkaarz_mobil/main/backend/data/ipos.json';

  // Fallback: Yerel asset (uygulama ilk açılış)
  static const String _fallbackAsset = 'assets/ipos.json';

  /// Hive kutusunu başlat
  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  /// GitHub'dan IPO verilerini çek (Günde 1 kez)
  static Future<List<IpoModel>> fetchFromRemote() async {
    final box = Hive.box(_boxName);
    final lastFetch = box.get('last_fetch_time') as String?;

    // Aynı gün içinde tekrar açıldıysa GitHub'a gitmeden lokalden oku
    if (lastFetch != null) {
      final lastDate = DateTime.tryParse(lastFetch);
      if (lastDate != null) {
        final now = DateTime.now();
        if (lastDate.year == now.year &&
            lastDate.month == now.month &&
            lastDate.day == now.day) {
          final localData = await loadFromLocal();
          if (localData.isNotEmpty) {
            print('[DataService] Bugün zaten çekilmiş, lokal cache kullanılıyor.');
            return localData;
          }
        }
      }
    }

    try {
      print('[DataService] İnternetten yeni veri çekiliyor...');
      final response = await http
          .get(Uri.parse(_rawUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        final ipos = _removeDummyEntries(
          jsonList.map((j) => IpoModel.fromJson(j)).toList(),
        );

        // Yerel Hive'a kaydet ve son çekilme zamanını güncelle
        await _saveToLocal(ipos);
        await box.put('last_fetch_time', DateTime.now().toIso8601String());

        return ipos;
      }
    } catch (e) {
      // Hata durumunda yerel veriden oku
      print('[DataService] Remote veri çekilemedi: $e');
    }
    return loadFromLocal();
  }

  /// Yerel Hive'dan IPO verilerini oku
  static Future<List<IpoModel>> loadFromLocal() async {
    final box = Hive.box(_boxName);
    final data = box.get('ipos_data');
    if (data == null) return [];
    try {
      final List<dynamic> jsonList = json.decode(data);
      return _removeDummyEntries(
        jsonList.map((j) => IpoModel.fromJson(j)).toList(),
      );
    } catch (_) {
      return [];
    }
  }

  /// Deneme/test amaçlı girişleri filtrele
  static List<IpoModel> _removeDummyEntries(List<IpoModel> ipos) {
    return ipos.where((ipo) {
      final kodOk = ipo.sirketKodu.toUpperCase() != 'ORNEK';
      final adOk = !ipo.sirketAdi.toLowerCase().contains('örnek');
      return kodOk && adOk;
    }).toList();
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
}
