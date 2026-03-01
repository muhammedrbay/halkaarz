#!/usr/bin/env python3
"""
Halka Arz Bot — halkarz.com → Firebase Firestore
==================================================
NOT: KAP'ın API'si (memberDisclosureQuery) Cloudflare / WAF tarafında
     bot-seviyesinde engelleniyor; oturum cookie'siyle bile timeout alınıyor.
     Aynı verileri sunan halkarz.com çalışmaya devam ettiğinden veri
     kaynağı olarak burası kullanılmakta; çıktı ipos.json yerine doğrudan
     Firebase Firestore'a yazılmaktadır.

Durum Mantığı:
  • Talep toplama aralığı bugünü (hafta sonu dahil) kapsıyorsa → talep_topluyor
  • Başlangıç bugünden sonraysa                                → taslak
  • Bitiş tarihi geçmişte kaldıysa                           → (atlanır)

Firestore:
  Koleksiyon : ipos
  Belge ID   : BIST Kodu (tekrar eden kayıt sorununu önler)
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
BASE_URL = "https://halkarz.com"
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9",
    "Connection": "keep-alive",
}
AY_MAP = {
    "ocak": 1, "şubat": 2, "mart": 3, "nisan": 4,
    "mayıs": 5, "haziran": 6, "temmuz": 7, "ağustos": 8,
    "eylül": 9, "ekim": 10, "kasım": 11, "aralık": 12,
}


# ─────────────────────────────────────────────────────────────────
# 3) Yardımcı Fonksiyonlar
# ─────────────────────────────────────────────────────────────────
def safe_get(url: str, timeout: int = 15) -> Optional[requests.Response]:
    """Rate-limited HTTP GET."""
    time.sleep(random.uniform(1.0, 2.5))
    try:
        resp = requests.get(url, headers=HEADERS, timeout=timeout)
        resp.raise_for_status()
        return resp
    except requests.RequestException as e:
        print(f"  [HATA] {url}: {e}")
        return None


def parse_date_range(date_str: str):
    """
    'DD-DD Ay YYYY' veya 'DD Ay YYYY - DD Ay YYYY' formatlarını parse eder.
    Döndürür: (start_iso, end_iso, start_dt, end_dt) ya da (None,None,None,None)
    """
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
        start_day = int(days[0])
        end_day   = int(days[-1])
        start_month = AY_MAP[months[0]]
        end_month   = AY_MAP[months[-1]]
        start_dt = datetime(year, start_month, start_day)
        end_dt   = datetime(year, end_month,   end_day)
        return (
            start_dt.strftime("%Y-%m-%dT00:00:00"),
            end_dt.strftime("%Y-%m-%dT00:00:00"),
            start_dt,
            end_dt,
        )
    except ValueError:
        return None, None, None, None


def determine_durum(start_dt, end_dt) -> str:
    if start_dt is None:
        return "taslak"
    today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    if start_dt <= today <= end_dt:
        return "talep_topluyor"
    elif start_dt > today:
        return "taslak"
    return "gecmis"


def clean_money(text: str) -> float:
    text = text.replace("TL", "").replace("₺", "").strip().split("/")[0].strip()
    text = text.replace(".", "").replace(",", ".")
    try:
        return float(text)
    except Exception:
        return 0.0


def clean_lot(text: str) -> int:
    text = text.lower().replace("lot", "").replace(".", "").strip()
    try:
        return int(text)
    except Exception:
        return 0


# ─────────────────────────────────────────────────────────────────
# 4) Detay Sayfasından Ek Bilgi Çekme
# ─────────────────────────────────────────────────────────────────
def fetch_details(url: str) -> tuple[float, int, str, str, bool, str]:
    """
    halkarz.com detay sayfasından fiyat, lot, dağıtım, aracı kurum,
    katılım endeksi ve kişi başı lot bilgilerini çeker.
    """
    if not url:
        return 0.0, 0, "Eşit", "", False, ""

    resp = safe_get(url)
    if not resp:
        return 0.0, 0, "Eşit", "", False, ""

    soup = BeautifulSoup(resp.text, "html.parser")
    arz_fiyati     = 0.0
    toplam_lot     = 0
    dagitim_sekli  = "Eşit"
    aracı_kurum    = ""
    katilim_endeks = False
    kisi_basi_lot  = ""

    for tbl in soup.find_all("table"):
        for tr in tbl.find_all("tr"):
            text = tr.get_text(" ", strip=True)
            lt   = text.lower()
            val  = text.split(":")[-1].strip() if ":" in text else ""

            if "halka arz fiyatı" in lt and val:
                arz_fiyati = clean_money(val)
            elif ("toplam" in lt and "lot" in lt) and val:
                toplam_lot = clean_lot(val)
            elif "dağıtım" in lt and val:
                if "oransal" in val.lower():
                    dagitim_sekli = "Oransal"
            elif "aracı kurum" in lt and val:
                aracı_kurum = val
            elif "katılım endeksi" in lt:
                katilim_endeks = "uygun" in lt
            elif "kişi başı" in lt and val:
                kisi_basi_lot = val

    return arz_fiyati, toplam_lot, dagitim_sekli, aracı_kurum, katilim_endeks, kisi_basi_lot


# ─────────────────────────────────────────────────────────────────
# 5) Ana Kazıma: halkarz.com → İlk Halka Arzlar
# ─────────────────────────────────────────────────────────────────
def scrape() -> list[dict]:
    print(f"\n[1/2] halkarz.com ana sayfa çekiliyor...")
    resp = safe_get(BASE_URL)
    if not resp:
        print("[✗] halkarz.com'a ulaşılamadı.")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")
    arz_lists = soup.find_all("ul", class_="halka-arz-list")

    # "Taslak Arzlar" listesi ayrı class alır; ilk non-taslak listeyi bul
    ilk_list = None
    for ul in arz_lists:
        if "taslak" not in ul.get("class", []):
            ilk_list = ul
            break
    if not ilk_list and arz_lists:
        ilk_list = arz_lists[0]
    if not ilk_list:
        print("[✗] halka-arz-list bulunamadı.")
        return []

    results = []
    items = ilk_list.find_all("li", recursive=False)
    print(f"    Listede {len(items)} öğe mevcut. Kronolojik tarama başlıyor...\n")

    for li in items:
        article = li.find("article", class_="index-list")
        if not article:
            continue

        h3 = article.find("h3", class_="il-halka-arz-sirket")
        if not h3:
            continue
        a_tag     = h3.find("a")
        sirket_adi = a_tag.get_text(strip=True) if a_tag else h3.get_text(strip=True)

        bist_span = article.find("span", class_="il-bist-kod")
        bist_kod  = bist_span.get_text(strip=True).upper() if bist_span else ""

        tarih_span = article.find("span", class_="il-halka-arz-tarihi")
        date_str   = ""
        if tarih_span:
            time_tag = tarih_span.find("time")
            date_str = (
                time_tag.get("datetime", time_tag.get_text(strip=True))
                if time_tag else tarih_span.get_text(strip=True)
            )

        start_iso, end_iso, start_dt, end_dt = parse_date_range(date_str)
        durum = determine_durum(start_dt, end_dt)

        # Liste kronolojik → geçmiş arz bulunca altındakiler de geçmiş → break
        if durum == "gecmis":
            print(f"  [SON] {sirket_adi} geçmişte kaldı → tarama durduruluyor.")
            break

        detail_url = ""
        if a_tag and a_tag.get("href"):
            href = a_tag["href"]
            detail_url = href if href.startswith("http") else BASE_URL + href

        print(f"  ↳ {sirket_adi} ({bist_kod}) | {durum} | {date_str}")
        arz_fiyati, toplam_lot, dagitim_sekli, aracı_kurum, katilim_endeks, kisi_basi_lot = fetch_details(detail_url)

        results.append({
            "sirket_kodu":              bist_kod,
            "sirket_adi":               sirket_adi,
            "durum":                    durum,
            "tarih_raw":                date_str,
            "talep_baslangic":          start_iso or "",
            "talep_bitis":              end_iso   or "",
            "detay_url":                detail_url,
            "arz_fiyati":               arz_fiyati,
            "toplam_lot":               toplam_lot,
            "dagitim_sekli":            dagitim_sekli,
            "konsorsiyum_lideri":       aracı_kurum,
            "katilim_endeksine_uygun":  katilim_endeks,
            "kisi_basi_lot":            kisi_basi_lot,
            "guncelleme_zamani":        datetime.now().isoformat(),
        })

    print(f"\n[✓] {len(results)} aktif halka arz bulundu.")
    return results


# ─────────────────────────────────────────────────────────────────
# 6) Firestore'a Yazma
# ─────────────────────────────────────────────────────────────────
def upsert_to_firestore(ipos: list[dict]):
    if not ipos:
        print("[!] Yazılacak kayıt yok.")
        return

    saved = 0
    for ipo in ipos:
        bist = ipo.get("sirket_kodu", "").strip()
        if not bist:
            print(f"  [ATLANDI] Borsa kodu boş: {ipo.get('sirket_adi')}")
            continue

        if db:
            db.collection("ipos").document(bist).set(ipo, merge=True)
            print(f"  [YAZILDI ✓] {bist} → durum={ipo['durum']}")
        else:
            print(f"  [DRY-RUN] {bist} → {ipo['durum']}")
            print(f"    {json.dumps(ipo, ensure_ascii=False, indent=6)}")
        saved += 1

    print(f"\n── Sonuç: {saved}/{len(ipos)} kayıt Firestore'a yazıldı. ──")


# ─────────────────────────────────────────────────────────────────
# 7) Giriş Noktası
# ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("=" * 55)
    print(f"  Halka Arz Bot  —  {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 55)

    ipos = scrape()
    upsert_to_firestore(ipos)
