#!/usr/bin/env python3
"""
Halka Arz Bot — halkarz.com → Firebase Firestore
==================================================
Hem "İlk Halka Arzlar" hem de "Halka Arz Performansı" sayfasını kazır.

Firestore Koleksiyonu: ipos
  durum='taslak'          → Taslak sekmesi
  durum='talep_topluyor'  → Talep sekmesi
  durum='islem_goruyor'   → İşlem / Performans sekmesi
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

# ─────────────────────────────────────────────────────────────────
# 1) Firebase Firestore Başlatma
# ─────────────────────────────────────────────────────────────────
try:
    import firebase_admin
    from firebase_admin import credentials, firestore as fs

    cred_json = os.environ.get("FIREBASE_CREDENTIALS")
    db = None

    if cred_json:
        cred_dict = json.loads(cred_json)
        cred = credentials.Certificate(cred_dict)
        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)
        db = fs.client()
        print("[✓] Firebase Firestore bağlantısı tamam.")
    else:
        print("[!] FIREBASE_CREDENTIALS bulunamadı → DRY-RUN modunda çalışılacak.")
except Exception as e:
    print(f"[!] Firebase başlatma hatası: {e}")
    db = None


# ─────────────────────────────────────────────────────────────────
# 2) Sabitler
# ─────────────────────────────────────────────────────────────────
BASE_URL     = "https://halkarz.com"
PERF_PAGE    = "https://halkarz.com/page/{}/"   # Sayfalı geçmiş liste
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9",
}
AY_MAP = {
    "ocak": 1, "şubat": 2, "mart": 3, "nisan": 4,
    "mayıs": 5, "haziran": 6, "temmuz": 7, "ağustos": 8,
    "eylül": 9, "ekim": 10, "kasım": 11, "aralık": 12,
}


# ─────────────────────────────────────────────────────────────────
# 3) Ortak Yardımcılar
# ─────────────────────────────────────────────────────────────────
def safe_get(url: str, timeout: int = 15) -> Optional[requests.Response]:
    time.sleep(random.uniform(0.8, 2.0))
    try:
        resp = requests.get(url, headers=HEADERS, timeout=timeout)
        resp.raise_for_status()
        return resp
    except requests.RequestException as e:
        print(f"  [HATA] {url}: {e}")
        return None


def parse_date_range(date_str: str):
    """'DD-DD Ay YYYY' veya 'DD Ay YYYY - DD Ay YYYY' → (start_iso, end_iso, start_dt, end_dt)"""
    if not date_str or "hazırlanıyor" in date_str.lower():
        return None, None, None, None
    clean = re.sub(r"\(.*?\)", "", date_str).strip()
    year_m = re.search(r"(\d{4})", clean)
    year = int(year_m.group(1)) if year_m else datetime.now().year
    days = re.findall(r"\b(\d{1,2})\b", clean)
    months = [m for m in re.findall(r"([a-zA-ZğüşıöçĞÜŞİÖÇ]+)", clean.lower()) if m in AY_MAP]
    if not days or not months:
        return None, None, None, None
    try:
        start_dt = datetime(year, AY_MAP[months[0]],  int(days[0]))
        end_dt   = datetime(year, AY_MAP[months[-1]], int(days[-1]))
        return (
            start_dt.strftime("%Y-%m-%dT00:00:00"),
            end_dt.strftime("%Y-%m-%dT00:00:00"),
            start_dt,
            end_dt,
        )
    except ValueError:
        return None, None, None, None


def determine_durum(start_dt, end_dt) -> str:
    if not start_dt:
        return "taslak"
    today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    if start_dt <= today <= end_dt:
        return "talep_topluyor"
    return "taslak" if start_dt > today else "gecmis"


def clean_money(text: str) -> float:
    text = text.replace("TL", "").replace("₺", "").strip().split("/")[0].strip()
    text = text.replace(".", "").replace(",", ".")
    try:
        return float(text)
    except Exception:
        return 0.0


def clean_lot(text: str) -> int:
    text = text.lower().replace("lot", "").replace(".", "").replace(",", "").strip()
    try:
        return int(text)
    except Exception:
        return 0


# ─────────────────────────────────────────────────────────────────
# 4) İlk Halka Arzlar — Detay Sayfası
# ─────────────────────────────────────────────────────────────────
def fetch_detail(url: str) -> dict:
    """halkarz.com detay sayfasından Arz Fiyatı, Lot, Dağıtım vd. çeker."""
    defaults = {
        "arz_fiyati": 0.0, "toplam_lot": 0,
        "dagitim_sekli": "Eşit", "konsorsiyum_lideri": "",
        "katilim_endeksine_uygun": False, "kisi_basi_lot": "",
    }
    if not url:
        return defaults
    resp = safe_get(url)
    if not resp:
        return defaults

    soup = BeautifulSoup(resp.text, "html.parser")
    d = dict(defaults)

    for tbl in soup.find_all("table"):
        for tr in tbl.find_all("tr"):
            txt = tr.get_text(" ", strip=True)
            lt  = txt.lower()
            val = txt.split(":")[-1].strip() if ":" in txt else ""
            if "halka arz fiyatı" in lt and val:
                d["arz_fiyati"] = clean_money(val)
            elif "toplam" in lt and "lot" in lt and val:
                d["toplam_lot"] = clean_lot(val)
            elif "dağıtım" in lt and val:
                if "oransal" in val.lower():
                    d["dagitim_sekli"] = "Oransal"
            elif "aracı kurum" in lt and val:
                d["konsorsiyum_lideri"] = val
            elif "katılım endeksi" in lt:
                d["katilim_endeksine_uygun"] = "uygun" in lt
            elif "kişi başı" in lt and val:
                d["kisi_basi_lot"] = val
    return d


# ─────────────────────────────────────────────────────────────────
# 5) İlk Halka Arzlar Bölümü (Taslak + Talep)
# ─────────────────────────────────────────────────────────────────
def scrape_ilk_halka_arzlar() -> list[dict]:
    print("\n[■] İlk Halka Arzlar kazınıyor...")
    resp = safe_get(BASE_URL)
    if not resp:
        print("  halkarz.com'a ulaşılamadı.")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")
    arz_lists = soup.find_all("ul", class_="halka-arz-list")
    ilk_list = None
    for ul in arz_lists:
        if "taslak" not in ul.get("class", []):
            ilk_list = ul
            break
    if not ilk_list and arz_lists:
        ilk_list = arz_lists[0]
    if not ilk_list:
        return []

    results = []
    for li in ilk_list.find_all("li", recursive=False):
        article = li.find("article", class_="index-list")
        if not article:
            continue

        h3 = article.find("h3", class_="il-halka-arz-sirket")
        if not h3:
            continue
        a_tag = h3.find("a")
        sirket_adi = a_tag.get_text(strip=True) if a_tag else h3.get_text(strip=True)

        bist_span = article.find("span", class_="il-bist-kod")
        bist_kod  = bist_span.get_text(strip=True).upper() if bist_span else ""

        tarih_span = article.find("span", class_="il-halka-arz-tarihi")
        date_str = ""
        if tarih_span:
            time_tag = tarih_span.find("time")
            date_str = (
                time_tag.get("datetime", time_tag.get_text(strip=True))
                if time_tag else tarih_span.get_text(strip=True)
            )

        start_iso, end_iso, start_dt, end_dt = parse_date_range(date_str)
        durum = determine_durum(start_dt, end_dt)

        if durum == "gecmis":
            print(f"  [SON] {sirket_adi} geçmişte → tarama durduruluyor.")
            break

        detail_url = ""
        if a_tag and a_tag.get("href"):
            href = a_tag["href"]
            detail_url = href if href.startswith("http") else BASE_URL + href

        print(f"  ↳ {sirket_adi} ({bist_kod}) | {durum}")
        det = fetch_detail(detail_url)

        results.append({
            "sirket_kodu":              bist_kod,
            "sirket_adi":               sirket_adi,
            "durum":                    durum,
            "tarih_raw":                date_str,
            "talep_baslangic":          start_iso or "",
            "talep_bitis":              end_iso   or "",
            "borsada_islem_tarihi":     "",
            "detay_url":                detail_url,
            "arz_fiyati":               det["arz_fiyati"],
            "toplam_lot":               det["toplam_lot"],
            "kisi_basi_lot":            det["kisi_basi_lot"],
            "dagitim_sekli":            det["dagitim_sekli"],
            "konsorsiyum_lideri":       det["konsorsiyum_lideri"],
            "katilim_endeksine_uygun":  det["katilim_endeksine_uygun"],
            "iskonto_orani":            0.0,
            "guncelleme_zamani":        datetime.now().isoformat(),
        })

    print(f"  → {len(results)} Taslak/Talep halka arz bulundu.")
    return results


# ─────────────────────────────────────────────────────────────────
# 6) Halka Arz Performansı Bölümü (İşlem Görüyor)
# ─────────────────────────────────────────────────────────────────
def scrape_performans(max_pages: int = 5) -> list[dict]:
    """
    halkarz.com sayfalı listesi üzerinden geçmiş tarihli halka arzları çeker.
    Bu IPO'lar bitiş tarihi geçmiş olduğu için 'islem_goruyor' olarak işaretlenir.
    max_pages: Kaç sayfa taranacak (her sayfa ~10 kayıt içerir)
    """
    print("\n[■] Halka Arz Performansı (geçmiş arzlar) kazınıyor...")
    results = []
    seen_codes = set()  # Sayfa tekrarı tespit için
    today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)

    for page_num in range(2, max_pages + 2):  # page 2'den başla (page 1 = aktif)
        url = PERF_PAGE.format(page_num)
        resp = safe_get(url)
        if not resp:
            print(f"  [Sayfa {page_num}] Erişilemedi, durduruluyor.")
            break

        soup = BeautifulSoup(resp.text, "html.parser")
        arz_lists = soup.find_all("ul", class_="halka-arz-list")
        items = []
        for ul in arz_lists:
            if "taslak" not in ul.get("class", []):
                items.extend(ul.find_all("li", recursive=False))

        if not items:
            print(f"  [Sayfa {page_num}] Liste bulunamadı, durduruluyor.")
            break

        print(f"  [Sayfa {page_num}] {len(items)} öğe bulundu.")
        geçmiş_count = 0
        new_this_page = 0  # Bu sayfada kaç yeni BIST kodu eklendi

        for li in items:
            article = li.find("article", class_="index-list")
            if not article:
                continue

            h3 = article.find("h3", class_="il-halka-arz-sirket")
            if not h3:
                continue
            a_tag = h3.find("a")
            sirket_adi = a_tag.get_text(strip=True) if a_tag else h3.get_text(strip=True)

            bist_span = article.find("span", class_="il-bist-kod")
            bist_kod  = bist_span.get_text(strip=True).upper() if bist_span else ""

            tarih_span = article.find("span", class_="il-halka-arz-tarihi")
            date_str = ""
            if tarih_span:
                time_tag = tarih_span.find("time")
                date_str = (
                    time_tag.get("datetime", time_tag.get_text(strip=True))
                    if time_tag else tarih_span.get_text(strip=True)
                )

            start_iso, end_iso, start_dt, end_dt = parse_date_range(date_str)
            if not end_dt:
                continue  # Tarihi olmayan → atla

            # Bitiş tarihi geçmişse → islem_goruyor
            if end_dt >= today:
                continue  # Hâlâ aktif → İlk Halka Arzlar bölümü zaten yazdı

            # Daha önce işlendiyse atla (sayfa tekrarı tespiti)
            if bist_kod and bist_kod in seen_codes:
                continue
            if bist_kod:
                seen_codes.add(bist_kod)

            geçmiş_count += 1
            new_this_page += 1
            detail_url = ""
            if a_tag and a_tag.get("href"):
                href = a_tag["href"]
                detail_url = href if href.startswith("http") else BASE_URL + href

            print(f"    ↳ {sirket_adi[:40]:40s} ({bist_kod})")
            det = fetch_detail(detail_url) if detail_url else {}

            results.append({
                "sirket_kodu":              bist_kod,
                "sirket_adi":               sirket_adi,
                "durum":                    "islem_goruyor",
                "tarih_raw":                date_str,
                "talep_baslangic":          start_iso or "",
                "talep_bitis":              end_iso   or "",
                "borsada_islem_tarihi":     (end_dt + __import__('datetime').timedelta(days=1)).strftime("%Y-%m-%dT00:00:00"),
                "detay_url":                detail_url,
                "arz_fiyati":               det.get("arz_fiyati", 0.0),
                "toplam_lot":               det.get("toplam_lot", 0),
                "kisi_basi_lot":            det.get("kisi_basi_lot", ""),
                "dagitim_sekli":            det.get("dagitim_sekli", "Eşit"),
                "konsorsiyum_lideri":       det.get("konsorsiyum_lideri", ""),
                "katilim_endeksine_uygun":  det.get("katilim_endeksine_uygun", False),
                "iskonto_orani":            0.0,
                "son_katilimci_sayilari":   [],
                "guncelleme_zamani":        datetime.now().isoformat(),
            })

        if new_this_page == 0:
            print(f"  [Sayfa {page_num}] Tüm öğeler daha önce işlendi (tekrar sayfa). Durduruluyor.")
            break

        if geçmiş_count == 0:
            print(f"  [Sayfa {page_num}] Bu sayfada geçmiş arz yok, durduruluyor.")
            break

    print(f"  → {len(results)} İşlem Gören halka arz bulundu.")
    return results



# ─────────────────────────────────────────────────────────────────
# 7) Firestore'a Yaz (BIST Kodu = Belge ID → tekrar yok)
# ─────────────────────────────────────────────────────────────────
def upsert_to_firestore(ipos: list[dict]):
    if not ipos:
        print("[!] Yazılacak kayıt yok.")
        return

    saved = 0
    for ipo in ipos:
        bist = ipo.get("sirket_kodu", "").strip()

        # BIST kodu boşsa şirket adından kısa bir anahtar üret
        if not bist:
            raw = ipo.get("sirket_adi", "NONAME")
            bist = re.sub(r"[^A-Z0-9]", "", raw.upper())[:10] or "NOCODE"
            ipo["sirket_kodu"] = bist

        if db:
            db.collection("ipos").document(bist).set(ipo, merge=True)
            print(f"  [✓] {bist:<8} {ipo['sirket_adi'][:40]:40s} → {ipo['durum']}")
        else:
            print(f"  [DRY] {bist:<8} → {ipo['durum']}")
        saved += 1

    print(f"\n── {saved} kayıt Firestore'a yazıldı. ──")


# ─────────────────────────────────────────────────────────────────
# 8) Giriş Noktası
# ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("=" * 58)
    print(f"  Halka Arz Bot  —  {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 58)

    taslak_talep = scrape_ilk_halka_arzlar()
    performans   = scrape_performans()

    all_ipos = taslak_talep + performans
    upsert_to_firestore(all_ipos)

    t = sum(1 for i in all_ipos if i["durum"] == "taslak")
    ta = sum(1 for i in all_ipos if i["durum"] == "talep_topluyor")
    is_ = sum(1 for i in all_ipos if i["durum"] == "islem_goruyor")
    print(f"\n[İSTATİSTİK] Taslak:{t} | Talep:{ta} | İşlem:{is_}")
