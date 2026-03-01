import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/ipo_model.dart';
import 'package:flutter/foundation.dart';

/// Firestore üzerinden KAP'tan gelen Taslak ve Talep listelerini alır.
/// Günlük 1 defa server maliyeti yapmak için (100K+ DAU için) agresif cache uygulanır.
class IpoService {
  static const String _boxName = 'ipo_cache_meta';
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  /// Firestore'dan verileri çeker. Maliyetleri düşürmek için gün içinde
  /// yapılan tüm takipler/açılışlar yerel (cache) üzerinden servis edilir.
  static Future<List<IpoModel>> getIpos() async {
    final box = Hive.box(_boxName);
    final lastFetchStr = box.get('last_firestore_fetch') as String?;
    
    bool shouldFetchFromServer = true;

    if (lastFetchStr != null) {
      final lastDate = DateTime.tryParse(lastFetchStr);
      if (lastDate != null) {
        final now = DateTime.now();
        // Eğer aynı takvim günü içindeysek server'dan GİTME, Firebase Cache'ten al.
        if (lastDate.year == now.year &&
            lastDate.month == now.month &&
            lastDate.day == now.day) {
          shouldFetchFromServer = false;
        }
      }
    }

    try {
      // Firebase'in yerleşik maliyet ve performans dostu GetOptions özelliği
      final options = shouldFetchFromServer
          ? const GetOptions(source: Source.serverAndCache) // Yeni günde 1 kez Server'a git
          : const GetOptions(source: Source.cache);       // Gün içindeki tüm diğer açılışlarda Cache kullan
          
      if (shouldFetchFromServer) {
        debugPrint('[IpoService] Sunucudan taze Firestore verisi çekiliyor (Günde 1 kez)...');
      } else {
        debugPrint('[IpoService] Bugün zaten çekilmiş, Firebase cihaz-içi Cache kullanılıyor (Bedava Okuma).');
      }

      final snapshot = await _db.collection('ipos').get(options);
      
      // Eğer sunucudan taze çekim başarılıysa o anki zamanı meta verisi olarak kaydet
      if (shouldFetchFromServer && snapshot.docs.isNotEmpty) {
         await box.put('last_firestore_fetch', DateTime.now().toIso8601String());
      }
      
      final List<IpoModel> results = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        // KAP'tan gelen python datasındaki eksik stringleri eşitleme koruması
        data['sirket_kodu'] = doc.id;
        try {
          results.add(IpoModel.fromJson(data));
        } catch (e) {
          debugPrint('[IpoService] Model Parse Hatası (${doc.id}): $e');
        }
      }
      
      // Sadece Taslak ve Talep Toplayanları gönderir (Geçmişler Performans sekmesi için ayrıldı)
      return results.where((ipo) => ipo.durum == 'taslak' || ipo.durum == 'talep_topluyor').toList();
      
    } catch (e) {
      debugPrint('[IpoService] Firestore bağlantı hatası: $e');
      
      // Çevrimdışı (Offline) kalındığında Cache'ten zorla yükleme Fallback'i
      try {
        final fallbackSnapshot = await _db.collection('ipos').get(const GetOptions(source: Source.cache));
        return fallbackSnapshot.docs
            .map((d) {
               final data = d.data();
               data['sirket_kodu'] = d.id;
               return IpoModel.fromJson(data);
            })
            .where((ipo) => ipo.durum == 'taslak' || ipo.durum == 'talep_topluyor')
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
