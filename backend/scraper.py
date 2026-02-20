#!/usr/bin/env python3
"""
Halka Arz Veri Çekme Motoru
KAP duyurularından ve resmi kaynaklardan halka arz verisi çeker.
Günde sadece 2-3 kez çalışacak şekilde planlanmıştır.
"""

import json
import os
import time
import re
from datetime import datetime, timedelta
from typing import Optional

import requests
from bs4 import BeautifulSoup

# --- Yapılandırma ---
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
OUTPUT_FILE = os.path.join(DATA_DIR, "ipos.json")
MANUAL_FILE = os.path.join(DATA_DIR, "manual_ipos.json")
REQUEST_DELAY = 3  # İstekler arası bekleme (saniye)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (compatible; HalkaArzTakip/1.0; +https://github.com/halka-arz-takip)",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
}

# Katılım endeksine uygun bilinen şirketler (manuel güncellenir)
KATILIM_ENDEKSI_SIRKETLERI = set()


def safe_request(url: str, timeout: int = 15) -> Optional[requests.Response]:
    """Hata yönetimli HTTP GET isteği."""
    try:
        time.sleep(REQUEST_DELAY)
        response = requests.get(url, headers=HEADERS, timeout=timeout)
        response.raise_for_status()
        return response
    except requests.RequestException as e:
        print(f"[HATA] İstek başarısız: {url} -> {e}")
        return None


def parse_kap_halka_arz_page() -> list[dict]:
    """
    KAP Halka Arz Duyurularını parse eder.
    KAP'ın halka arz sayfasından güncel verileri çeker.
    """
    results = []

    # KAP halka arz bildirim sayfası
    url = "https://www.kap.org.tr/tr/bist-sirketler"
    response = safe_request(url)
    if not response:
        print("[UYARI] KAP sayfasına erişilemedi, manuel veriler kullanılacak.")
        return results

    try:
        soup = BeautifulSoup(response.text, "html.parser")
        # KAP'ın yapısı değişebilir, temel parse mantığı
        # Bu bölüm KAP'ın güncel HTML yapısına göre güncellenmeli
        print("[BİLGİ] KAP sayfası başarıyla çekildi.")
    except Exception as e:
        print(f"[HATA] KAP parse hatası: {e}")

    return results


def fetch_spk_bulteni() -> list[dict]:
    """
    SPK haftalık bülteninden halka arz onaylarını kontrol eder.
    """
    results = []
    url = "https://www.spk.gov.tr/Bulten/Goster"
    response = safe_request(url)
    if not response:
        print("[UYARI] SPK bültenine erişilemedi.")
        return results

    try:
        soup = BeautifulSoup(response.text, "html.parser")
        print("[BİLGİ] SPK bülteni başarıyla çekildi.")
    except Exception as e:
        print(f"[HATA] SPK parse hatası: {e}")

    return results


def create_ipo_entry(
    sirket_kodu: str,
    sirket_adi: str,
    arz_fiyati: float,
    toplam_lot: int,
    dagitim_sekli: str = "Eşit",
    konsorsiyum_lideri: str = "",
    iskonto_orani: float = 0.0,
    fon_kullanim_yeri: Optional[dict] = None,
    katilim_endeksine_uygun: bool = False,
    talep_baslangic: str = "",
    talep_bitis: str = "",
    borsada_islem_tarihi: str = "",
    durum: str = "taslak",
    son_katilimci_sayilari: Optional[list] = None,
) -> dict:
    """Standart IPO veri girişi oluşturur."""
    return {
        "sirket_kodu": sirket_kodu.upper(),
        "sirket_adi": sirket_adi,
        "arz_fiyati": arz_fiyati,
        "toplam_lot": toplam_lot,
        "dagitim_sekli": dagitim_sekli,
        "konsorsiyum_lideri": konsorsiyum_lideri,
        "iskonto_orani": iskonto_orani,
        "fon_kullanim_yeri": fon_kullanim_yeri or {
            "yatirim": 0,
            "borc_odeme": 0,
            "isletme_sermayesi": 0,
        },
        "katilim_endeksine_uygun": katilim_endeksine_uygun,
        "talep_baslangic": talep_baslangic,
        "talep_bitis": talep_bitis,
        "borsada_islem_tarihi": borsada_islem_tarihi,
        "durum": durum,  # taslak | talep_topluyor | islem_goruyor
        "son_katilimci_sayilari": son_katilimci_sayilari or [],
        "guncelleme_zamani": datetime.now().isoformat(),
    }


