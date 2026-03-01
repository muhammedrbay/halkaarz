/// Halka Arz (IPO) veri modeli
class IpoModel {
  final String sirketKodu;
  final String sirketAdi;
  final double arzFiyati;
  final int toplamLot;
  final String dagitimSekli;
  final String konsorsiyumLideri;
  final double iskontoOrani;
  final Map<String, dynamic> fonKullanimYeri;
  final bool katilimEndeksineUygun;
  final String talepBaslangic;
  final String talepBitis;
  final String borsadaIslemTarihi;
  final String durum; // taslak | talep_topluyor | islem_goruyor
  final List<int> sonKatilimciSayilari;
  final String guncellemeZamani;
  // Yeni detay alanları
  final String halkaArzSekli;
  final String fonunKullanimYeriMetin;
  final String satisYontemi;
  final String tahsisatGruplari;
  final int bireyselLot;
  final int bireyselYuzde;
  final String sirketAciklama;

  IpoModel({
    required this.sirketKodu,
    required this.sirketAdi,
    required this.arzFiyati,
    required this.toplamLot,
    required this.dagitimSekli,
    required this.konsorsiyumLideri,
    required this.iskontoOrani,
    required this.fonKullanimYeri,
    required this.katilimEndeksineUygun,
    required this.talepBaslangic,
    required this.talepBitis,
    required this.borsadaIslemTarihi,
    required this.durum,
    required this.sonKatilimciSayilari,
    required this.guncellemeZamani,
    this.halkaArzSekli = '',
    this.fonunKullanimYeriMetin = '',
    this.satisYontemi = '',
    this.tahsisatGruplari = '',
    this.bireyselLot = 0,
    this.bireyselYuzde = 0,
    this.sirketAciklama = '',
  });

  factory IpoModel.fromJson(Map<String, dynamic> json) {
    return IpoModel(
      sirketKodu: json['sirket_kodu'] ?? '',
      sirketAdi: json['sirket_adi'] ?? '',
      arzFiyati: (json['arz_fiyati'] ?? 0).toDouble(),
      toplamLot: json['toplam_lot'] ?? 0,
      dagitimSekli: json['dagitim_sekli'] ?? 'Eşit',
      konsorsiyumLideri: json['konsorsiyum_lideri'] ?? '',
      iskontoOrani: (json['iskonto_orani'] ?? 0).toDouble(),
      fonKullanimYeri: Map<String, dynamic>.from(
        json['fon_kullanim_yeri'] ?? {},
      ),
      katilimEndeksineUygun: json['katilim_endeksine_uygun'] ?? false,
      talepBaslangic: json['talep_baslangic'] ?? '',
      talepBitis: json['talep_bitis'] ?? '',
      borsadaIslemTarihi: json['borsada_islem_tarihi'] ?? '',
      durum: json['durum'] ?? 'taslak',
      sonKatilimciSayilari: List<int>.from(
        json['son_katilimci_sayilari'] ?? [],
      ),
      guncellemeZamani: json['guncelleme_zamani'] ?? '',
      halkaArzSekli: json['halka_arz_sekli'] ?? '',
      fonunKullanimYeriMetin: json['fonun_kullanim_yeri'] ?? '',
      satisYontemi: json['satis_yontemi'] ?? '',
      tahsisatGruplari: json['tahsisat_gruplari'] ?? '',
      bireyselLot: json['bireysel_lot'] ?? 0,
      bireyselYuzde: json['bireysel_yuzde'] ?? 0,
      sirketAciklama: json['sirket_aciklama'] ?? '',
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
      'iskonto_orani': iskontoOrani,
      'fon_kullanim_yeri': fonKullanimYeri,
      'katilim_endeksine_uygun': katilimEndeksineUygun,
      'talep_baslangic': talepBaslangic,
      'talep_bitis': talepBitis,
      'borsada_islem_tarihi': borsadaIslemTarihi,
      'durum': durum,
      'son_katilimci_sayilari': sonKatilimciSayilari,
      'guncelleme_zamani': guncellemeZamani,
      'halka_arz_sekli': halkaArzSekli,
      'fonun_kullanim_yeri': fonunKullanimYeriMetin,
      'satis_yontemi': satisYontemi,
      'tahsisat_gruplari': tahsisatGruplari,
      'bireysel_lot': bireyselLot,
      'bireysel_yuzde': bireyselYuzde,
      'sirket_aciklama': sirketAciklama,
    };
  }

  /// Talep toplama tarih aralığı formatlı metin
  String get talepTarihAraligi {
    if (talepBaslangic.isEmpty || talepBitis.isEmpty) return 'Belirtilmedi';
    try {
      final bas = DateTime.parse(talepBaslangic);
      final bit = DateTime.parse(talepBitis);
      return '${bas.day}.${bas.month.toString().padLeft(2, '0')}.${bas.year} - '
          '${bit.day}.${bit.month.toString().padLeft(2, '0')}.${bit.year}';
    } catch (_) {
      return 'Belirtilmedi';
    }
  }

  /// Toplam yatırım tutarı (1 lot için)
  double get birLotTutar => arzFiyati * 100; // 1 lot = 100 hisse

  /// Tahmini lot hesapla
  double tahminiLot(int tahminiKatilimciSayisi) {
    if (tahminiKatilimciSayisi <= 0) return 0;
    if (dagitimSekli == 'Eşit') {
      return toplamLot / tahminiKatilimciSayisi;
    }
    // Oransal dağıtım — basit eşit varsayım
    return toplamLot / tahminiKatilimciSayisi;
  }
}
