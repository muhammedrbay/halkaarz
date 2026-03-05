#!/usr/bin/env python3
"""
Halka Arz Canlı Fiyat Takibi — Yahoo Finance → Realtime Database
=================================================================
GitHub Actions: Her ~8 dk'da bir, hafta içi borsa saatlerinde (09:30–18:10 TR)

1. Firestore'dan "islem" durumundaki hisseleri çeker
2. Yahoo Finance'ten anlık fiyatları alır (15 dk gecikmeli)
3. Realtime Database'e yazar (/prices/{KOD})
4. Dünkü kapanışla karşılaştırır: Tavan/Taban → FCM bildirim
"""

import json
import os
from datetime import datetime, timezone, timedelta
from typing import Optional

import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request

# ─── Yapılandırma ─────────────────────────────────────────────────
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_SA_KEY_JSON = os.environ.get("FIREBASE_SA_KEY_JSON", "")
FIREBASE_RTDB_URL = os.environ.get("FIREBASE_RTDB_URL", "")

FIRESTORE_COLLECTION = "halka_arzlar"
STATE_DOC_PATH = "meta/price_tracker_state"
FCM_V1_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

# BIST tavan/taban kuralları
TAVAN_CARPANI = 1.10
TABAN_CARPANI = 0.90
TAVAN_ESIGI = 0.999   # %0.1 tolerans
TABAN_ESIGI = 1.001

# TR saat dilimi (UTC+3)
TR_TZ = timezone(timedelta(hours=3))

# Borsa saatleri (TR)
BORSA_ACILIS = (9, 30)   # 09:30
BORSA_KAPANIS = (18, 10)  # 18:10


# ═══════════════════════════════════════════════════════════════════
# SAAT KONTROLÜ
# ═══════════════════════════════════════════════════════════════════
def borsa_acik_mi():
    """Borsa şu an açık mı? (Hafta içi 09:30–18:10 TR)"""
    now_tr = datetime.now(TR_TZ)
    # Hafta sonu
    if now_tr.weekday() >= 5:
        print(f"[BİLGİ] Hafta sonu ({now_tr.strftime('%A')}) — çıkılıyor.")
        return False
    # Saat kontrolü
    saat = now_tr.hour * 60 + now_tr.minute
    acilis = BORSA_ACILIS[0] * 60 + BORSA_ACILIS[1]
    kapanis = BORSA_KAPANIS[0] * 60 + BORSA_KAPANIS[1]
    if saat < acilis or saat > kapanis:
        print(f"[BİLGİ] Borsa kapalı ({now_tr.strftime('%H:%M')} TR) — çıkılıyor.")
        return False
    return True


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

def get_rtdb_token():
    c = _get_credentials(["https://www.googleapis.com/auth/firebase.database", "https://www.googleapis.com/auth/userinfo.email"])
    return c.token if c else None


# ═══════════════════════════════════════════════════════════════════
# FIRESTORE
# ═══════════════════════════════════════════════════════════════════
def _fs_url(path):
    return f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/{path}"

def _from_fv(fv):
    if "stringValue" in fv: return fv["stringValue"]
    if "integerValue" in fv: return int(fv["integerValue"])
    if "doubleValue" in fv: return fv["doubleValue"]
    if "booleanValue" in fv: return fv["booleanValue"]
    if "nullValue" in fv: return None
    if "arrayValue" in fv: return [_from_fv(v) for v in fv.get("arrayValue", {}).get("values", [])]
    if "mapValue" in fv: return {k: _from_fv(v) for k, v in fv.get("mapValue", {}).get("fields", {}).items()}
    return None

def _to_fv(val):
    if val is None: return {"nullValue": None}
    if isinstance(val, bool): return {"booleanValue": val}
    if isinstance(val, int): return {"integerValue": str(val)}
    if isinstance(val, float): return {"doubleValue": val}
    if isinstance(val, str): return {"stringValue": val}
    if isinstance(val, list): return {"arrayValue": {"values": [_to_fv(v) for v in val]}}
    if isinstance(val, dict): return {"mapValue": {"fields": {k: _to_fv(v) for k, v in val.items()}}}
    return {"stringValue": str(val)}

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

