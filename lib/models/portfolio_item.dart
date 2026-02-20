/// Portföy öğesi — Halka arz yatırım kaydı
class PortfolioItem {
  String id;
  String sirketKodu;
  String sirketAdi;
  double arzFiyati;
  int lotSayisi;
  int hesapSayisi; // Kaç farklı hesaptan katıldı?
  double? satisFiyati;
  bool satildiMi;
  DateTime eklenmeTarihi;
  DateTime? satisTarihi;

  PortfolioItem({
    required this.id,
    required this.sirketKodu,
    required this.sirketAdi,
    required this.arzFiyati,
    required this.lotSayisi,
    required this.hesapSayisi,
    this.satisFiyati,
    this.satildiMi = false,
    required this.eklenmeTarihi,
    this.satisTarihi,
  });

  /// Toplam lot (hesap sayısı × lot)
  int get toplamLot => lotSayisi * hesapSayisi;

  /// Toplam hisse adedi (1 lot = 100 hisse)
  int get toplamHisse => toplamLot * 100;

  /// Toplam maliyet (TL)
  double get toplamMaliyet => toplamHisse * arzFiyati;

  /// Net kar/zarar hesabı (anlık fiyat ile)
  double karZarar(double guncelFiyat) {
    final guncelDeger = toplamHisse * guncelFiyat;
    return guncelDeger - toplamMaliyet;
  }

  /// Yüzdelik kar/zarar
  double karZararYuzde(double guncelFiyat) {
    if (toplamMaliyet == 0) return 0;
    return ((karZarar(guncelFiyat)) / toplamMaliyet) * 100;
  }

  /// Satış net karı
  double get satisNetKar {
    if (!satildiMi || satisFiyati == null) return 0;
    final satisDeger = toplamHisse * satisFiyati!;
    return satisDeger - toplamMaliyet;
  }

  /// Satış net kar yüzdesi
  double get satisNetKarYuzde {
    if (toplamMaliyet == 0) return 0;
    return (satisNetKar / toplamMaliyet) * 100;
  }

  // JSON dönüşümleri
  factory PortfolioItem.fromJson(Map<String, dynamic> json) {
    return PortfolioItem(
      id: json['id'] ?? '',
      sirketKodu: json['sirket_kodu'] ?? '',
      sirketAdi: json['sirket_adi'] ?? '',
      arzFiyati: (json['arz_fiyati'] ?? 0).toDouble(),
      lotSayisi: json['lot_sayisi'] ?? 0,
      hesapSayisi: json['hesap_sayisi'] ?? 1,
      satisFiyati: json['satis_fiyati']?.toDouble(),
      satildiMi: json['satildi_mi'] ?? false,
      eklenmeTarihi: DateTime.parse(
        json['eklenme_tarihi'] ?? DateTime.now().toIso8601String(),
      ),
      satisTarihi: json['satis_tarihi'] != null
          ? DateTime.parse(json['satis_tarihi'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sirket_kodu': sirketKodu,
      'sirket_adi': sirketAdi,
      'arz_fiyati': arzFiyati,
      'lot_sayisi': lotSayisi,
      'hesap_sayisi': hesapSayisi,
      'satis_fiyati': satisFiyati,
      'satildi_mi': satildiMi,
      'eklenme_tarihi': eklenmeTarihi.toIso8601String(),
      'satis_tarihi': satisTarihi?.toIso8601String(),
    };
  }
}
