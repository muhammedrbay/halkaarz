#!/usr/bin/env python3
"""
halkarz.com İlk Halka Arzlar Kazıma & Kategorilendirme
========================================================
halkarz.com ana sayfasından "İlk Halka Arzlar" sekmesindeki halka arzları çeker,
tarih ve badge durumuna göre taslak / talep_topluyor / islem_goruyor olarak sınıflandırır
ve ipos.json'a merge eder.

GitHub Actions: Günde 1 kez (TR 10:00) çalışır.
"""

import json
import os
import re
import random
import time
from datetime import datetime
from typing import Optional

import requests
from bs4 import BeautifulSoup

# --- Yapılandırma ---
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
IPOS_FILE = os.path.join(DATA_DIR, "ipos.json")

BASE_URL = "https://halkarz.com"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
    "Connection": "keep-alive",
}

# Türkçe ay isimleri → ay numarası
AY_MAP = {
    "ocak": 1, "şubat": 2, "mart": 3, "nisan": 4,
    "mayıs": 5, "haziran": 6, "temmuz": 7, "ağustos": 8,
    "eylül": 9, "ekim": 10, "kasım": 11, "aralık": 12,
}


# ─── Yardımcılar ──────────────────────────────────────────────────

def safe_get(url: str, timeout: int = 15) -> Optional[requests.Response]:
    """Rate-limited HTTP GET."""
    delay = random.uniform(1.0, 2.5)
    time.sleep(delay)
    try:
        resp = requests.get(url, headers=HEADERS, timeout=timeout)
        resp.raise_for_status()
        return resp
    except requests.RequestException as e:
        print(f"  [HATA] {url} → {e}")
        return None


def parse_turkish_date(date_str: str) -> Optional[datetime]:
    """
    Türkçe tarih stringini parse eder.
    Örnekler:
      "19-20 Şubat 2026" → son gün: 20 Şubat 2026
      "2-3-4 Mart 2026" → son gün: 4 Mart 2026
      "26-27 Şubat, 2 Mart 2026" → son gün: 2 Mart 2026
      "5-6-7 Ocak 2026" → son gün: 7 Ocak 2026
      "16 Eylül 2025 (Kısmi Bölünme)" → 16 Eylül 2025
    """
    if not date_str or "hazırlanıyor" in date_str.lower():
        return None

    # Parantez içini temizle
    clean = re.sub(r"\(.*?\)", "", date_str).strip()

    # Virgül varsa, en son parçayı al (örn: "26-27 Şubat, 2 Mart 2026")
    if "," in clean:
        parts = clean.split(",")
        clean = parts[-1].strip()

    # Tire varsa son günü al (örn: "2-3-4 Mart 2026" → "4 Mart 2026")
    # Pattern: rakam-rakam-... ay yıl
    match = re.match(r"([\d\-]+)\s+(\S+)\s+(\d{4})", clean)
    if match:
        days_part = match.group(1)
        month_str = match.group(2).lower()
        year = int(match.group(3))

        # Son günü al
        days = days_part.split("-")
        last_day = int(days[-1])

        month = AY_MAP.get(month_str)
        if month:
            try:
                return datetime(year, month, last_day)
            except (ValueError, OverflowError):
                pass

    return None


def determine_durum(date_str: str, has_talep_badge: bool, has_gong_badge: bool) -> str:
    """
    Halka arzın durumunu belirler:
      - "Hazırlanıyor..." → taslak
      - Badge: "Talep toplanıyor" → talep_topluyor
      - Badge: "Gong!" → islem_goruyor
      - Tarih gelecekte → talep_topluyor
      - Tarih geçmişte → islem_goruyor
    """
    # Badge'ler en yüksek önceliğe sahip
    if has_gong_badge:
        return "islem_goruyor"
    if has_talep_badge:
        return "talep_topluyor"

    # Tarih kontrolü
    if not date_str or "hazırlanıyor" in date_str.lower():
        return "taslak"

    parsed_date = parse_turkish_date(date_str)
    if parsed_date is None:
        return "taslak"

    today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)

    if parsed_date >= today:
        return "talep_topluyor"
    else:
        return "islem_goruyor"