def get_islem_hisseleri():
    """Firestore'dan durum='islem' olan hisseleri çeker."""
    token = get_firestore_token()
    if not token: return []
    docs, pt = [], None
    try:
        while True:
            params = {"pageSize": 100}
            if pt: params["pageToken"] = pt
            r = requests.get(_fs_url(FIRESTORE_COLLECTION), params=params, headers={"Authorization": f"Bearer {token}"}, timeout=30)
            if r.status_code != 200: break
            res = r.json()
            for doc in res.get("documents", []):
                p = {k: _from_fv(v) for k, v in doc.get("fields", {}).items()}
                p["_doc_id"] = doc["name"].split("/")[-1]
                if p.get("durum") == "islem":
                    docs.append(p)
            pt = res.get("nextPageToken")
            if not pt: break
        return docs
    except: return []


# ═══════════════════════════════════════════════════════════════════
# RTDB
# ═══════════════════════════════════════════════════════════════════
def rtdb_write_prices(prices):
    """Realtime Database'e fiyatları yazar. Format: /prices/{KOD}: fiyat"""
    if not FIREBASE_RTDB_URL or not prices: return False
    token = get_rtdb_token()
    if not token: return False
    url = f"{FIREBASE_RTDB_URL.rstrip('/')}/prices.json"
    try:
        r = requests.patch(url, json=prices, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, timeout=15)
        if r.status_code == 200:
            print(f"  [RTDB ✓] {len(prices)} fiyat yazıldı.")
            return True
        return False
    except: return False


# ═══════════════════════════════════════════════════════════════════
# FCM
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
        return False
    except: return False


# ═══════════════════════════════════════════════════════════════════
# YAHOO FINANCE
# ═══════════════════════════════════════════════════════════════════
def fetch_live_prices(ticker_list):
    """Yahoo Finance'ten canlı fiyat çeker. Dönüş: {KOD: fiyat}"""
    if not ticker_list: return {}
    try:
        import yfinance as yf
        prices = {}
        symbols = " ".join([f"{t}.IS" for t in ticker_list])
        tickers = yf.Tickers(symbols)
        for kod in ticker_list:
            sym = f"{kod}.IS"
            try:
                info = tickers.tickers[sym].fast_info
                price = round(float(info.last_price), 2)
                prices[kod] = price
            except Exception:
                try:
                    tk = yf.Ticker(sym)
                    hist = tk.history(period="1d")
                    if not hist.empty:
                        prices[kod] = round(float(hist["Close"].iloc[-1]), 2)
                except Exception as e:
                    print(f"    {kod} fiyat alınamadı: {e}")
        return prices
    except ImportError:
        print("  [HATA] yfinance yüklü değil!")
        return {}


# ═══════════════════════════════════════════════════════════════════
# TAVAN / TABAN KONTROLÜ
# ═══════════════════════════════════════════════════════════════════
def check_tavan_taban(kod, adi, current_price, onceki_kapanis, state):
    """
    Bugünkü fiyatı dünkü kapanışla karşılaştırır.
    Tavan/Taban durumu değiştiyse bildirim gönderir.
    """
    if not onceki_kapanis or onceki_kapanis <= 0:
        return state

    tavan = round(onceki_kapanis * TAVAN_CARPANI, 2)
    taban = round(onceki_kapanis * TABAN_CARPANI, 2)

    # Mevcut durum
    if current_price >= tavan * TAVAN_ESIGI:
        new_state = "tavan"
    elif current_price <= taban * TABAN_ESIGI:
        new_state = "taban"
    else:
        new_state = "normal"

    prev_state = state.get(f"tt_{kod}", "normal")

    if new_state == prev_state:
        return state

    # ─── Durum değişikliği bildirimleri ───
    if new_state == "tavan" and prev_state != "tavan":
        if prev_state == "taban":
            send_fcm("📈 Taban Bozdu!", f"{adi} tabandan çıktı! ₺{taban} → ₺{current_price}", {"type": "taban_bozdu", "ticker": kod})
        send_fcm("🚀 Tavan Yaptı!", f"{adi} tavan yaptı! ₺{tavan} | ₺{current_price}", {"type": "tavan_yapti", "ticker": kod})

    elif prev_state == "tavan" and new_state != "tavan":
        send_fcm("⚠️ Tavan Bozdu!", f"{adi} tavan bozdu! ₺{tavan} → ₺{current_price}", {"type": "tavan_bozdu", "ticker": kod})
        if new_state == "taban":
            send_fcm("📉 Taban Yaptı!", f"{adi} tabana indi! ₺{taban} | ₺{current_price}", {"type": "taban_yapti", "ticker": kod})

    elif new_state == "taban" and prev_state != "taban":
        send_fcm("📉 Taban Yaptı!", f"{adi} tabana indi! ₺{taban} | ₺{current_price}", {"type": "taban_yapti", "ticker": kod})

    elif prev_state == "taban" and new_state == "normal":
        send_fcm("📈 Taban Bozdu!", f"{adi} tabandan çıktı! ₺{taban} → ₺{current_price}", {"type": "taban_bozdu", "ticker": kod})

    state[f"tt_{kod}"] = new_state
    return state


