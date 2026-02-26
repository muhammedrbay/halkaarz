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


def parse_turkish_date_range(date_str: str) -> tuple[Optional[str], Optional[str], Optional[datetime], Optional[datetime]]:
    """
    Türkçe tarih stringini parse edip (baslangic_iso, bitis_iso, baslangic_dt, bitis_dt) döner.
    Örnekler:
      "19-20 Şubat 2026" → "2026-02-19", "2026-02-20", start_dt, end_dt
    """
    if not date_str or "hazırlanıyor" in date_str.lower():
        return None, None, None, None

    clean = re.sub(r"\(.*?\)", "", date_str).strip()
    
    match_year = re.search(r'(\d{4})$', clean)
    year = int(match_year.group(1)) if match_year else datetime.now().year
    
    days = re.findall(r'\b(\d{1,2})\b', clean)
    months = re.findall(r'([a-zA-ZğüşıöçĞÜŞİÖÇ]+)', clean.lower())
    months = [m for m in months if m in AY_MAP]
    
    if not days or not months:
        return None, None, None, None
        
    start_day = int(days[0])
    end_day = int(days[-1])
    
    end_month = AY_MAP[months[-1]]
    start_month = AY_MAP[months[0]] if len(months) > 1 else end_month
    
    try:
        start_dt = datetime(year, start_month, start_day)
        end_dt = datetime(year, end_month, end_day)
        start_date = start_dt.strftime('%Y-%m-%dT00:00:00')
        end_date = end_dt.strftime('%Y-%m-%dT00:00:00')
        return start_date, end_date, start_dt, end_dt
    except ValueError:
        return None, None, None, None


def determine_durum(start_dt: Optional[datetime], end_dt: Optional[datetime]) -> str:
    """
    Halka arzın durumunu salt tarihe göre belirler:
      - Tarih belirsiz/yok → taslak (Hazırlanıyor)
      - Bugün tarih aralığının içindeyse → talep_topluyor
      - Başlangıç tarihi bugünden sonraysa → taslak
      - Bitiş tarihi bugünden önceyse → gecmis (kaydedilmeyecek)
    """
    if start_dt is None or end_dt is None:
        return "taslak"

    today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)

    if start_dt <= today <= end_dt:
        return "talep_topluyor"
    elif start_dt > today:
        return "taslak"
    else:
        return "gecmis"


# ─── Kazıma ──────────────────────────────────────────────────────

def clean_money(text: str) -> float:
    text = text.replace('TL', '').replace('₺', '').strip()
    text = text.split('/')[0].strip()
    text = text.replace('.', '').replace(',', '.')
    try:
        return float(text)
    except Exception:
        return 0.0

def clean_lot(text: str) -> int:
    text = text.lower().replace('lot', '').replace('.', '').strip()
    try:
        return int(text)
    except Exception:
        return 0

def fetch_details(url: str) -> tuple[float, int, str]:
    if not url: return 0.0, 0, "Eşit"
    resp = safe_get(url)
    if not resp: return 0.0, 0, "Eşit"

    soup = BeautifulSoup(resp.text, 'html.parser')
    arz_fiyati = 0.0
    toplam_lot = 0
    dagitim_sekli = "Eşit"
    
    tables = soup.find_all('table')
    for tbl in tables:
        for tr in tbl.find_all('tr'):
            text = tr.text.strip().replace('\n', ' ')
            if 'Halka Arz Fiyatı' in text:
                val = text.split(':')[-1].strip()
                arz_fiyati = clean_money(val)
            elif 'Dağıtım Yöntemi' in text:
                val = text.split(':')[-1].strip()
                if 'Oransal' in val: dagitim_sekli = "Oransal"
            elif 'Pay' in text and 'Lot' in text:
                val = text.split(':')[-1].strip()
                toplam_lot = clean_lot(val)

    return arz_fiyati, toplam_lot, dagitim_sekli


