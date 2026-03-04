#!/usr/bin/env python3
"""
Halka Arz Bot — halkarz.com → Firebase Firestore
==================================================
Sadece taslak ve talep_topluyor arzları çeker. Geçmiş arzlar çekilmez.
Her IPO'nun detay sayfasından TÜM bilgiler alınır.

Firestore Koleksiyonu: ipos
  durum='taslak'          → Taslak sekmesi
  durum='talep_topluyor'  → Talep sekmesi
"""

import json
import os
import re
import random
import time
from datetime import datetime, timedelta
from typing import Optional

import requests
from bs4 import BeautifulSoup

# ─────────────────────────────────────────────────────────────────
# 1) Firebase Firestore
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
}
AY_MAP = {
    "ocak": 1, "şubat": 2, "mart": 3, "nisan": 4,
    "mayıs": 5, "haziran": 6, "temmuz": 7, "ağustos": 8,
    "eylül": 9, "ekim": 10, "kasım": 11, "aralık": 12,
}


# ─────────────────────────────────────────────────────────────────
# 3) Yardımcılar
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
        start_dt = datetime(year, AY_MAP[months[0]], int(days[0]))
        end_dt = datetime(year, AY_MAP[months[-1]], int(days[-1]))
        return (
            start_dt.strftime("%Y-%m-%dT00:00:00"),
            end_dt.strftime("%Y-%m-%dT00:00:00"),
            start_dt, end_dt,
        )
    except ValueError:
        return None, None, None, None


def determine_durum(start_dt, end_dt) -> str:
    if not start_dt:
        return "taslak"
    today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    # Hafta sonu toleransı: Cuma→Pazartesi arası aktif kabul et
    end_plus = end_dt + timedelta(days=2) if end_dt.weekday() == 4 else end_dt
    if start_dt <= today <= end_plus:
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
# 4) Detay Sayfası — TÜM bilgileri çeker
# ─────────────────────────────────────────────────────────────────
def _extract_section(full_text: str, header: str, next_headers: list[str]) -> str:
    """Sayfa body text'i içinde header ile başlayan bölümü ayıklar."""
    lt = full_text.lower()
    start = lt.find(header.lower())
    if start < 0:
        return ""
    start += len(header)
    end = len(full_text)
    for nh in next_headers:
        pos = lt.find(nh.lower(), start)
        if 0 < pos < end:
            end = pos
    return full_text[start:end].strip()


