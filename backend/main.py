#!/usr/bin/env python3
"""
Halka Arz Takip Botu — Hibrit Mimari (halkarz.com Kazıma + CollectAPI Fiyat)
=============================================================================
GitHub Actions üzerinde günde 1 kez (saat 20:00 TR) çalışır.

Veri Kaynakları:
  - halkarz.com (BeautifulSoup) → Halka arz listesi ve şirket detayları
  - CollectAPI /economy/hisseSenedi → Canlı Borsa fiyatları

Veritabanı:
  - Firestore "halka_arzlar" koleksiyonu → IPO bilgileri + fiyat geçmişi
  - Firestore "meta/notification_state" → Bildirim durum takibi
  - Firebase Realtime Database /prices → Canlı fiyatlar (mevcut mantık)

Bildirimler:
  - FCM v1 API → Yeni arz, tavan/taban bildirimleri
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
from google.oauth2 import service_account
from google.auth.transport.requests import Request

# ─── Yapılandırma ─────────────────────────────────────────────────────────────

COLLECT_API_KEY = os.environ.get("COLLECT_API_KEY", "")
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_SA_KEY_JSON = os.environ.get("FIREBASE_SA_KEY_JSON", "")
FIREBASE_RTDB_URL = os.environ.get("FIREBASE_RTDB_URL", "")

COLLECT_BASE = "https://api.collectapi.com/economy"
FIRESTORE_COLLECTION = "halka_arzlar"
STATE_DOC_PATH = "meta/notification_state"

# BIST limitleri (mevcut mantıkla birebir aynı)
TAVAN_CARPANI = 1.10
TABAN_CARPANI = 0.90
TAVAN_ESIGI = 0.999   # %0.1 tolerans
TABAN_ESIGI = 1.001

FCM_V1_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

SCRAPE_BASE_URL = "https://halkarz.com"
SCRAPE_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9",
}

AY_MAP = {
    "ocak": 1, "şubat": 2, "mart": 3, "nisan": 4,
    "mayıs": 5, "haziran": 6, "temmuz": 7, "ağustos": 8,
    "eylül": 9, "ekim": 10, "kasım": 11, "aralık": 12,
}

# ═══════════════════════════════════════════════════════════════════════════════
# FIREBASE AUTH — Ortak token alma (FCM, RTDB, Firestore)
# ═══════════════════════════════════════════════════════════════════════════════

def _get_credentials(scopes: list[str]):
    if not FIREBASE_SA_KEY_JSON:
        print("[UYARI] FIREBASE_SA_KEY_JSON ayarlanmadı.")
        return None
    try:
        sa_info = json.loads(FIREBASE_SA_KEY_JSON)
        creds = service_account.Credentials.from_service_account_info(sa_info, scopes=scopes)
        creds.refresh(Request())
        return creds
    except Exception as e:
        print(f"[HATA] Firebase credentials alınamadı: {e}")
        return None

def get_fcm_access_token() -> Optional[str]:
    creds = _get_credentials(["https://www.googleapis.com/auth/firebase.messaging"])
    return creds.token if creds else None

def get_firestore_access_token() -> Optional[str]:
    creds = _get_credentials(["https://www.googleapis.com/auth/datastore"])
    return creds.token if creds else None

def get_rtdb_access_token() -> Optional[str]:
    creds = _get_credentials([
        "https://www.googleapis.com/auth/firebase.database",
        "https://www.googleapis.com/auth/userinfo.email",
    ])
    return creds.token if creds else None


# ═══════════════════════════════════════════════════════════════════════════════
# WEB SCRAPING — halkarz.com Kazıma İşlemleri
# ═══════════════════════════════════════════════════════════════════════════════

def safe_get(url: str, timeout: int = 15) -> Optional[requests.Response]:
    time.sleep(random.uniform(0.8, 1.5))
    try:
        resp = requests.get(url, headers=SCRAPE_HEADERS, timeout=timeout)
        resp.raise_for_status()
        return resp
    except requests.RequestException as e:
        print(f"  [HATA] {url}: {e}")
        return None

def parse_date_range(date_str: str):
    if not date_str or "hazırlanıyor" in date_str.lower():
        return None, None
    clean = re.sub(r"\(.*?\)", "", date_str).strip()
    year_m = re.search(r"(\d{4})", clean)
    year = int(year_m.group(1)) if year_m else datetime.now().year
    days = re.findall(r"\b(\d{1,2})\b", clean)
    months = [m for m in re.findall(r"([a-zA-ZğüşıöçĞÜŞİÖÇ]+)", clean.lower()) if m in AY_MAP]
    if not days or not months:
        return None, None
    try:
        start_dt = datetime(year, AY_MAP[months[0]], int(days[0]))
        end_dt = datetime(year, AY_MAP[months[-1]], int(days[-1]))
        return start_dt, end_dt
    except ValueError:
        return None, None

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

def _extract_section(full_text: str, header: str, next_headers: list[str]) -> str:
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
            lt = txt.lower()
            val = txt.split(":")[-1].strip() if ":" in txt else ""

            if "halka arz fiyatı" in lt and val:
                d["arz_fiyati"] = clean_money(val)
            elif ("pay" in lt and "lot" in lt) and val:
                d["toplam_lot"] = clean_lot(val)
            elif "dağıtım" in lt and val:
                d["dagitim_sekli"] = "Oransal" if "oransal" in val.lower() else "Eşit"
            elif "aracı kurum" in lt and val:
                d["konsorsiyum_lideri"] = val
            elif "kişi başı" in lt and val:
                d["kisi_basi_lot"] = val
        break

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

    sec = _extract_section(full_text, "Halka Arz Şekli", section_headers)
    if sec: d["halka_arz_sekli"] = sec

    sec = _extract_section(full_text, "Fonun Kullanım Yeri", section_headers)
    if sec: d["fonun_kullanim_yeri"] = sec

    sec = _extract_section(full_text, "Halka Arz Satış Yöntemi", section_headers)
    if sec: d["satis_yontemi"] = sec

    sec = _extract_section(full_text, "Tahsisat Grupları", section_headers)
    if sec:
        d["tahsisat_gruplari"] = sec
        bireysel = re.search(r"([\d.]+)\s*Lot\s*\(%?(\d+)\)\s*.*?Bireysel", sec)
        if bireysel:
            d["bireysel_lot"] = clean_lot(bireysel.group(1))
            try: d["bireysel_yuzde"] = int(bireysel.group(2))
            except ValueError: pass

    katilim_text = full_text.lower()
    if "katılım endeksi" in katilim_text:
        if "uygun" in katilim_text[katilim_text.find("katılım endeksi"):katilim_text.find("katılım endeksi")+100]:
            d["katilim_endeksine_uygun"] = True

    sirket_h2 = None
    for h2 in soup.find_all("h2"):
        if h2.get_text(strip=True).startswith("(") or "A.Ş." in h2.get_text(strip=True):
            sirket_h2 = h2
            break
    if sirket_h2:
        sib = sirket_h2.find_next_sibling("p")
        if sib:
            d["sirket_aciklama"] = sib.get_text(strip=True)[:500]

    return d


def scrape_halkarz_com() -> list[dict]:
    """halkarz.com'u tarar ve detaylı listeyi döndürür."""
    print(f"\n[1/6] halkarz.com ana sayfa kazınıyor...")
    resp = safe_get(SCRAPE_BASE_URL)
    if not resp:
        print("  halkarz.com'a ulaşılamadı.")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")
    arz_lists = soup.find_all("ul", class_="halka-arz-list")
    
    # Sadece ilk listeyi (Sıradaki ve yeni arzlar) ve varsa Taslakları tara
    results = []
    
    for ul in arz_lists[:2]:
        items = ul.find_all("li", recursive=False)
        for li in items:
            article = li.find("article", class_="index-list")
            if not article:
                continue

            h3 = article.find("h3", class_="il-halka-arz-sirket")
            if not h3: continue
            a_tag = h3.find("a")
            sirket_adi = a_tag.get_text(strip=True) if a_tag else h3.get_text(strip=True)

            bist_span = article.find("span", class_="il-bist-kod")
            bist_kod = bist_span.get_text(strip=True).upper() if bist_span else ""
            if not bist_kod:
                bist_kod = re.sub(r"[^A-Z0-9]", "", sirket_adi.upper())[:10]

            tarih_span = article.find("span", class_="il-halka-arz-tarihi")
            tarih_str = ""
            if tarih_span:
                time_tag = tarih_span.find("time")
                tarih_str = (time_tag.get("datetime", time_tag.get_text(strip=True)) if time_tag else tarih_span.get_text(strip=True))

            start_dt, end_dt = parse_date_range(tarih_str)

            detail_url = ""
            if a_tag and a_tag.get("href"):
                href = a_tag["href"]
                detail_url = href if href.startswith("http") else SCRAPE_BASE_URL + href

            print(f"  ↳ {sirket_adi} ({bist_kod}) detayları çekiliyor...")
            det = fetch_all_details(detail_url)

            entry = {
                "sirket_kodu": bist_kod,
                "sirket_adi": sirket_adi,
                "tarih_str": tarih_str,
                "start_dt": start_dt,
                "end_dt": end_dt,
                **det
            }
            results.append(entry)

    print(f"[✓] {len(results)} halka arz web'den kazındı.")
    return results


