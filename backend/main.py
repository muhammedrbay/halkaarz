#!/usr/bin/env python3
"""
Halka Arz Günlük Bot — halkarz.com Kazıma + Yahoo Finance Fiyat
================================================================
GitHub Actions: Her gün 08:00 TR

1. halkarz.com'dan ilk 20 halka arzı çeker
2. Kategorize eder: Taslak / Arz / İşlem
3. Taslak + Arz → detaylarıyla Firestore'a yazar
4. İşlem → Yahoo Finance fiyat çekip Firestore fiyat_gecmisi'ne ekler
5. Yeni arz veya durum değişikliği → FCM bildirim
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

# ─── Yapılandırma ─────────────────────────────────────────────────
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_SA_KEY_JSON = os.environ.get("FIREBASE_SA_KEY_JSON", "")
FIREBASE_RTDB_URL = os.environ.get("FIREBASE_RTDB_URL", "")

FIRESTORE_COLLECTION = "halka_arzlar"
STATE_DOC_PATH = "meta/notification_state"
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
MAX_IPO_COUNT = 20


# ═══════════════════════════════════════════════════════════════════
# FIREBASE AUTH
# ═══════════════════════════════════════════════════════════════════
def _get_credentials(scopes):
    if not FIREBASE_SA_KEY_JSON:
        print("[UYARI] FIREBASE_SA_KEY_JSON ayarlanmadı.")
        return None
    try:
        sa_info = json.loads(FIREBASE_SA_KEY_JSON)
        creds = service_account.Credentials.from_service_account_info(sa_info, scopes=scopes)
        creds.refresh(Request())
        return creds
    except Exception as e:
        print(f"[HATA] Firebase credentials: {e}")
        return None

def get_fcm_token():
    c = _get_credentials(["https://www.googleapis.com/auth/firebase.messaging"])
    return c.token if c else None

def get_firestore_token():
    c = _get_credentials(["https://www.googleapis.com/auth/datastore"])
    return c.token if c else None


# ═══════════════════════════════════════════════════════════════════
# FIRESTORE REST API
# ═══════════════════════════════════════════════════════════════════
def _fs_url(path):
    return f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/{path}"

def _to_fv(val):
    if val is None: return {"nullValue": None}
    if isinstance(val, bool): return {"booleanValue": val}
    if isinstance(val, int): return {"integerValue": str(val)}
    if isinstance(val, float): return {"doubleValue": val}
    if isinstance(val, str): return {"stringValue": val}
    if isinstance(val, list): return {"arrayValue": {"values": [_to_fv(v) for v in val]}}
    if isinstance(val, dict): return {"mapValue": {"fields": {k: _to_fv(v) for k, v in val.items()}}}
    return {"stringValue": str(val)}

def _from_fv(fv):
    if "stringValue" in fv: return fv["stringValue"]
    if "integerValue" in fv: return int(fv["integerValue"])
    if "doubleValue" in fv: return fv["doubleValue"]
    if "booleanValue" in fv: return fv["booleanValue"]
    if "nullValue" in fv: return None
    if "arrayValue" in fv: return [_from_fv(v) for v in fv.get("arrayValue", {}).get("values", [])]
    if "mapValue" in fv: return {k: _from_fv(v) for k, v in fv.get("mapValue", {}).get("fields", {}).items()}
    return None

def fs_get(doc_path):
    token = get_firestore_token()
    if not token: return None
    try:
        r = requests.get(_fs_url(doc_path), headers={"Authorization": f"Bearer {token}"}, timeout=15)
        if r.status_code == 200:
            return {k: _from_fv(v) for k, v in r.json().get("fields", {}).items()}
        if r.status_code == 404: return {}
        return None
    except: return None

def fs_set(doc_path, data, merge=False):
    token = get_firestore_token()
    if not token: return False
    body = {"fields": {k: _to_fv(v) for k, v in data.items()}}
    url = _fs_url(doc_path)
    try:
        if merge:
            fp = "&".join([f"updateMask.fieldPaths={k}" for k in data.keys()])
            r = requests.patch(f"{url}?{fp}", json=body, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, timeout=15)
        else:
            r = requests.patch(url, json=body, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, timeout=15)
        return r.status_code == 200
    except: return False

def fs_collection(col):
    token = get_firestore_token()
    if not token: return []
    docs, pt = [], None
    try:
        while True:
            params = {"pageSize": 100}
            if pt: params["pageToken"] = pt
            r = requests.get(_fs_url(col), params=params, headers={"Authorization": f"Bearer {token}"}, timeout=30)
            if r.status_code != 200: break
            res = r.json()
            for doc in res.get("documents", []):
                p = {k: _from_fv(v) for k, v in doc.get("fields", {}).items()}
                p["_doc_id"] = doc["name"].split("/")[-1]
                docs.append(p)
            pt = res.get("nextPageToken")
            if not pt: break
        return docs
    except: return []


# ═══════════════════════════════════════════════════════════════════
# FCM BİLDİRİM
# ═══════════════════════════════════════════════════════════════════
def send_fcm(title, body, data=None):
    if not FIREBASE_PROJECT_ID: return False
    token = get_fcm_token()
    if not token: return False
    msg = {
        "message": {
            "topic": "halka_arz",
            "notification": {"title": title, "body": body},
            "android": {"priority": "high", "notification": {"sound": "default", "channel_id": "halka_arz_channel", "click_action": "FLUTTER_NOTIFICATION_CLICK"}},
            "apns": {"payload": {"aps": {"sound": "default", "badge": 1}}},
            "data": {k: str(v) for k, v in (data or {}).items()},
        }
    }
    try:
        r = requests.post(FCM_V1_URL.format(project_id=FIREBASE_PROJECT_ID), json=msg,
                          headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json; UTF-8"}, timeout=10)
        if r.status_code == 200:
            print(f"  [FCM ✓] {title}")
            return True
        print(f"  [FCM HATA] {r.status_code}: {r.text[:100]}")
        return False
    except: return False


# ═══════════════════════════════════════════════════════════════════
# WEB SCRAPING — halkarz.com
# ═══════════════════════════════════════════════════════════════════
def safe_get(url, timeout=15):
    time.sleep(random.uniform(0.5, 1.2))
    try:
        r = requests.get(url, headers=SCRAPE_HEADERS, timeout=timeout)
        r.raise_for_status()
        return r
    except requests.RequestException as e:
        print(f"  [HATA] {url}: {e}")
        return None

def parse_date_range(date_str):
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

def clean_money(text):
    text = text.replace("TL", "").replace("₺", "").strip().split("/")[0].strip()
    text = text.replace(".", "").replace(",", ".")
    try: return float(text)
    except: return 0.0

def clean_lot(text):
    text = text.lower().replace("lot", "").replace(".", "").replace(",", "").strip()
    try: return int(text)
    except: return 0

def fetch_detail(url):
    defaults = {"arz_fiyati": 0.0, "toplam_lot": 0, "dagitim_sekli": "Eşit", "konsorsiyum_lideri": "", "katilim_endeksine_uygun": False, "kisi_basi_lot": "", "halka_arz_sekli": "", "fonun_kullanim_yeri": "", "satis_yontemi": "", "tahsisat_gruplari": "", "bireysel_lot": 0, "bireysel_yuzde": 0, "sirket_aciklama": ""}
    if not url: return defaults
    resp = safe_get(url)
    if not resp: return defaults
    soup = BeautifulSoup(resp.text, "html.parser")
    d = dict(defaults)

    for tbl in soup.find_all("table"):
        for tr in tbl.find_all("tr"):
            txt = tr.get_text(" ", strip=True)
            lt = txt.lower()
            val = txt.split(":")[-1].strip() if ":" in txt else ""
            if "halka arz fiyatı" in lt and val: d["arz_fiyati"] = clean_money(val)
            elif ("pay" in lt and "lot" in lt) and val: d["toplam_lot"] = clean_lot(val)
            elif "dağıtım" in lt and val: d["dagitim_sekli"] = "Oransal" if "oransal" in val.lower() else "Eşit"
            elif "aracı kurum" in lt and val: d["konsorsiyum_lideri"] = val
            elif "kişi başı" in lt and val: d["kisi_basi_lot"] = val
        break

    body = soup.find("body")
    if not body: return d
    full_text = body.get_text("\n", strip=True)

    section_headers = ["Halka Arz Şekli", "Fonun Kullanım Yeri", "Halka Arz Satış Yöntemi", "Tahsisat Grupları", "Dağıtılacak Pay Miktarı", "Katılım Endeksi", "Özet Bilgiler", "Forum", "Başvuru Yerleri", "Halka Arz Bilgileri", "Grafiği"]

    for key, header in [("halka_arz_sekli", "Halka Arz Şekli"), ("fonun_kullanim_yeri", "Fonun Kullanım Yeri"), ("satis_yontemi", "Halka Arz Satış Yöntemi"), ("tahsisat_gruplari", "Tahsisat Grupları")]:
        lt = full_text.lower()
        start = lt.find(header.lower())
        if start < 0: continue
        start += len(header)
        end = len(full_text)
        for nh in section_headers:
            pos = lt.find(nh.lower(), start)
            if 0 < pos < end: end = pos
        sec = full_text[start:end].strip()
        if sec: d[key] = sec

    if "katılım endeksi" in full_text.lower():
        idx = full_text.lower().find("katılım endeksi")
        if "uygun" in full_text.lower()[idx:idx+100]:
            d["katilim_endeksine_uygun"] = True

    for h2 in soup.find_all("h2"):
        if h2.get_text(strip=True).startswith("(") or "A.Ş." in h2.get_text(strip=True):
            sib = h2.find_next_sibling("p")
            if sib: d["sirket_aciklama"] = sib.get_text(strip=True)[:500]
            break
    return d


def scrape_first_20():
    """halkarz.com'dan ilk 20 halka arzı kazır."""
    print("[1/4] halkarz.com kazınıyor...")
    resp = safe_get(SCRAPE_BASE_URL)
    if not resp:
        print("  halkarz.com'a ulaşılamadı.")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")
    arz_lists = soup.find_all("ul", class_="halka-arz-list")
    if not arz_lists:
        print("  halka-arz-list bulunamadı.")
        return []

    results = []
    items = arz_lists[0].find_all("li", recursive=False)

    for li in items[:MAX_IPO_COUNT]:
        article = li.find("article", class_="index-list")
        if not article: continue

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

        results.append({
            "sirket_kodu": bist_kod, "sirket_adi": sirket_adi,
            "tarih_str": tarih_str, "start_dt": start_dt, "end_dt": end_dt,
            "detail_url": detail_url,
        })

    print(f"  {len(results)} halka arz bulundu.")
    return results