def fetch_all_details(url: str) -> dict:
    """halkarz.com detay sayfasından TÜM halka arz bilgilerini çeker."""
    defaults = {
        "arz_fiyati": 0.0,
        "toplam_lot": 0,
        "dagitim_sekli": "Eşit",
        "konsorsiyum_lideri": "",
        "katilim_endeksine_uygun": False,
        "kisi_basi_lot": "",
        "halka_arz_sekli": "",
        "fonun_kullanim_yeri": "",
        "satis_yontemi": "",
        "tahsisat_gruplari": "",
        "bireysel_lot": 0,
        "bireysel_yuzde": 0,
        "sirket_aciklama": "",
        "finansal_tablolar": {},
    }
    if not url:
        return defaults

    resp = safe_get(url)
    if not resp:
        return defaults

    soup = BeautifulSoup(resp.text, "html.parser")
    d = dict(defaults)

    # ── 1) Ana tablo: Fiyat, Pay, Dağıtım, Aracı Kurum ──
    for tbl in soup.find_all("table"):
        for tr in tbl.find_all("tr"):
            txt = tr.get_text(" ", strip=True)
            lt = txt.lower()
            val = txt.split(":")[-1].strip() if ":" in txt else ""

            if "halka arz fiyatı" in lt and val:
                # "80,00 TL" ya da "75,00 - 80,00 TL"
                d["arz_fiyati"] = clean_money(val)
            elif ("pay" in lt and "lot" in lt) and val:
                d["toplam_lot"] = clean_lot(val)
            elif "dağıtım" in lt and val:
                d["dagitim_sekli"] = "Oransal" if "oransal" in val.lower() else "Eşit"
            elif "aracı kurum" in lt and val:
                d["konsorsiyum_lideri"] = val
            elif "kişi başı" in lt and val:
                d["kisi_basi_lot"] = val
        break  # Sadece ilk tabloyu al (ana bilgiler tablosu)

    # ── 2) Body text'ten bölüm bazlı bilgiler ──
    body = soup.find("body")
    if not body:
        return d
    full_text = body.get_text("\n", strip=True)

    section_headers = [
        "Halka Arz Şekli", "Fonun Kullanım Yeri",
        "Halka Arz Satış Yöntemi", "Tahsisat Grupları",
        "Dağıtılacak Pay Miktarı", "Katılım Endeksi",
        "Özet Bilgiler", "Forum", "Başvuru Yerleri",
        "Halka Arz Bilgileri", "Grafiği",
    ]

    # Halka Arz Şekli
    sec = _extract_section(full_text, "Halka Arz Şekli", section_headers)
    if sec:
        d["halka_arz_sekli"] = sec

    # Fonun Kullanım Yeri
    sec = _extract_section(full_text, "Fonun Kullanım Yeri", section_headers)
    if sec:
        d["fonun_kullanim_yeri"] = sec

    # Satış Yöntemi
    sec = _extract_section(full_text, "Halka Arz Satış Yöntemi", section_headers)
    if sec:
        d["satis_yontemi"] = sec

    # Tahsisat Grupları
    sec = _extract_section(full_text, "Tahsisat Grupları", section_headers)
    if sec:
        d["tahsisat_gruplari"] = sec
        # Bireysel yatırımcı lot ve yüzdesini ayıkla
        bireysel = re.search(r"([\d.]+)\s*Lot\s*\(%?(\d+)\)\s*.*?Bireysel", sec)
        if bireysel:
            d["bireysel_lot"] = clean_lot(bireysel.group(1))
            try:
                d["bireysel_yuzde"] = int(bireysel.group(2))
            except ValueError:
                pass

    # Katılım Endeksi
    katilim_text = full_text.lower()
    if "katılım endeksi" in katilim_text:
        if "uygun" in katilim_text[katilim_text.find("katılım endeksi"):katilim_text.find("katılım endeksi")+100]:
            d["katilim_endeksine_uygun"] = True

    # Şirket Açıklaması (kısa)
    sirket_h2 = None
    for h2 in soup.find_all("h2"):
        if h2.get_text(strip=True).startswith("(") or "A.Ş." in h2.get_text(strip=True):
            sirket_h2 = h2
            break
    if sirket_h2:
        sib = sirket_h2.find_next_sibling("p")
        if sib:
            d["sirket_aciklama"] = sib.get_text(strip=True)[:500]

    # Finansal Tablolar (tablo 2)
    tables = soup.find_all("table")
    if len(tables) > 1:
        fin_tbl = tables[1]
        headers = [th.get_text(strip=True) for th in fin_tbl.find_all("th")]
        if not headers:
            first_row = fin_tbl.find("tr")
            if first_row:
                headers = [td.get_text(strip=True) for td in first_row.find_all("td")]
        rows = fin_tbl.find_all("tr")[1:]  # başlık hariç
        fin_data = {}
        for tr in rows[:6]:
            cells = [td.get_text(strip=True) for td in tr.find_all("td")]
            if len(cells) >= 2:
                fin_data[cells[0]] = cells[1:]
        if fin_data:
            d["finansal_tablolar"] = fin_data

    return d