def kategorize_et(start_dt: Optional[datetime], end_dt: Optional[datetime], bugun: datetime) -> Optional[str]:
    """Tarih aralığına göre halka arzın Firebase kategorisini (durum) belirler."""
    if not start_dt or not end_dt:
        return None  # Taslak (tarihi belirsiz) → kategorize etmeyiz
    
    bugun_date = bugun.date()
    start_date = start_dt.date()
    end_date = end_dt.date()
    
    if bugun_date < start_date:
        return "talep"            # Tarihi henüz gelmemiş
    elif start_date <= bugun_date <= end_date:
        return "arz"              # Bugün talep toplama aşamasında
    else:
        return "islem_goruyor"    # Talep tarihi geçmiş -> Borsaya girdi/girecek


# ═══════════════════════════════════════════════════════════════════════════════
# COLLECTAPI — Borsa Fiyatlarını Çekme
# ═══════════════════════════════════════════════════════════════════════════════

def _collect_headers() -> dict:
    auth_val = COLLECT_API_KEY
    if not auth_val.lower().startswith("apikey "):
        auth_val = f"apikey {COLLECT_API_KEY}"
    return {
        "Authorization": auth_val,
        "Content-Type": "application/json",
    }

def fetch_hisse_fiyatlari() -> dict[str, dict]:
    """CollectAPI /economy/hisseSenedi endpoint'inden BIST fiyatlarını çeker."""
    if not COLLECT_API_KEY:
        print("[HATA] COLLECT_API_KEY ayarlanmadı.")
        return {}
    try:
        resp = requests.get(f"{COLLECT_BASE}/hisseSenedi", headers=_collect_headers(), timeout=30)
        resp.raise_for_status()
        data = resp.json()
        if not data.get("success"):
            print(f"[HATA] CollectAPI hisseSenedi başarısız: {data}")
            return {}

        results = data.get("result", [])
        fiyat_map = {}
        for item in results:
            kod = (item.get("code") or item.get("kod") or "").replace(".IS", "").strip().upper()
            if not kod: continue
            try:
                son = float(str(item.get("lastprice", item.get("son_fiyat", "0"))).replace(",", "."))
                onceki = float(str(item.get("previousClose", item.get("onceki_kapanis", "0"))).replace(",", "."))
                fiyat_map[kod] = {"son_fiyat": son, "onceki_kapanis": onceki if onceki > 0 else son}
            except (ValueError, TypeError): continue
        print(f"[COLLECT] hisseSenedi → {len(fiyat_map)} hisse fiyatı alındı.")
        return fiyat_map
    except Exception as e:
        print(f"[HATA] CollectAPI hisseSenedi: {e}")
        return {}