def kategorize(start_dt, end_dt, bugun):
    if not start_dt or not end_dt: return "taslak"
    bugun_d = bugun.date()
    if bugun_d < start_dt.date(): return "taslak"
    elif start_dt.date() <= bugun_d <= end_dt.date(): return "arz"
    else: return "islem"


# ═══════════════════════════════════════════════════════════════════
# YAHOO FINANCE — Kapanış fiyatı (işlem gören hisseler için)
# ═══════════════════════════════════════════════════════════════════
def fetch_yahoo_prices(ticker_list):
    """Yahoo Finance'ten hisse fiyatlarını çeker. Dönüş: {KOD: fiyat}"""
    if not ticker_list: return {}
    try:
        import yfinance as yf
        symbols = [f"{t}.IS" for t in ticker_list]
        print(f"  Yahoo Finance: {len(symbols)} hisse sorgulanıyor...")
        prices = {}
        for kod, sym in zip(ticker_list, symbols):
            try:
                tk = yf.Ticker(sym)
                hist = tk.history(period="1d")
                if not hist.empty:
                    prices[kod] = round(float(hist["Close"].iloc[-1]), 2)
                    print(f"    {kod} → ₺{prices[kod]}")
            except Exception as e:
                print(f"    {kod} fiyat alınamadı: {e}")
        return prices
    except ImportError:
        print("  [HATA] yfinance yüklü değil!")
        return {}