# ═══════════════════════════════════════════════════════════════════
# ANA FONKSİYON
# ═══════════════════════════════════════════════════════════════════
def main():
    now_tr = datetime.now(TR_TZ)
    print("=" * 60)
    print(f"  Canlı Fiyat Takibi — {now_tr.strftime('%Y-%m-%d %H:%M')} TR")
    print("=" * 60)

    # Borsa açık mı kontrol et
    if not borsa_acik_mi():
        return

    # 1. Firestore'dan işlem gören hisseleri çek
    print("\n[1/3] İşlem gören hisseler Firestore'dan çekiliyor...")
    hisseler = get_islem_hisseleri()
    if not hisseler:
        print("  İşlem gören hisse bulunamadı.")
        return
    print(f"  {len(hisseler)} işlem gören hisse bulundu.")

    # 2. Yahoo Finance'ten fiyat çek
    print("\n[2/3] Yahoo Finance'ten fiyatlar çekiliyor...")
    kodlar = [h["_doc_id"] for h in hisseler]
    fiyatlar = fetch_live_prices(kodlar)
    if not fiyatlar:
        print("  Fiyat alınamadı.")
        return
    print(f"  {len(fiyatlar)} fiyat alındı.")

    # 3. RTDB'ye yaz + Tavan/Taban kontrolü
    print("\n[3/3] RTDB'ye yazılıyor ve tavan/taban kontrol ediliyor...")
    rtdb_write_prices(fiyatlar)

    # State'i oku (tavan/taban durumları)
    state = fs_get(STATE_DOC_PATH) or {}

    for hisse in hisseler:
        kod = hisse["_doc_id"]
        adi = hisse.get("sirket_adi", kod)
        fiyat = fiyatlar.get(kod)
        if not fiyat:
            continue

        # Dünkü kapanış fiyatını Firestore fiyat_gecmisi'nden al
        fiyat_gecmisi = hisse.get("fiyat_gecmisi", {})
        if not isinstance(fiyat_gecmisi, dict): fiyat_gecmisi = {}

        # Bugünden önceki en son kayıtlı fiyatı bul (= dünkü kapanış)
        bugun_str = now_tr.strftime("%Y-%m-%d")
        gecmis_tarihleri = sorted([t for t in fiyat_gecmisi.keys() if t < bugun_str], reverse=True)
        onceki_kapanis = fiyat_gecmisi.get(gecmis_tarihleri[0]) if gecmis_tarihleri else None

        if onceki_kapanis:
            try:
                onceki_kapanis = float(onceki_kapanis)
            except (ValueError, TypeError):
                onceki_kapanis = None

        if onceki_kapanis:
            state = check_tavan_taban(kod, adi, fiyat, onceki_kapanis, state)
            print(f"  {kod}: ₺{fiyat} (dünkü: ₺{onceki_kapanis})")
        else:
            print(f"  {kod}: ₺{fiyat} (dünkü fiyat yok, tavan/taban kontrolü atlandı)")

        # Bugünkü fiyatı fiyat_gecmisi'ne ekle (grafik için)
        fiyat_gecmisi[bugun_str] = fiyat
        fs_set(f"{FIRESTORE_COLLECTION}/{kod}", {"fiyat_gecmisi": fiyat_gecmisi}, merge=True)

    # State'i kaydet
    fs_set(STATE_DOC_PATH, state, merge=False)

    print("\n" + "=" * 60)
    print(f"  {len(fiyatlar)} fiyat güncellendi.")
    print("=" * 60)


if __name__ == "__main__":
    main()
