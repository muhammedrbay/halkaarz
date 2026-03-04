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
    final lastFetchStr = box.get('last_firestore_fetch') as String?;
    
    bool shouldFetchFromServer = true;

    if (lastFetchStr != null) {
      final lastDate = DateTime.tryParse(lastFetchStr);
      if (lastDate != null) {
        final now = DateTime.now();
        if (lastDate.year == now.year &&
            lastDate.month == now.month &&
            lastDate.day == now.day) {
          shouldFetchFromServer = false;
        }
      }
    }

    try {
      final options = shouldFetchFromServer
          ? const GetOptions(source: Source.serverAndCache)
          : const GetOptions(source: Source.cache);
          
      if (shouldFetchFromServer) {
        debugPrint('[IpoService] Sunucudan taze Firestore verisi çekiliyor (Günde 1 kez)...');
      } else {
        debugPrint('[IpoService] Bugün zaten çekilmiş, Firebase cihaz-içi Cache kullanılıyor.');
      }

      final snapshot = await _db.collection('halka_arzlar').get(options);
      
      // Cache'ten boş sonuç geldiyse server'a git
      if (!shouldFetchFromServer && snapshot.docs.isEmpty) {
        debugPrint('[IpoService] Cache boş geldi, server\'dan taze veri çekiliyor...');
        final freshSnapshot = await _db
            .collection('halka_arzlar')
            .get(const GetOptions(source: Source.serverAndCache));
        if (freshSnapshot.docs.isNotEmpty) {
          await box.put('last_firestore_fetch', DateTime.now().toIso8601String());
          final results = <IpoModel>[];
          for (var doc in freshSnapshot.docs) {
            final data = doc.data();
            data['sirket_kodu'] = doc.id;
            try { results.add(IpoModel.fromJson(data)); } catch (_) {}
          }
          return results;
        }
      }
      
      if (shouldFetchFromServer && snapshot.docs.isNotEmpty) {
         await box.put('last_firestore_fetch', DateTime.now().toIso8601String());
      }
      
      final List<IpoModel> results = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['sirket_kodu'] = doc.id;
        try {
          results.add(IpoModel.fromJson(data));
        } catch (e) {
          debugPrint('[IpoService] Model Parse Hatası (${doc.id}): $e');
        }
      }
      
      // TÜM verileri dön (taslak + arz + islem)
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