def scrape_ilk_halka_arzlar() -> list[dict]:
    """
    halkarz.com 'İlk Halka Arzlar' (taslak/talep) kazıması
    """
    print("[1/3] halkarz.com ana sayfası çekiliyor (İlk Halka Arzlar)...")
    resp = safe_get(BASE_URL)
    if not resp: return []

    soup = BeautifulSoup(resp.text, "html.parser")
    arz_lists = soup.find_all("ul", class_="halka-arz-list")
    if not arz_lists: return []

    ilk_halka_arz_list = None
    for ul in arz_lists:
        if "taslak" not in ul.get("class", []):
            ilk_halka_arz_list = ul
            break
    if not ilk_halka_arz_list:
        ilk_halka_arz_list = arz_lists[0]

    results = []
    items = ilk_halka_arz_list.find_all("li", recursive=False)

    for li in items:
        article = li.find("article", class_="index-list")
        if not article: continue

        h3 = article.find("h3", class_="il-halka-arz-sirket")
        if not h3: continue
        a_tag = h3.find("a")
        sirket_adi = a_tag.get_text(strip=True) if a_tag else h3.get_text(strip=True)

        bist_kod_span = article.find("span", class_="il-bist-kod")
        bist_kod = bist_kod_span.get_text(strip=True) if bist_kod_span else ""

        tarih_span = article.find("span", class_="il-halka-arz-tarihi")
        date_str = ""
        if tarih_span:
            time_tag = tarih_span.find("time")
            date_str = time_tag.get("datetime", time_tag.get_text(strip=True)) if time_tag else tarih_span.get_text(strip=True)

        badge_div = article.find("div", class_="il-badge")

        start_date, end_date, start_dt, end_dt = parse_turkish_date_range(date_str)
        durum = determine_durum(start_dt, end_dt)

        if durum == "gecmis":
            continue

        detail_url = ""
        if a_tag and a_tag.get("href"):
            href = a_tag["href"]
            detail_url = href if href.startswith("http") else BASE_URL + href

        arz_fiyati, toplam_lot, dagitim_sekli = fetch_details(detail_url)

        entry = {
            "sirket_kodu": bist_kod.upper(),
            "sirket_adi": sirket_adi,
            "durum": durum,
            "tarih_raw": date_str,
            "talep_baslangic": start_date or "",
            "talep_bitis": end_date or "",
            "detay_url": detail_url,
            "arz_fiyati": arz_fiyati,
            "toplam_lot": toplam_lot,
            "dagitim_sekli": dagitim_sekli,
        }
        results.append(entry)
        print(f"  {sirket_adi[:40]:40s} | Kod: {bist_kod:8s} | {durum:16s} | {date_str} (Lot: {toplam_lot})")

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
            # Mevcut kayıt — durumu ve tarihleri güncelle
            old_durum = existing_dict[code].get("durum", "")
            new_durum = item["durum"]
            
            updated = False
            if old_durum != new_durum:
                existing_dict[code]["durum"] = new_durum
                updated = True
                print(f"  [GÜNCELLE] {code}: {old_durum} → {new_durum}")
            
            # Tarihleri de tazele (eskiden boş kalmış olabilir)
            for field in ["talep_baslangic", "talep_bitis", "tarih_raw"]:
                if item.get(field) and not existing_dict[code].get(field):
                    existing_dict[code][field] = item[field]
                    updated = True

            # Performans ve detay bilgileri tazele
            for field in ["arz_fiyati", "toplam_lot"]:
                if item.get(field) and (existing_dict[code].get(field, 0) == 0):
                    existing_dict[code][field] = item[field]
                    updated = True
            
            if item.get("dagitim_sekli") and existing_dict[code].get("dagitim_sekli") != item["dagitim_sekli"]:
                existing_dict[code]["dagitim_sekli"] = item["dagitim_sekli"]
                updated = True

            if updated:
                existing_dict[code]["guncelleme_zamani"] = datetime.now().isoformat()
                updated_count += 1
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