# ─────────────────────────────────────────────────────────────────
# 5) Ana Kazıma — Sadece Taslak & Talep
# ─────────────────────────────────────────────────────────────────
def scrape() -> list[dict]:
    print(f"\n[■] halkarz.com ana sayfa çekiliyor...")
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
        print("  halka-arz-list bulunamadı.")
        return []

    results = []
    items = ilk_list.find_all("li", recursive=False)
    print(f"  {len(items)} öğe bulundu. Kronolojik tarama başlıyor...\n")

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
        bist_kod = bist_span.get_text(strip=True).upper() if bist_span else ""

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

        # ── GEÇMİŞ ARZLARI ATLA ──
        if durum == "gecmis":
            print(f"  [SON] {sirket_adi} geçmişte → tarama durduruluyor.")
            break

        detail_url = ""
        if a_tag and a_tag.get("href"):
            href = a_tag["href"]
            detail_url = href if href.startswith("http") else BASE_URL + href

        print(f"  ↳ {sirket_adi} ({bist_kod}) | {durum}")
        print(f"    Detay sayfası çekiliyor: {detail_url}")

        det = fetch_all_details(detail_url)

        entry = {
            "sirket_kodu":              bist_kod,
            "sirket_adi":               sirket_adi,
            "durum":                    durum,
            "tarih_raw":                date_str,
            "talep_baslangic":          start_iso or "",
            "talep_bitis":              end_iso or "",
            "borsada_islem_tarihi":     "",
            "detay_url":                detail_url,
            # Temel bilgiler
            "arz_fiyati":               det["arz_fiyati"],
            "toplam_lot":               det["toplam_lot"],
            "kisi_basi_lot":            det["kisi_basi_lot"],
            "dagitim_sekli":            det["dagitim_sekli"],
            "konsorsiyum_lideri":       det["konsorsiyum_lideri"],
            "katilim_endeksine_uygun":  det["katilim_endeksine_uygun"],
            "iskonto_orani":            0.0,
            # Detaylı bilgiler
            "halka_arz_sekli":          det["halka_arz_sekli"],
            "fonun_kullanim_yeri":      det["fonun_kullanim_yeri"],
            "satis_yontemi":            det["satis_yontemi"],
            "tahsisat_gruplari":        det["tahsisat_gruplari"],
            "bireysel_lot":             det["bireysel_lot"],
            "bireysel_yuzde":           det["bireysel_yuzde"],
            "sirket_aciklama":          det["sirket_aciklama"],
            "finansal_tablolar":        det["finansal_tablolar"],
            # Meta
            "guncelleme_zamani":        datetime.now().isoformat(),
        }
        results.append(entry)

    print(f"\n[✓] {len(results)} aktif halka arz bulundu (sadece taslak + talep).")
    return results


# ─────────────────────────────────────────────────────────────────
# 6) Firestore'a Yaz
# ─────────────────────────────────────────────────────────────────
def upsert_to_firestore(ipos: list[dict]):
    if not ipos:
        print("[!] Yazılacak kayıt yok.")
        return

    saved = 0
    for ipo in ipos:
        bist = ipo.get("sirket_kodu", "").strip()
        if not bist:
            raw = ipo.get("sirket_adi", "NONAME")
            bist = re.sub(r"[^A-Z0-9]", "", raw.upper())[:10] or "NOCODE"
            ipo["sirket_kodu"] = bist

        if db:
            db.collection("ipos").document(bist).set(ipo, merge=True)
            print(f"  [✓] {bist:<8} {ipo['sirket_adi'][:40]:40s} → {ipo['durum']}")
        else:
            print(f"  [DRY] {bist:<8} → {ipo['durum']}")
            print(f"    Fiyat: {ipo['arz_fiyati']} | Lot: {ipo['toplam_lot']} | Dağıtım: {ipo['dagitim_sekli']}")
            print(f"    Aracı: {ipo['konsorsiyum_lideri']}")
            print(f"    Katılım: {ipo['katilim_endeksine_uygun']}")
            if ipo["halka_arz_sekli"]:
                print(f"    Arz Şekli: {ipo['halka_arz_sekli'][:100]}")
            if ipo["fonun_kullanim_yeri"]:
                print(f"    Fon Kullanım: {ipo['fonun_kullanim_yeri'][:100]}")
            if ipo["tahsisat_gruplari"]:
                print(f"    Tahsisat: {ipo['tahsisat_gruplari'][:100]}")
        saved += 1

    print(f"\n── {saved} kayıt Firestore'a yazıldı. ──")


# ─────────────────────────────────────────────────────────────────
# 7) Giriş Noktası
# ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print("=" * 58)
    print(f"  Halka Arz Bot  —  {datetime.now():%Y-%m-%d %H:%M:%S}")
    print("=" * 58)

    ipos = scrape()
    upsert_to_firestore(ipos)

    t = sum(1 for i in ipos if i["durum"] == "taslak")
    ta = sum(1 for i in ipos if i["durum"] == "talep_topluyor")
    print(f"\n[İSTATİSTİK] Taslak:{t} | Talep:{ta} | Toplam:{len(ipos)}")