def load_manual_data() -> list[dict]:
    """Manuel olarak girilen IPO verilerini yükler."""
    if not os.path.exists(MANUAL_FILE):
        return []
    try:
        with open(MANUAL_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[HATA] Manuel veri okunamadı: {e}")
        return []


def load_existing_data() -> list[dict]:
    """Mevcut IPO verilerini yükler."""
    if not os.path.exists(OUTPUT_FILE):
        return []
    try:
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[HATA] Mevcut veri okunamadı: {e}")
        return []


def merge_ipo_data(existing: list[dict], new_data: list[dict]) -> list[dict]:
    """
    Mevcut ve yeni IPO verilerini birleştirir.
    Aynı şirket kodu varsa günceller, yoksa ekler.
    """
    merged = {item["sirket_kodu"]: item for item in existing}
    for item in new_data:
        code = item["sirket_kodu"]
        if code in merged:
            # Mevcut veriyi güncelle, ama kullanıcı girişlerini koru
            existing_item = merged[code]
            item["guncelleme_zamani"] = datetime.now().isoformat()
            merged[code] = {**existing_item, **item}
        else:
            merged[code] = item
    return list(merged.values())


def update_ipo_statuses(ipos: list[dict]) -> list[dict]:
    """IPO durumlarını tarihlere göre günceller."""
    now = datetime.now()
    for ipo in ipos:
        try:
            talep_bas = ipo.get("talep_baslangic", "")
            talep_bit = ipo.get("talep_bitis", "")
            islem_tar = ipo.get("borsada_islem_tarihi", "")

            if islem_tar:
                islem_date = datetime.fromisoformat(islem_tar.replace("Z", ""))
                if now >= islem_date:
                    ipo["durum"] = "islem_goruyor"
                    continue

            if talep_bas and talep_bit:
                bas_date = datetime.fromisoformat(talep_bas.replace("Z", ""))
                bit_date = datetime.fromisoformat(talep_bit.replace("Z", ""))
                if bas_date <= now <= bit_date:
                    ipo["durum"] = "talep_topluyor"
                elif now > bit_date:
                    ipo["durum"] = "talep_topluyor"  # Talep bitti ama henüz işlem görmüyor
                else:
                    ipo["durum"] = "taslak"
        except (ValueError, TypeError):
            pass

    return ipos


def save_data(ipos: list[dict]):
    """IPO verilerini JSON dosyasına kaydeder."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(ipos, f, ensure_ascii=False, indent=2)
    print(f"[BİLGİ] {len(ipos)} adet IPO verisi kaydedildi: {OUTPUT_FILE}")


def main():
    """Ana çalıştırma fonksiyonu."""
    print("=" * 60)
    print(f"Halka Arz Veri Çekme Motoru - {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    # 1. Mevcut verileri yükle
    existing_data = load_existing_data()
    print(f"[BİLGİ] Mevcut veri sayısı: {len(existing_data)}")

    # 2. KAP'tan veri çek
    kap_data = parse_kap_halka_arz_page()
    print(f"[BİLGİ] KAP'tan çekilen veri sayısı: {len(kap_data)}")

    # 3. SPK bülteninden veri çek
    spk_data = fetch_spk_bulteni()
    print(f"[BİLGİ] SPK'dan çekilen veri sayısı: {len(spk_data)}")

    # 4. Manuel verileri yükle
    manual_data = load_manual_data()
    print(f"[BİLGİ] Manuel veri sayısı: {len(manual_data)}")

    # 5. Tüm verileri birleştir
    all_new = kap_data + spk_data + manual_data
    merged = merge_ipo_data(existing_data, all_new)

    # 6. Durumları güncelle
    updated = update_ipo_statuses(merged)

    # 7. Kaydet
    save_data(updated)

    print("=" * 60)
    print("[BİLGİ] İşlem tamamlandı.")


if __name__ == "__main__":
    main()
