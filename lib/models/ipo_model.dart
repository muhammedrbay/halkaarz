/// Halka Arz (IPO) veri modeli — Firestore `halka_arzlar` koleksiyonuyla eşleşir
class IpoModel {
  final String sirketKodu;
  final String sirketAdi;
  final double arzFiyati;
  final int toplamLot;
  final String dagitimSekli;
  final String konsorsiyumLideri;
  final bool katilimEndeksineUygun;
  final String kisiBashiLot;
  final String tarih;
  final String durum; // taslak | arz | islem
  final String pazar;
  final String bistIlkIslemTarihi;
  final String sirketAciklama;
  final int bireyselLot;
  final int bireyselYuzde;
  final String guncellemeZamani;
  // İşlem gören hisseler için:
  final dynamic sonFiyat; // double veya "Borsaya açılmadı henüz"
  final Map<String, dynamic> fiyatGecmisi;

  IpoModel({
    required this.sirketKodu,
    required this.sirketAdi,
    required this.arzFiyati,
    required this.toplamLot,
    required this.dagitimSekli,
    required this.konsorsiyumLideri,
    required this.katilimEndeksineUygun,
    required this.kisiBashiLot,
    required this.tarih,
    required this.durum,
    required this.pazar,
    required this.bistIlkIslemTarihi,
    required this.sirketAciklama,
    required this.bireyselLot,
    required this.bireyselYuzde,
    required this.guncellemeZamani,
    required this.sonFiyat,
    required this.fiyatGecmisi,
  });

  factory IpoModel.fromJson(Map<String, dynamic> json) {
    return IpoModel(
      sirketKodu: json['sirket_kodu'] ?? '',
      sirketAdi: json['sirket_adi'] ?? '',
      arzFiyati: (json['arz_fiyati'] ?? 0).toDouble(),
      toplamLot: json['toplam_lot'] ?? 0,
      dagitimSekli: json['dagitim_sekli'] ?? 'Eşit',
      konsorsiyumLideri: json['konsorsiyum_lideri'] ?? '',
      katilimEndeksineUygun: json['katilim_endeksine_uygun'] ?? false,
      kisiBashiLot: json['kisi_basi_lot']?.toString() ?? '',
      tarih: json['tarih'] ?? '',
      durum: json['durum'] ?? 'taslak',
      pazar: json['pazar'] ?? '',
      bistIlkIslemTarihi: json['bist_ilk_islem_tarihi'] ?? '',
      sirketAciklama: json['sirket_aciklama'] ?? '',
      bireyselLot: json['bireysel_lot'] ?? 0,
      bireyselYuzde: json['bireysel_yuzde'] ?? 0,
      guncellemeZamani: json['guncelleme_zamani'] ?? '',
      sonFiyat: json['son_fiyat'],
      fiyatGecmisi: Map<String, dynamic>.from(json['fiyat_gecmisi'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sirket_kodu': sirketKodu,
      'sirket_adi': sirketAdi,
      'arz_fiyati': arzFiyati,
      'toplam_lot': toplamLot,
      'dagitim_sekli': dagitimSekli,
      'konsorsiyum_lideri': konsorsiyumLideri,
      'katilim_endeksine_uygun': katilimEndeksineUygun,
      'kisi_basi_lot': kisiBashiLot,
      'tarih': tarih,
      'durum': durum,
      'pazar': pazar,
      'bist_ilk_islem_tarihi': bistIlkIslemTarihi,
      'sirket_aciklama': sirketAciklama,
      'bireysel_lot': bireyselLot,
      'bireysel_yuzde': bireyselYuzde,
      'guncelleme_zamani': guncellemeZamani,
      'son_fiyat': sonFiyat,
      'fiyat_gecmisi': fiyatGecmisi,
    };
  }

  /// Halka arz fiyatı formatlanmış
  String get arzFiyatiFormatli => '₺${arzFiyati.toStringAsFixed(2)}';

  /// Son fiyat formatlanmış
  String get sonFiyatFormatli {
    if (sonFiyat == null) return 'Veri yok';
    if (sonFiyat is String) return sonFiyat;
    return '₺${(sonFiyat as num).toDouble().toStringAsFixed(2)}';
  }

  /// Toplam yatırım tutarı (1 lot için)
  double get birLotTutar => arzFiyati * 100; // 1 lot = 100 hisse

  /// Tahmini lot hesapla
  double tahminiLot(int tahminiKatilimciSayisi) {
    if (tahminiKatilimciSayisi <= 0) return 0;
    return toplamLot / tahminiKatilimciSayisi;
  }
}
