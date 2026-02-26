import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/portfolio_item.dart';

/// Portföy CRUD işlemleri ve kar/zarar hesaplamaları
class PortfolioService {
  static const String _boxName = 'portfolio';
  static const String _totalEarningsKey = 'total_earnings';

  /// Hive kutusunu başlat
  static Future<void> init() async {
    await Hive.openBox(_boxName);
  }

  /// Portföye yeni öğe ekle
  static Future<void> addItem(PortfolioItem item) async {
    final box = Hive.box(_boxName);
    final items = _getItemsList(box);
    items.add(item);
    await _saveItemsList(box, items);
  }

  /// Portföy öğesini güncelle
  static Future<void> updateItem(PortfolioItem item) async {
    final box = Hive.box(_boxName);
    final items = _getItemsList(box);
    final index = items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      items[index] = item;
      await _saveItemsList(box, items);
    }
  }

  /// Portföy öğesini sil
  static Future<void> deleteItem(String id) async {
    final box = Hive.box(_boxName);
    final items = _getItemsList(box);
    items.removeWhere((i) => i.id == id);
    await _saveItemsList(box, items);
  }

  /// Tüm portföy öğelerini getir
  static List<PortfolioItem> getAllItems() {
    final box = Hive.box(_boxName);
    return _getItemsList(box);
  }

  /// Aktif pozisyonlar (satılmamış)
  static List<PortfolioItem> getActivePositions() {
    return getAllItems().where((i) => !i.satildiMi).toList();
  }

  /// Satılmış pozisyonlar
  static List<PortfolioItem> getSoldPositions() {
    return getAllItems().where((i) => i.satildiMi).toList();
  }

  /// Hisseyi sat
  static Future<double> sellItem(String id, double satisFiyati) async {
    final box = Hive.box(_boxName);
    final items = _getItemsList(box);
    final index = items.indexWhere((i) => i.id == id);
    if (index != -1) {
      items[index].satisFiyati = satisFiyati;
      items[index].satildiMi = true;
      items[index].satisTarihi = DateTime.now();

      final netKar = items[index].satisNetKar;

      // Toplam kazanca ekle
      await addToTotalEarnings(netKar);

      await _saveItemsList(box, items);
      return netKar;
    }
    return 0;
  }

  /// Tüm zamanların toplam kazancı
  static double getTotalEarnings() {
    double total = 0.0;
    for (var item in getSoldPositions()) {
      total += item.satisNetKar;
    }
    return total;
  }

  /// Toplam kazanca ekle (Dinamik hesaplandığı için kullanılmıyor)
  static Future<void> addToTotalEarnings(double amount) async {
    // Toplam kazanç artık anlık olarak getSoldPositions() üzerinden hesaplanıyor.
  }

  // === Private helpers ===

  static List<PortfolioItem> _getItemsList(Box box) {
    final data = box.get('portfolio_items');
    if (data == null) return [];
    try {
      final List<dynamic> jsonList = json.decode(data);
      return jsonList.map((j) => PortfolioItem.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveItemsList(Box box, List<PortfolioItem> items) async {
    final jsonStr = json.encode(items.map((i) => i.toJson()).toList());
    await box.put('portfolio_items', jsonStr);
  }
}