# ═══════════════════════════════════════════════════════════════════
# ANA FONKSİYON
# ═══════════════════════════════════════════════════════════════════
def main():
    bugun = datetime.now()
    print("=" * 60)
    print(f"  Günlük Halka Arz Botu — {bugun.strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    # 1. Scrape
    raw_list = scrape_first_20()
    if not raw_list:
        print("[BİTTİ] Veri alınamadı.")
        return

    # 2. Mevcut state'i oku
    print("\n[2/4] Bildirim durumu okunuyor...")
    state = fs_get(STATE_DOC_PATH) or {}
    prev_docs = {d["_doc_id"]: d for d in fs_collection(FIRESTORE_COLLECTION)}

    # 3. Kategorize et ve işle
    print("\n[3/4] Kategorize ediliyor ve Firestore'a yazılıyor...")
    taslak_list, arz_list, islem_list = [], [], []

    for item in raw_list:
        kod = item["sirket_kodu"]
        adi = item["sirket_adi"]
        kat = kategorize(item["start_dt"], item["end_dt"], bugun)

        if kat == "taslak":
            taslak_list.append(item)
        elif kat == "arz":
            arz_list.append(item)
        else:
            islem_list.append(item)

    # ── TASLAK + ARZ → Detay çekip Firestore'a yaz ──
    for item in taslak_list + arz_list:
        kod = item["sirket_kodu"]
        adi = item["sirket_adi"]
        kat = "taslak" if item in taslak_list else "arz"

        print(f"  [{kat.upper()}] {adi} ({kod}) detay çekiliyor...")
        det = fetch_detail(item["detail_url"])

        doc = {
            "sirket_kodu": kod, "sirket_adi": adi, "durum": kat,
            "tarih": item["tarih_str"],
            "arz_fiyati": det["arz_fiyati"], "toplam_lot": det["toplam_lot"],
            "dagitim_sekli": det["dagitim_sekli"], "konsorsiyum_lideri": det["konsorsiyum_lideri"],
            "katilim_endeksine_uygun": det["katilim_endeksine_uygun"],
            "kisi_basi_lot": det["kisi_basi_lot"], "halka_arz_sekli": det["halka_arz_sekli"],
            "fonun_kullanim_yeri": det["fonun_kullanim_yeri"], "satis_yontemi": det["satis_yontemi"],
            "tahsisat_gruplari": det["tahsisat_gruplari"], "bireysel_lot": det["bireysel_lot"],
            "bireysel_yuzde": det["bireysel_yuzde"], "sirket_aciklama": det["sirket_aciklama"],
            "guncelleme_zamani": bugun.isoformat(),
        }
        fs_set(f"{FIRESTORE_COLLECTION}/{kod}", doc, merge=False)

        # Bildirim: yeni arz mı?
        if f"yeni_arz_{kod}" not in state:
            send_fcm("🆕 Yeni Halka Arz!", f"{adi} — ₺{det['arz_fiyati']}", {"type": "yeni_arz", "ticker": kod})
            state[f"yeni_arz_{kod}"] = bugun.isoformat()

        # Bildirim: durum değişikliği?
        prev = prev_docs.get(kod, {})
        if prev.get("durum") and prev["durum"] != kat:
            if kat == "arz":
                send_fcm("📢 Talep Toplama Başladı!", f"{adi} halka arzı talep topluyor!", {"type": "durum_degisim", "ticker": kod})
            state[f"durum_{kod}_{kat}"] = bugun.isoformat()

    # ── İŞLEM → Yahoo Finance fiyat + Firestore güncelle ──
    if islem_list:
        print(f"\n  İşlem gören {len(islem_list)} hisse için fiyat çekiliyor...")
        islem_kodlari = [i["sirket_kodu"] for i in islem_list]
        fiyatlar = fetch_yahoo_prices(islem_kodlari)

        for item in islem_list:
            kod = item["sirket_kodu"]
            adi = item["sirket_adi"]
            fiyat = fiyatlar.get(kod)

            # Mevcut dokümanı oku
            mevcut = fs_get(f"{FIRESTORE_COLLECTION}/{kod}") or {}
            fiyat_gecmisi = mevcut.get("fiyat_gecmisi", {})
            if not isinstance(fiyat_gecmisi, dict): fiyat_gecmisi = {}

            update = {
                "sirket_kodu": kod, "sirket_adi": adi, "durum": "islem",
                "tarih": item["tarih_str"], "guncelleme_zamani": bugun.isoformat(),
            }

            if fiyat:
                fiyat_gecmisi[bugun.strftime("%Y-%m-%d")] = fiyat
                update["son_fiyat"] = fiyat
                update["fiyat_gecmisi"] = fiyat_gecmisi
                print(f"  [İŞLEM] {adi} ({kod}) → ₺{fiyat}")
            else:
                print(f"  [İŞLEM] {adi} ({kod}) → fiyat alınamadı")

            fs_set(f"{FIRESTORE_COLLECTION}/{kod}", update, merge=True)

            # Bildirim: durum değişikliği (arz → islem)?
            prev = prev_docs.get(kod, {})
            if prev.get("durum") and prev["durum"] != "islem":
                dkey = f"durum_{kod}_islem"
                if dkey not in state:
                    send_fcm("🔔 Borsada İşlem Başladı!", f"{adi} artık borsada işlem görüyor!", {"type": "islem_basladi", "ticker": kod})
                    state[dkey] = bugun.isoformat()

    # 4. State kaydet
    print(f"\n[4/4] Bildirim durumu kaydediliyor...")
    # Eski kayıtları temizle (7 günden eski)
    cutoff = bugun - timedelta(days=7)
    cleaned = {}
    for k, v in state.items():
        try:
            if datetime.fromisoformat(str(v)) > cutoff: cleaned[k] = v
        except: cleaned[k] = v
    fs_set(STATE_DOC_PATH, cleaned, merge=False)

    print("\n" + "=" * 60)
    print(f"  Taslak: {len(taslak_list)} | Arz: {len(arz_list)} | İşlem: {len(islem_list)}")
    print("=" * 60)


if __name__ == "__main__":
    main()