# ─── Kazıma ──────────────────────────────────────────────────────

def scrape_ilk_halka_arzlar() -> list[dict]:
    """
    halkarz.com ana sayfasından İlk Halka Arzlar sekmesindeki tüm verileri çeker.
    """
    print("[1/3] halkarz.com ana sayfası çekiliyor...")
    resp = safe_get(BASE_URL)
    if not resp:
        print("  [HATA] Ana sayfa yüklenemedi!")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")

    # İlk tab: ul.halka-arz-list (taslak olmayan)
    arz_lists = soup.find_all("ul", class_="halka-arz-list")
    if not arz_lists:
        print("  [HATA] Halka arz listesi bulunamadı!")
        return []

    # İlk ul (taslak sınıfı olmayan) = İlk Halka Arzlar
    ilk_halka_arz_list = None
    for ul in arz_lists:
        classes = ul.get("class", [])
        if "taslak" not in classes:
            ilk_halka_arz_list = ul
            break

    if not ilk_halka_arz_list:
        ilk_halka_arz_list = arz_lists[0]

    results = []
    items = ilk_halka_arz_list.find_all("li", recursive=False)

    for li in items:
        article = li.find("article", class_="index-list")
        if not article:
            continue

        # Şirket adı
        h3 = article.find("h3", class_="il-halka-arz-sirket")
        if not h3:
            continue
        a_tag = h3.find("a")
        sirket_adi = a_tag.get_text(strip=True) if a_tag else h3.get_text(strip=True)

        # BIST kodu
        bist_kod_span = article.find("span", class_="il-bist-kod")
        bist_kod = bist_kod_span.get_text(strip=True) if bist_kod_span else ""

        # Tarih
        tarih_span = article.find("span", class_="il-halka-arz-tarihi")
        date_str = ""
        if tarih_span:
            time_tag = tarih_span.find("time")
            if time_tag:
                date_str = time_tag.get("datetime", time_tag.get_text(strip=True))
            else:
                date_str = tarih_span.get_text(strip=True)

        # Badge'ler
        badge_div = article.find("div", class_="il-badge")
        has_talep = False
        has_gong = False
        if badge_div:
            has_talep = badge_div.find("div", class_="il-tt") is not None
            has_gong = badge_div.find("div", class_="il-gonk") is not None

        # Durum belirle
        durum = determine_durum(date_str, has_talep, has_gong)

        # Detay URL
        detail_url = ""
        if a_tag and a_tag.get("href"):
            href = a_tag["href"]
            detail_url = href if href.startswith("http") else BASE_URL + href

        entry = {
            "sirket_kodu": bist_kod.upper(),
            "sirket_adi": sirket_adi,
            "durum": durum,
            "tarih_raw": date_str,
            "detay_url": detail_url,
        }

        results.append(entry)
        print(f"  {sirket_adi[:40]:40s} | Kod: {bist_kod:8s} | {durum:16s} | {date_str}")

    print(f"\n[✓] {len(results)} halka arz bulundu.")
    return results


# ─── Merge ──────────────────────────────────────────────────────

