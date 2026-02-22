import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

/// Firebase Realtime Database'den fiyatları TEK SEFERLİK çeker.
/// - `get()` kullanır, stream/onValue KULLANMAZ → bağlantı anında kapanır
/// - 15 dakika Hive cache → aynı seansda defalarca açma maliyeti sıfır
/// - 100 eş zamanlı bağlantı kotası: 1 kullanıcı sadece ~0.1 sn yer kaplar

class RealtimePriceService {
  static const String _boxName = 'rtdb_prices';
  static const Duration _cacheTtl = Duration(minutes: 15);

  static String? _rtdbUrl; // Sadece web için (mobilde otomatik)
  static DateTime? _lastFetch;
  static Map<String, double> _cache = {};

  static Future<void> init() async {
    await Hive.openBox(_boxName);
    _loadFromHive();
  }

  static void _loadFromHive() {
    final box = Hive.box(_boxName);
    final raw = box.get('prices') as Map?;
    if (raw != null) {
      _cache = raw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    }
    final lastFetchStr = box.get('last_fetch') as String?;
    if (lastFetchStr != null) {
      _lastFetch = DateTime.tryParse(lastFetchStr);
    }
  }

  static Future<void> _saveToHive(Map<String, double> prices) async {
    final box = Hive.box(_boxName);
    await box.put('prices', prices);
    await box.put('last_fetch', DateTime.now().toIso8601String());
  }

  /// Tüm fiyatları döner. Cache geçerliyse internete çıkmaz.
  static Future<Map<String, double>> fetchAll({
    bool forceRefresh = false,
  }) async {
    // Cache geçerliyse hemen dön
    if (!forceRefresh && _lastFetch != null) {
      final age = DateTime.now().difference(_lastFetch!);
      if (age < _cacheTtl && _cache.isNotEmpty) {
        debugPrint('[RTDB] Cache geçerli (${age.inMinutes} dk önce çekildi)');
        return Map.unmodifiable(_cache);
      }
    }

    return await _fetchFromRtdb();
  }

  static Future<Map<String, double>> _fetchFromRtdb() async {
    try {
      debugPrint('[RTDB] Tek seferlik get() çağrısı → /prices');
      final snapshot = await FirebaseDatabase.instance.ref('prices').get().timeout(const Duration(seconds: 8));
      
      if (!snapshot.exists) {
        debugPrint('[RTDB] /prices boş veya yok.');
        return Map.unmodifiable(_cache);
      }
      
      final raw = Map<String, dynamic>.from(snapshot.value as Map);
      final prices = raw.map((key, value) => MapEntry(key, (value as num).toDouble()));

      debugPrint('[RTDB ✓] ${prices.length} fiyat alındı.');
      _cache = prices;
      _lastFetch = DateTime.now();
      await _saveToHive(prices);
      return Map.unmodifiable(prices);
    } on TimeoutException {
      debugPrint('[RTDB] Timeout — cache kullanılıyor.');
      return Map.unmodifiable(_cache);
    } catch (e) {
      debugPrint('[RTDB] Hata: $e — cache kullanılıyor.');
      return Map.unmodifiable(_cache);
    }
  }

  /// Belirli bir hissenin fiyatı (cache'ten, yoksa null)
  static double? getPrice(String ticker) => _cache[ticker.toUpperCase()];

  /// Cache'teki tüm fiyatlar
  static Map<String, double> get cachedPrices => Map.unmodifiable(_cache);

  /// Sadece belirli tickerları çek (tüm listeyi indirmek yerine)
  static Future<double?> fetchSingle(String ticker) async {


    try {
      final ref = FirebaseDatabase.instance.ref('prices/$ticker');
      final snapshot = await ref.get().timeout(const Duration(seconds: 5));
      if (snapshot.exists && snapshot.value != null) {
        final price = (snapshot.value as num).toDouble();
        _cache[ticker] = price;
        return price;
      }
    } catch (e) {
      debugPrint('[RTDB] $ticker tek fiyat hatası: $e');
    }
    return _cache[ticker];
  }

  /// Cache'in ne zaman güncellendiği
  static DateTime? get lastFetch => _lastFetch;

  /// Cache geçerli mi?
  static bool get isCacheValid {
    if (_lastFetch == null || _cache.isEmpty) return false;
    return DateTime.now().difference(_lastFetch!) < _cacheTtl;
  }
}
