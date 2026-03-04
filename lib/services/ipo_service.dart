import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/ipo_model.dart';
import 'package:flutter/foundation.dart';

/// Firestore 'halka_arzlar' koleksiyonundan TÜM halka arzları çeker.
/// Bot her gün 08:00'de çalışır → uygulama 08:30'dan sonra 1 kez server'dan çeker,
/// sonraki 08:30'a kadar Firestore cihaz-içi cache kullanır.
class IpoService {
  static const String _boxName = 'ipo_cache_meta';
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Bot güncelleme saati + 30 dk buffer
  static const int _guncellemeYenileSaat = 8;
  static const int _guncellemeYenileDk = 30;

  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  /// Bugünkü güncelleme zamanı geçti mi? (08:30)
  static bool _guncellemeSaatiGectiMi() {
    final now = DateTime.now();
    final guncellemeSaati = DateTime(
      now.year, now.month, now.day,
      _guncellemeYenileSaat, _guncellemeYenileDk,
    );
    return now.isAfter(guncellemeSaati);
  }

  /// Server'dan çekmemiz gerekiyor mu?
  static bool _shouldFetchFromServer() {
    final box = Hive.box(_boxName);
    final lastFetchStr = box.get('last_firestore_fetch') as String?;

    // Hiç çekilmemişse → server'a git
    if (lastFetchStr == null) return true;

    final lastFetch = DateTime.tryParse(lastFetchStr);
    if (lastFetch == null) return true;

    final now = DateTime.now();

    // Bugünün güncelleme saati (08:30)
    final bugunGuncelleme = DateTime(
      now.year, now.month, now.day,
      _guncellemeYenileSaat, _guncellemeYenileDk,
    );

    // Son çekim bugünün 08:30'undan SONRA mı yapıldı?
    if (lastFetch.isAfter(bugunGuncelleme)) {
      // Evet, bugünkü güncel veriyi zaten aldık → cache kullan
      return false;
    }

    // Son çekim bugünün 08:30'undan ÖNCE yapıldı
    if (_guncellemeSaatiGectiMi()) {
      // 08:30 geçti ama henüz bugün güncel veri çekilmedi → server'a git
      return true;
    }

    // Henüz 08:30 olmadı → dünkü veri hala geçerli → cache kullan
    return false;
  }

  /// Firestore'dan verileri çeker.
  /// Günde 1x (08:30'da) server'dan çeker, geri kalanında cihaz cache kullanır.
  static Future<List<IpoModel>> getIpos() async {
    final box = Hive.box(_boxName);
    final fromServer = _shouldFetchFromServer();

    try {
      if (fromServer) {
        debugPrint('[IpoService] 🌐 Server\'dan taze veri çekiliyor...');
      } else {
        debugPrint('[IpoService] 💾 Cihaz cache kullanılıyor (08:30\'a kadar geçerli).');
      }

      final options = fromServer
          ? const GetOptions(source: Source.serverAndCache)
          : const GetOptions(source: Source.cache);

      var snapshot = await _db.collection('halka_arzlar').get(options);

      // Cache boş geldiyse → server'a git
      if (!fromServer && snapshot.docs.isEmpty) {
        debugPrint('[IpoService] Cache boş, server\'dan çekiliyor...');
        snapshot = await _db.collection('halka_arzlar')
            .get(const GetOptions(source: Source.serverAndCache));
      }

      if (snapshot.docs.isEmpty) {
        debugPrint('[IpoService] ❌ halka_arzlar koleksiyonu boş!');
        return [];
      }

      // Server'dan çektiyseK tarih güncelle
      if (fromServer || snapshot.metadata.isFromCache == false) {
        await box.put('last_firestore_fetch', DateTime.now().toIso8601String());
      }

      final List<IpoModel> results = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['sirket_kodu'] = doc.id;
        try {
          results.add(IpoModel.fromJson(data));
        } catch (e) {
          debugPrint('[IpoService] ❌ Parse hatası (${doc.id}): $e');
        }
      }

      debugPrint('[IpoService] ✅ ${results.length} IPO yüklendi (${fromServer ? "server" : "cache"})');
      return results;

    } catch (e) {
      debugPrint('[IpoService] ⚠️ Hata: $e — cache denenecek...');
      try {
        final fallback = await _db.collection('halka_arzlar')
            .get(const GetOptions(source: Source.cache));
        return fallback.docs.map((d) {
          final data = d.data();
          data['sirket_kodu'] = d.id;
          return IpoModel.fromJson(data);
        }).toList();
      } catch (e2) {
        debugPrint('[IpoService] ❌ Cache fallback da başarısız: $e2');
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
