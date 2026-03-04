import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/ipo_model.dart';
import 'package:flutter/foundation.dart';

/// Firestore 'halka_arzlar' koleksiyonundan TÜM halka arzları çeker.
/// Günlük 1 defa server maliyeti yapmak için agresif cache uygulanır.
class IpoService {
  static const String _boxName = 'ipo_cache_meta';
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  /// Firestore'dan verileri çeker. Günde 1x server, sonrası cache.
  static Future<List<IpoModel>> getIpos() async {
    final box = Hive.box(_boxName);
    
    // İlk çalıştırmada her zaman server'dan çek
    bool shouldFetchFromServer = true;

    try {
      debugPrint('[IpoService] halka_arzlar koleksiyonundan veri çekiliyor (server)...');
      
      final snapshot = await _db.collection('halka_arzlar')
          .get(const GetOptions(source: Source.serverAndCache));
      
      debugPrint('[IpoService] Firestore döndü: ${snapshot.docs.length} doküman');
      
      if (snapshot.docs.isEmpty) {
        debugPrint('[IpoService] ❌ halka_arzlar koleksiyonu boş!');
        return [];
      }
      
      await box.put('last_firestore_fetch', DateTime.now().toIso8601String());
      
      final List<IpoModel> results = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['sirket_kodu'] = doc.id;
        try {
          results.add(IpoModel.fromJson(data));
        } catch (e) {
          debugPrint('[IpoService] ❌ Model Parse Hatası (${doc.id}): $e');
        }
      }
      
      debugPrint('[IpoService] ✅ ${results.length} IPO başarıyla parse edildi');
      debugPrint('[IpoService] Durumlar: ${results.map((r) => '${r.sirketKodu}=${r.durum}').join(', ')}');
      
      return results;
      
    } catch (e) {
      debugPrint('[IpoService] Firestore bağlantı hatası: $e');
      
      try {
        final fallbackSnapshot = await _db.collection('halka_arzlar').get(const GetOptions(source: Source.cache));
        return fallbackSnapshot.docs
            .map((d) {
               final data = d.data();
               data['sirket_kodu'] = d.id;
               return IpoModel.fromJson(data);
            })
            .toList();
      } catch (e2) {
        debugPrint('[IpoService] Cache fallback başarısız: $e2');
        return [];
      }
    }
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