def load_ipos() -> list[dict]:
    """Mevcut ipos.json dosyasını yükler."""
    if not os.path.exists(IPOS_FILE):
        return []
    try:
        with open(IPOS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[HATA] ipos.json okuma: {e}")
        return []


def save_ipos(ipos: list[dict]):
    """ipos.json dosyasına yazar."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(IPOS_FILE, "w", encoding="utf-8") as f:
        json.dump(ipos, f, ensure_ascii=False, indent=2)
    print(f"[✓] {len(ipos)} kayıt → ipos.json")


def create_new_ipo_entry(scraped: dict) -> dict:
    """Yeni bir IPO kaydı oluşturur (ipos.json formatında)."""
    return {
        "sirket_kodu": scraped["sirket_kodu"],
        "sirket_adi": scraped["sirket_adi"],
        "arz_fiyati": 0,
        "toplam_lot": 0,
        "kisi_basi_lot": 1,
        "dagitim_sekli": "Eşit",
        "konsorsiyum_lideri": "",
        "iskonto_orani": 0.0,
        "fon_kullanim_yeri": {
            "yatirim": 0,
            "borc_odeme": 0,
            "isletme_sermayesi": 0
        },
        "katilim_endeksine_uygun": False,
        "talep_baslangic": "",
        "talep_bitis": "",
        "borsada_islem_tarihi": "",
        "durum": scraped["durum"],
        "son_katilimci_sayilari": [],
        "guncelleme_zamani": datetime.now().isoformat(),
    }


def merge_scraped_data(existing: list[dict], scraped: list[dict]) -> list[dict]:
    """
    Kazınan verileri mevcut ipos.json ile birleştirir.
    - Mevcut şirketlerin durum bilgisini günceller
    - Yeni şirketleri ekler
    - Mevcut sparkline/fiyat verilerini korur
    """
    # Mevcut verileri dict'e çevir (kod -> kayıt)
    existing_dict = {}
    for ipo in existing:
        code = ipo.get("sirket_kodu", "").upper()
        if code:
            existing_dict[code] = ipo

    new_count = 0
    updated_count = 0

    for item in scraped:
        code = item["sirket_kodu"].upper()

        # BIST kodu boşsa şirket adından tanımlama yapılamaz, atla
        if not code:
            # Kodusuz kayıtları şirket adıyla eşleştirmeye çalış
            found = False
            for ex_code, ex_ipo in existing_dict.items():
                if ex_ipo.get("sirket_adi", "").lower() == item["sirket_adi"].lower():
                    code = ex_code
                    found = True
                    break
            if not found:
                # Yeni ve kodsuz → yine de ekle (şirket adı bazlı)
                new_entry = create_new_ipo_entry(item)
                existing_dict[f"_nocode_{item['sirket_adi'][:20]}"] = new_entry
                new_count += 1
                print(f"  [YENİ] {item['sirket_adi']} (kod yok) → {item['durum']}")
                continue

        if code in existing_dict:
            # Mevcut kayıt — sadece durumu güncelle
            old_durum = existing_dict[code].get("durum", "")
            new_durum = item["durum"]

            if old_durum != new_durum:
                existing_dict[code]["durum"] = new_durum
                existing_dict[code]["guncelleme_zamani"] = datetime.now().isoformat()
                updated_count += 1
                print(f"  [GÜNCELLE] {code}: {old_durum} → {new_durum}")
        else:
            # Yeni kayıt
            new_entry = create_new_ipo_entry(item)
            existing_dict[code] = new_entry
            new_count += 1
            print(f"  [YENİ] {code} ({item['sirket_adi']}) → {item['durum']}")

    print(f"\n[Merge ✓] {new_count} yeni, {updated_count} güncellenen kayıt.")

    # Dict'ten listeye çevir
    return list(existing_dict.values())


# ─── Ana Fonksiyon ──────────────────────────────────────────────

def main():
    print("=" * 60)
    print(f"halkarz.com İlk Halka Arzlar Kazıma — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    # 1. halkarz.com'dan İlk Halka Arzlar verisini çek
    scraped = scrape_ilk_halka_arzlar()
    if not scraped:
        print("[UYARI] Kazıma sonucu boş, işlem durduruluyor.")
        return

    # 2. Mevcut ipos.json yükle
    existing = load_ipos()
    print(f"\n[2/3] Mevcut ipos.json: {len(existing)} kayıt")

    # 3. Merge
    print(f"\n[3/3] Merge işlemi başlıyor...")
    merged = merge_scraped_data(existing, scraped)

    # 4. Kaydet
    save_ipos(merged)

    # İstatistikler
    taslak = sum(1 for i in merged if i.get("durum") == "taslak")
    talep = sum(1 for i in merged if i.get("durum") == "talep_topluyor")
    islem = sum(1 for i in merged if i.get("durum") == "islem_goruyor")
    print(f"\n[İSTATİSTİK] Taslak: {taslak} | Talep: {talep} | İşlem: {islem}")
    print("=" * 60)


if __name__ == "__main__":
    main()