# ═══════════════════════════════════════════════════════════════════════════════
# FIRESTORE & BİLDİRİM & RTDB İŞLEMLERİ
# ═══════════════════════════════════════════════════════════════════════════════

def _firestore_url(path: str) -> str:
    return f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/{path}"

def _to_firestore_value(val):
    if val is None: return {"nullValue": None}
    if isinstance(val, bool): return {"booleanValue": val}
    if isinstance(val, int): return {"integerValue": str(val)}
    if isinstance(val, float): return {"doubleValue": val}
    if isinstance(val, str): return {"stringValue": val}
    if isinstance(val, list): return {"arrayValue": {"values": [_to_firestore_value(v) for v in val]}}
    if isinstance(val, dict): return {"mapValue": {"fields": {k: _to_firestore_value(v) for k, v in val.items()}}}
    return {"stringValue": str(val)}

def _from_firestore_value(fv: dict):
    if "stringValue" in fv: return fv["stringValue"]
    if "integerValue" in fv: return int(fv["integerValue"])
    if "doubleValue" in fv: return fv["doubleValue"]
    if "booleanValue" in fv: return fv["booleanValue"]
    if "nullValue" in fv: return None
    if "arrayValue" in fv: return [_from_firestore_value(v) for v in fv.get("arrayValue", {}).get("values", [])]
    if "mapValue" in fv: return {k: _from_firestore_value(v) for k, v in fv.get("mapValue", {}).get("fields", {}).items()}
    return None

def firestore_get_doc(doc_path: str) -> Optional[dict]:
    token = get_firestore_access_token()
    if not token: return None
    try:
        resp = requests.get(_firestore_url(doc_path), headers={"Authorization": f"Bearer {token}"}, timeout=15)
        if resp.status_code == 200:
            return {k: _from_firestore_value(v) for k, v in resp.json().get("fields", {}).items()}
        elif resp.status_code == 404:
            return {}
        return None
    except Exception: return None

def firestore_set_doc(doc_path: str, data: dict, merge: bool = False) -> bool:
    token = get_firestore_access_token()
    if not token: return False
    body = {"fields": {k: _to_firestore_value(v) for k, v in data.items()}}
    url = _firestore_url(doc_path)
    try:
        if merge:
            field_paths = "&".join([f"updateMask.fieldPaths={k}" for k in data.keys()])
            resp = requests.patch(f"{url}?{field_paths}", json=body, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, timeout=15)
        else:
            resp = requests.patch(url, json=body, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, timeout=15)
        return resp.status_code == 200
    except Exception: return False

def firestore_get_collection(collection: str) -> list[dict]:
    token = get_firestore_access_token()
    if not token: return []
    try:
        docs, page_token = [], None
        while True:
            params = {"pageSize": 100}
            if page_token: params["pageToken"] = page_token
            resp = requests.get(_firestore_url(collection), params=params, headers={"Authorization": f"Bearer {token}"}, timeout=30)
            if resp.status_code != 200: break
            result = resp.json()
            for doc in result.get("documents", []):
                parsed = {k: _from_firestore_value(v) for k, v in doc.get("fields", {}).items()}
                parsed["_doc_id"] = doc["name"].split("/")[-1]
                docs.append(parsed)
            page_token = result.get("nextPageToken")
            if not page_token: break
        return docs
    except Exception: return []


def send_fcm_notification(title: str, body: str, data: Optional[dict] = None) -> bool:
    if not FIREBASE_PROJECT_ID: return False
    access_token = get_fcm_access_token()
    if not access_token: return False
    message = {
        "message": {
            "topic": "halka_arz",
            "notification": {"title": title, "body": body},
            "android": {"priority": "high", "notification": {"sound": "default", "channel_id": "halka_arz_channel", "click_action": "FLUTTER_NOTIFICATION_CLICK"}},
            "apns": {"payload": {"aps": {"sound": "default", "badge": 1}}},
            "data": {k: str(v) for k, v in (data or {}).items()},
        }
    }
    try:
        resp = requests.post(FCM_V1_URL.format(project_id=FIREBASE_PROJECT_ID), json=message, headers={"Authorization": f"Bearer {access_token}", "Content-Type": "application/json; UTF-8"}, timeout=10)
        if resp.status_code == 200:
            print(f"[BİLDİRİM ✓] {title} — {body}")
            return True
        return False
    except Exception: return False

def write_prices_to_rtdb(prices: dict[str, float]) -> bool:
    if not FIREBASE_RTDB_URL or not prices: return False
    token = get_rtdb_access_token()
    if not token: return False
    url = f"{FIREBASE_RTDB_URL.rstrip('/')}/prices.json"
    try:
        resp = requests.patch(url, json=prices, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, timeout=15)
        if resp.status_code == 200:
            print(f"[RTDB ✓] {len(prices)} fiyat yazıldı.")
            return True
        return False
    except Exception: return False

def load_notification_state() -> dict: return firestore_get_doc(STATE_DOC_PATH) or {}
def save_notification_state(state: dict) -> bool: return firestore_set_doc(STATE_DOC_PATH, state, merge=False)

def get_stock_state(current_price: float, previous_close: float) -> str:
    tavan = round(previous_close * TAVAN_CARPANI, 2)
    taban = round(previous_close * TABAN_CARPANI, 2)
    if current_price >= tavan * TAVAN_ESIGI: return "tavan"
    elif current_price <= taban * TABAN_ESIGI: return "taban"
    return "normal"

def process_tavan_taban(ticker: str, adi: str, current_price: float, previous_close: float, state: dict) -> dict:
    tavan = round(previous_close * TAVAN_CARPANI, 2)
    taban = round(previous_close * TABAN_CARPANI, 2)
    current_state = get_stock_state(current_price, previous_close)
    previous_state = state.get(f"stock_state_{ticker}", "normal")

    if current_state == previous_state: return state

    if current_state == "tavan" and previous_state != "tavan":
        if previous_state == "taban": send_fcm_notification("📈 Taban Bozdu!", f"{adi} tabandan çıktı! Taban: ₺{taban} → Anlık: ₺{current_price}", {"type": "taban_bozdu", "ticker": ticker})
        send_fcm_notification("🚀 Tavan Yaptı!", f"{adi} tavan yaptı! Tavan: ₺{tavan} | Anlık: ₺{current_price}", {"type": "tavan_yapti", "ticker": ticker})
    elif previous_state == "tavan" and current_state != "tavan":
        send_fcm_notification("⚠️ Tavan Bozdu!", f"{adi} tavan bozdu! Tavan: ₺{tavan} → Anlık: ₺{current_price}", {"type": "tavan_bozdu", "ticker": ticker})
        if current_state == "taban": send_fcm_notification("📉 Taban Yaptı!", f"{adi} tabana indi! Taban: ₺{taban} | Anlık: ₺{current_price}", {"type": "taban_yapti", "ticker": ticker})
    elif current_state == "taban" and previous_state != "taban":
        send_fcm_notification("📉 Taban Yaptı!", f"{adi} tabana indi! Taban: ₺{taban} | Anlık: ₺{current_price}", {"type": "taban_yapti", "ticker": ticker})
    elif previous_state == "taban" and current_state == "normal":
        send_fcm_notification("📈 Taban Bozdu!", f"{adi} tabandan çıktı! Taban: ₺{taban} → Anlık: ₺{current_price}", {"type": "taban_bozdu", "ticker": ticker})

    state[f"stock_state_{ticker}"] = current_state
    state[f"stock_state_ts_{ticker}"] = datetime.now().isoformat()
    return state

def is_weekend(dt: datetime) -> bool: return dt.weekday() in (5, 6)

def cleanup_old_states(state: dict) -> dict:
    cutoff = datetime.now() - timedelta(days=7)
    cleaned = {}
    for k, v in state.items():
        try:
            if datetime.fromisoformat(str(v)) > cutoff: cleaned[k] = v
        except Exception: cleaned[k] = v
    return cleaned


# ═══════════════════════════════════════════════════════════════════════════════
# ANA FONKSİYON
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    bugun = datetime.now()
    print("=" * 60)
    print(f"Halka Arz Botu (HİBRİT) — {bugun.strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    ham_liste = scrape_halkarz_com()

    print("\n[2/6] Mevcut halka arzlar Firestore'dan çekiliyor...")
    existing_docs = firestore_get_collection(FIRESTORE_COLLECTION)
    
    print("\n[3/6] Bildirim durumu Firestore'dan okunuyor...")
    state = load_notification_state()

    print("\n[4/6] Veriler kategorize ediliyor ve birleştiriliyor...")
    
    islem_gorenler = {}
    talep_count = arz_count = atlanan_count = 0

    scraped_codes = set()
    for ipo in ham_liste:
        kod = ipo["sirket_kodu"]
        scraped_codes.add(kod)
        adi = ipo["sirket_adi"]

        kategori = kategorize_et(ipo["start_dt"], ipo["end_dt"], bugun)
        if not kategori:
            atlanan_count += 1
            print(f"  [ATLANDI] {adi} ({kod}) — tarih belirsiz (taslak)")
            continue

        del ipo["start_dt"]
        del ipo["end_dt"]
        ipo["durum"] = kategori
        ipo["guncelleme_zamani"] = bugun.isoformat()

        doc_path = f"{FIRESTORE_COLLECTION}/{kod}"

        if kategori == "talep":
            firestore_set_doc(doc_path, ipo, merge=False)
            talep_count += 1
            if f"yeni_arz_{kod}" not in state:
                send_fcm_notification("🆕 Yeni Halka Arz!", f"{adi} — ₺{ipo['arz_fiyati']}", {"type": "yeni_arz", "ticker": kod})
                state[f"yeni_arz_{kod}"] = bugun.isoformat()

        elif kategori == "arz":
            firestore_set_doc(doc_path, ipo, merge=False)
            arz_count += 1
            if f"yeni_arz_{kod}" not in state:
                send_fcm_notification("🆕 Yeni Halka Arz!", f"{adi} — ₺{ipo['arz_fiyati']}", {"type": "yeni_arz", "ticker": kod})
                state[f"yeni_arz_{kod}"] = bugun.isoformat()
            
            durum_key = f"durum_degisim_{kod}_arz"
            if durum_key not in state:
                send_fcm_notification("📢 Talep Toplama Başladı!", f"{adi} halka arzı şu an talep topluyor!", {"type": "talep_basladi", "ticker": kod})
                state[durum_key] = bugun.isoformat()

        elif kategori == "islem_goruyor":
            islem_gorenler[kod] = ipo


    for doc in existing_docs:
        kod = doc.get("_doc_id", "")
        if kod and kod not in scraped_codes and doc.get("durum") == "islem_goruyor":
            doc["sirket_kodu"] = kod
            del doc["_doc_id"]
            islem_gorenler[kod] = doc

    print(f"\n[ÖZET] Talep: {talep_count} | Arz: {arz_count} | İşlem: {len(islem_gorenler)} | Atlanan: {atlanan_count}")

    print("\n[5/6] İşlem gören hisseler için fiyat kontrolü (CollectAPI)...")
    rtdb_prices = {}

    if islem_gorenler and not is_weekend(bugun):
        fiyat_map = fetch_hisse_fiyatlari()

        for kod, doc_data in islem_gorenler.items():
            adi = doc_data.get("sirket_adi", kod)
            fiyat_bilgi = fiyat_map.get(kod)
            
            if not fiyat_bilgi:
                firestore_set_doc(f"{FIRESTORE_COLLECTION}/{kod}", doc_data, merge=True)
                continue

            son_fiyat = fiyat_bilgi["son_fiyat"]
            onceki_kapanis = fiyat_bilgi["onceki_kapanis"]
            rtdb_prices[kod] = son_fiyat

            mevcut_doc = firestore_get_doc(f"{FIRESTORE_COLLECTION}/{kod}") or {}
            fiyat_gecmisi = mevcut_doc.get("fiyat_gecmisi", {})
            fiyat_gecmisi[bugun.strftime("%Y-%m-%d")] = son_fiyat

            doc_data["son_fiyat"] = son_fiyat
            doc_data["onceki_kapanis"] = onceki_kapanis
            doc_data["fiyat_gecmisi"] = fiyat_gecmisi
            doc_data["guncelleme_zamani"] = bugun.isoformat()

            firestore_set_doc(f"{FIRESTORE_COLLECTION}/{kod}", doc_data, merge=True)
            state = process_tavan_taban(kod, adi, son_fiyat, onceki_kapanis, state)

    elif is_weekend(bugun):
        print("  Hafta sonu nedeniyle fiyat güncellemesi atlandı.")
        for kod, doc_data in islem_gorenler.items():
            firestore_set_doc(f"{FIRESTORE_COLLECTION}/{kod}", doc_data, merge=True)

    print(f"\n[6/6] RTDB ve State güncelleniyor...")
    if rtdb_prices: write_prices_to_rtdb(rtdb_prices)
    save_notification_state(cleanup_old_states(state))

    print("\n" + "=" * 60)
    print(f"[BİLGİ] Hibrit Tarama Tamamlandı! RTDB: {len(rtdb_prices)} fiyat yazıldı.")
    print("=" * 60)

if __name__ == "__main__":
    main()
