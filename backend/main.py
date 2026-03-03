#!/usr/bin/env python3
"""
Halka Arz Takip Botu — CollectAPI + Firestore + FCM + RTDB
=============================================================
GitHub Actions üzerinde günde 1 kez (saat 20:00 TR) çalışır.

Veri Kaynakları:
  - CollectAPI /economy/halkaArz → Halka arz listesi
  - CollectAPI /economy/hisseSenedi → Borsa fiyatları

Veritabanı:
  - Firestore "halka_arzlar" koleksiyonu → IPO bilgileri + fiyat geçmişi
  - Firestore "meta/notification_state" → Bildirim durum takibi
  - Firebase Realtime Database /prices → Canlı fiyatlar (mevcut mantık)

Bildirimler:
  - FCM v1 API → Yeni arz, tavan/taban, süre bitiyor bildirimleri
"""

import json
import os
from datetime import datetime, timedelta
from typing import Optional

import requests
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

# Türkçe ay adları (CollectAPI tarih parse etmek için)
MONTHS_TR = {
    "ocak": 1, "şubat": 2, "mart": 3, "nisan": 4, "mayıs": 5,
    "haziran": 6, "temmuz": 7, "ağustos": 8, "eylül": 9,
    "ekim": 10, "kasım": 11, "aralık": 12,
}


# ═══════════════════════════════════════════════════════════════════════════════
# FIREBASE AUTH — Ortak token alma (FCM, RTDB, Firestore)
# ═══════════════════════════════════════════════════════════════════════════════

def _get_credentials(scopes: list[str]):
    """Firebase Service Account ile belirtilen scope'lar için credentials alır."""
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
# COLLECTAPI — Veri Çekme
# ═══════════════════════════════════════════════════════════════════════════════

def _collect_headers() -> dict:
    return {
        "Authorization": f"apikey {COLLECT_API_KEY}",
        "Content-Type": "application/json",
    }


def fetch_halka_arz_listesi() -> list[dict]:
    """CollectAPI /economy/halkaArz endpoint'inden halka arz listesini çeker."""
    if not COLLECT_API_KEY:
        print("[HATA] COLLECT_API_KEY ayarlanmadı.")
        return []
    try:
        resp = requests.get(
            f"{COLLECT_BASE}/halkaArz",
            headers=_collect_headers(),
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()
        if data.get("success"):
            result = data.get("result", [])
            print(f"[COLLECT] halkaArz → {len(result)} kayıt alındı.")
            return result
        print(f"[HATA] CollectAPI halkaArz başarısız: {data}")
        return []
    except Exception as e:
        print(f"[HATA] CollectAPI halkaArz: {e}")
        return []


def fetch_hisse_fiyatlari() -> dict[str, dict]:
    """
    CollectAPI /economy/hisseSenedi endpoint'inden BIST fiyatlarını çeker.
    Dönüş: {hisse_kodu: {"son_fiyat": float, "onceki_kapanis": float, ...}}
    """
    if not COLLECT_API_KEY:
        print("[HATA] COLLECT_API_KEY ayarlanmadı.")
        return {}
    try:
        resp = requests.get(
            f"{COLLECT_BASE}/hisseSenedi",
            headers=_collect_headers(),
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()
        if not data.get("success"):
            print(f"[HATA] CollectAPI hisseSenedi başarısız: {data}")
            return {}

        results = data.get("result", [])
        fiyat_map = {}
        for item in results:
            kod = (item.get("code") or item.get("kod") or "").replace(".IS", "").strip().upper()
            if not kod:
                continue
            try:
                son_fiyat = float(str(item.get("lastprice", item.get("son_fiyat", "0"))).replace(",", "."))
                onceki = float(str(item.get("previousClose", item.get("onceki_kapanis", "0"))).replace(",", "."))
                fiyat_map[kod] = {
                    "son_fiyat": son_fiyat,
                    "onceki_kapanis": onceki if onceki > 0 else son_fiyat,
                    "en_yuksek": float(str(item.get("high", item.get("en_yuksek", "0"))).replace(",", ".")),
                    "en_dusuk": float(str(item.get("low", item.get("en_dusuk", "0"))).replace(",", ".")),
                }
            except (ValueError, TypeError):
                continue

        print(f"[COLLECT] hisseSenedi → {len(fiyat_map)} hisse fiyatı alındı.")
        return fiyat_map
    except Exception as e:
        print(f"[HATA] CollectAPI hisseSenedi: {e}")
        return {}


# ═══════════════════════════════════════════════════════════════════════════════
# TARİH PARSE + KATEGORİZASYON
# ═══════════════════════════════════════════════════════════════════════════════

def _parse_tarih(tarih_str: str) -> Optional[datetime]:
    """
    CollectAPI'den gelen tarih string'lerini parse eder.
    Olası formatlar:
      - '2026-03-15' (ISO)
      - '15.03.2026' (TR)
      - '15 Mart 2026' (TR metin)
      - '10-11-12 Mart 2026' (aralıklı)
    """
    if not tarih_str or tarih_str.strip() in ("", "-", "Belirsiz", "belirsiz"):
        return None

    tarih_str = tarih_str.strip()

    # ISO format: 2026-03-15
    try:
        return datetime.strptime(tarih_str, "%Y-%m-%d")
    except ValueError:
        pass

    # TR format: 15.03.2026
    try:
        return datetime.strptime(tarih_str, "%d.%m.%Y")
    except ValueError:
        pass

    # TR metin: "15 Mart 2026" veya "10-11-12 Mart 2026"
    try:
        parts = tarih_str.replace(",", " ").split()
        if len(parts) >= 3:
            yil = int(parts[-1])
            ay_str = parts[-2].lower()
            ay = MONTHS_TR.get(ay_str)
            if ay:
                gun_str = parts[0]
                gun = int(gun_str.split("-")[-1])  # "10-11-12" → 12
                return datetime(yil, ay, gun)
    except Exception:
        pass

    return None


def kategorize_et(item: dict, bugun: datetime) -> Optional[str]:
    """
    API'den gelen bir halka arz kaydını kategorize eder.
    Dönüş: "talep" | "arz" | "islem_goruyor" | None (yok say)

    Kurallar:
      - Tarih bilgisi yoksa → None (tamamen yok say)
      - Talep başlangıcı gelecekte → "talep"
      - Bugün, talep toplama tarihleri arasındaysa → "arz"
      - Talep toplama tarihi geçmişse → "islem_goruyor"
    """
    # CollectAPI'den gelen alan adları değişkenlik gösterebilir
    tarih_str = (
        item.get("date") or
        item.get("tarih") or
        item.get("halkaArzTarihi") or
        item.get("borsaIslemTarihi") or
        ""
    )
    tarih = _parse_tarih(tarih_str)

    if tarih is None:
        return None  # Taslak: tarihi belli değil → YOK SAY

    tarih_date = tarih.date()
    bugun_date = bugun.date()

    if tarih_date > bugun_date:
        return "talep"          # Tarihi henüz gelmemiş
    elif tarih_date == bugun_date:
        return "arz"            # Bugün talep toplama tarihinde
    else:
        return "islem_goruyor"  # Tarihi geçmiş → borsada


def parse_ipo_item(item: dict) -> dict:
    """CollectAPI'den gelen bir halka arz kaydını standart formata dönüştürür."""
    # CollectAPI alan adlarını normalize et
    kod = (
        item.get("code") or
        item.get("kod") or
        item.get("hisseKodu") or
        item.get("sirketKodu") or
        ""
    ).strip().upper()

    ad = (
        item.get("title") or
        item.get("name") or
        item.get("sirketAdi") or
        item.get("ad") or
        ""
    ).strip()

    fiyat_str = str(item.get("price") or item.get("fiyat") or item.get("arzFiyati") or "0")
    try:
        fiyat = float(fiyat_str.replace(",", ".").replace("TL", "").strip())
    except (ValueError, TypeError):
        fiyat = 0.0

    tarih_str = (
        item.get("date") or
        item.get("tarih") or
        item.get("halkaArzTarihi") or
        item.get("borsaIslemTarihi") or
        ""
    )

    return {
        "sirket_kodu": kod,
        "sirket_adi": ad,
        "arz_fiyati": fiyat,
        "tarih_str": tarih_str,
        "ham_veri": item,  # Orijinal kaydı da sakla
    }


# ═══════════════════════════════════════════════════════════════════════════════
# FIRESTORE — Okuma / Yazma (REST API)
# ═══════════════════════════════════════════════════════════════════════════════

def _firestore_url(path: str) -> str:
    """Firestore REST API URL'i oluşturur."""
    return f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/{path}"


def _to_firestore_value(val):
    """Python değerini Firestore REST API formatına çevirir."""
    if val is None:
        return {"nullValue": None}
    if isinstance(val, bool):
        return {"booleanValue": val}
    if isinstance(val, int):
        return {"integerValue": str(val)}
    if isinstance(val, float):
        return {"doubleValue": val}
    if isinstance(val, str):
        return {"stringValue": val}
    if isinstance(val, list):
        return {"arrayValue": {"values": [_to_firestore_value(v) for v in val]}}
    if isinstance(val, dict):
        return {"mapValue": {"fields": {k: _to_firestore_value(v) for k, v in val.items()}}}
    return {"stringValue": str(val)}


def _from_firestore_value(fv: dict):
    """Firestore REST API değerini Python nesnesine çevirir."""
    if "stringValue" in fv:
        return fv["stringValue"]
    if "integerValue" in fv:
        return int(fv["integerValue"])
    if "doubleValue" in fv:
        return fv["doubleValue"]
    if "booleanValue" in fv:
        return fv["booleanValue"]
    if "nullValue" in fv:
        return None
    if "arrayValue" in fv:
        return [_from_firestore_value(v) for v in fv.get("arrayValue", {}).get("values", [])]
    if "mapValue" in fv:
        fields = fv.get("mapValue", {}).get("fields", {})
        return {k: _from_firestore_value(v) for k, v in fields.items()}
    return None


def firestore_get_doc(doc_path: str) -> Optional[dict]:
    """Firestore'dan tek bir doküman okur."""
    token = get_firestore_access_token()
    if not token:
        return None
    try:
        resp = requests.get(
            _firestore_url(doc_path),
            headers={"Authorization": f"Bearer {token}"},
            timeout=15,
        )
        if resp.status_code == 200:
            fields = resp.json().get("fields", {})
            return {k: _from_firestore_value(v) for k, v in fields.items()}
        elif resp.status_code == 404:
            return {}  # Doküman henüz yok
        print(f"[HATA] Firestore GET {doc_path} ({resp.status_code}): {resp.text[:200]}")
        return None
    except Exception as e:
        print(f"[HATA] Firestore GET {doc_path}: {e}")
        return None


def firestore_set_doc(doc_path: str, data: dict, merge: bool = False) -> bool:
    """
    Firestore'a doküman yazar.
    merge=False → Eski verinin ÜZERİNE YAZAR (overwrite).
    merge=True  → Sadece verilen alanları günceller.
    """
    token = get_firestore_access_token()
    if not token:
        return False

    fields = {k: _to_firestore_value(v) for k, v in data.items()}
    body = {"fields": fields}

    url = _firestore_url(doc_path)

    try:
        if merge:
            # PATCH ile belirtilen alanları güncelle
            field_paths = "&".join([f"updateMask.fieldPaths={k}" for k in data.keys()])
            resp = requests.patch(
                f"{url}?{field_paths}",
                json=body,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                },
                timeout=15,
            )
        else:
            # PATCH ile tüm dokümanı overwrite et (updateMask yok)
            resp = requests.patch(
                url,
                json=body,
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json",
                },
                timeout=15,
            )

        if resp.status_code == 200:
            return True
        print(f"[HATA] Firestore SET {doc_path} ({resp.status_code}): {resp.text[:200]}")
        return False
    except Exception as e:
        print(f"[HATA] Firestore SET {doc_path}: {e}")
        return False


def firestore_get_collection(collection: str) -> list[dict]:
    """Firestore'dan bir koleksiyondaki tüm dokümanları çeker."""
    token = get_firestore_access_token()
    if not token:
        return []
    try:
        docs = []
        url = _firestore_url(collection)
        page_token = None
        while True:
            params = {"pageSize": 100}
            if page_token:
                params["pageToken"] = page_token

            resp = requests.get(
                url,
                params=params,
                headers={"Authorization": f"Bearer {token}"},
                timeout=30,
            )
            if resp.status_code != 200:
                print(f"[HATA] Firestore LIST {collection} ({resp.status_code}): {resp.text[:200]}")
                break

            result = resp.json()
            for doc in result.get("documents", []):
                doc_id = doc["name"].split("/")[-1]
                fields = doc.get("fields", {})
                parsed = {k: _from_firestore_value(v) for k, v in fields.items()}
                parsed["_doc_id"] = doc_id
                docs.append(parsed)

            page_token = result.get("nextPageToken")
            if not page_token:
                break

        return docs
    except Exception as e:
        print(f"[HATA] Firestore LIST {collection}: {e}")
        return []


# ═══════════════════════════════════════════════════════════════════════════════
# FCM BİLDİRİMLER — Mevcut mantıkla birebir aynı
# ═══════════════════════════════════════════════════════════════════════════════

def send_fcm_notification(title: str, body: str, data: Optional[dict] = None) -> bool:
    """FCM v1 API ile bildirim gönderir (topic: halka_arz)."""
    if not FIREBASE_PROJECT_ID:
        print(f"[SİMÜLE] {title} — {body}")
        return False

    access_token = get_fcm_access_token()
    if not access_token:
        return False

    url = FCM_V1_URL.format(project_id=FIREBASE_PROJECT_ID)
    message = {
        "message": {
            "topic": "halka_arz",
            "notification": {"title": title, "body": body},
            "android": {
                "priority": "high",
                "notification": {
                    "sound": "default",
                    "channel_id": "halka_arz_channel",
                    "click_action": "FLUTTER_NOTIFICATION_CLICK",
                },
            },
            "apns": {"payload": {"aps": {"sound": "default", "badge": 1}}},
            "data": {k: str(v) for k, v in (data or {}).items()},
        }
    }

    try:
        resp = requests.post(
            url, json=message,
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json; UTF-8",
            },
            timeout=10,
        )
        if resp.status_code == 200:
            print(f"[BİLDİRİM ✓] {title} — {body}")
            return True
        print(f"[HATA] FCM v1 ({resp.status_code}): {resp.text[:200]}")
        return False
    except requests.RequestException as e:
        print(f"[HATA] FCM isteği: {e}")
        return False


# ═══════════════════════════════════════════════════════════════════════════════
# FIREBASE REALTIME DATABASE — Mevcut mantıkla birebir aynı
# ═══════════════════════════════════════════════════════════════════════════════

def write_prices_to_rtdb(prices: dict[str, float]) -> bool:
    """
    Fiyatları Firebase Realtime Database'e yazar.
    Tek endpoint: /prices.json
    Format: {"EMPAE": 72.4, "ATATR": 41.2, ...}
    """
    if not FIREBASE_RTDB_URL:
        print("[UYARI] FIREBASE_RTDB_URL ayarlanmadı, RTDB yazma atlandı.")
        return False

    if not prices:
        print("[BİLGİ] Yazılacak fiyat yok.")
        return False

    token = get_rtdb_access_token()
    if not token:
        return False

    url = f"{FIREBASE_RTDB_URL.rstrip('/')}/prices.json"
    try:
        resp = requests.patch(
            url,
            json=prices,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            timeout=15,
        )
        if resp.status_code == 200:
            print(f"[RTDB ✓] {len(prices)} fiyat yazıldı → {url}")
            return True
        print(f"[HATA] RTDB ({resp.status_code}): {resp.text[:200]}")
        return False
    except requests.RequestException as e:
        print(f"[HATA] RTDB yazma: {e}")
        return False


# ═══════════════════════════════════════════════════════════════════════════════
# BİLDİRİM STATE YÖNETİMİ — Firestore üzerinden
# ═══════════════════════════════════════════════════════════════════════════════

def load_notification_state() -> dict:
    """Firestore'dan bildirim durumunu okur."""
    doc = firestore_get_doc(STATE_DOC_PATH)
    if doc is None:
        print("[UYARI] Bildirim state okunamadı, boş dict kullanılıyor.")
        return {}
    return doc


def save_notification_state(state: dict) -> bool:
    """Bildirim durumunu Firestore'a kaydeder."""
    return firestore_set_doc(STATE_DOC_PATH, state, merge=False)


# ═══════════════════════════════════════════════════════════════════════════════
# DURUM MAKİNESİ (TAVAN / TABAN) — Mevcut mantıkla birebir aynı
# ═══════════════════════════════════════════════════════════════════════════════

def get_stock_state(current_price: float, previous_close: float) -> str:
    """
    Hissenin mevcut durumunu belirler.
    Dönüş: "tavan", "taban", veya "normal"
    """
    tavan = round(previous_close * TAVAN_CARPANI, 2)
    taban = round(previous_close * TABAN_CARPANI, 2)

    if current_price >= tavan * TAVAN_ESIGI:
        return "tavan"
    elif current_price <= taban * TABAN_ESIGI:
        return "taban"
    else:
        return "normal"


def process_tavan_taban(ticker: str, adi: str, current_price: float,
                        previous_close: float, state: dict) -> dict:
    """
    Tavan/taban durum geçişlerini kontrol eder ve gerekirse bildirim gönderir.
    Mevcut price_checker.py mantığıyla birebir aynı.
    """
    tavan = round(previous_close * TAVAN_CARPANI, 2)
    taban = round(previous_close * TABAN_CARPANI, 2)

    current_state = get_stock_state(current_price, previous_close)
    previous_state = state.get(f"stock_state_{ticker}", "normal")

    print(f"  ₺{current_price} | Tavan: ₺{tavan} | Taban: ₺{taban} | Durum: {previous_state} → {current_state}")

    # Durum değişmediyse bildirim gönderme
    if current_state == previous_state:
        return state

    # ─── Durum Geçişleri ─────────────────────────────

    # normal/taban → tavan = "Tavan Yaptı!"
    if current_state == "tavan" and previous_state != "tavan":
        if previous_state == "taban":
            send_fcm_notification(
                title="📈 Taban Bozdu!",
                body=f"{adi} tabandan çıktı! Taban: ₺{taban} → Anlık: ₺{current_price}",
                data={"type": "taban_bozdu", "ticker": ticker},
            )
        send_fcm_notification(
            title="🚀 Tavan Yaptı!",
            body=f"{adi} tavan yaptı! Tavan: ₺{tavan} | Anlık: ₺{current_price}",
            data={"type": "tavan_yapti", "ticker": ticker},
        )

    # tavan → normal/taban = "Tavan Bozdu!"
    elif previous_state == "tavan" and current_state != "tavan":
        send_fcm_notification(
            title="⚠️ Tavan Bozdu!",
            body=f"{adi} tavan bozdu! Tavan: ₺{tavan} → Anlık: ₺{current_price}",
            data={"type": "tavan_bozdu", "ticker": ticker},
        )
        if current_state == "taban":
            send_fcm_notification(
                title="📉 Taban Yaptı!",
                body=f"{adi} tabana indi! Taban: ₺{taban} | Anlık: ₺{current_price}",
                data={"type": "taban_yapti", "ticker": ticker},
            )

    # normal/tavan → taban = "Taban Yaptı!"
    elif current_state == "taban" and previous_state != "taban":
        send_fcm_notification(
            title="📉 Taban Yaptı!",
            body=f"{adi} tabana indi! Taban: ₺{taban} | Anlık: ₺{current_price}",
            data={"type": "taban_yapti", "ticker": ticker},
        )

    # taban → normal = "Taban Bozdu!"
    elif previous_state == "taban" and current_state == "normal":
        send_fcm_notification(
            title="📈 Taban Bozdu!",
            body=f"{adi} tabandan çıktı! Taban: ₺{taban} → Anlık: ₺{current_price}",
            data={"type": "taban_bozdu", "ticker": ticker},
        )

    # Durumu güncelle
    state[f"stock_state_{ticker}"] = current_state
    state[f"stock_state_ts_{ticker}"] = datetime.now().isoformat()

    return state


# ═══════════════════════════════════════════════════════════════════════════════
# HAFTA SONU KONTROLÜ
# ═══════════════════════════════════════════════════════════════════════════════

def is_weekend(dt: datetime) -> bool:
    """Cumartesi (5) veya Pazar (6) mı kontrol er."""
    return dt.weekday() in (5, 6)


# ═══════════════════════════════════════════════════════════════════════════════
# BİLDİRİM YARDIMCILARI
# ═══════════════════════════════════════════════════════════════════════════════

def check_yeni_arz(kod: str, state: dict) -> bool:
    """Bu hisse için daha önce yeni arz bildirimi gönderildi mi?"""
    key = f"yeni_arz_{kod}"
    return key not in state


def cleanup_old_states(state: dict) -> dict:
    """7 günden eski bildirim kayıtlarını temizler."""
    cutoff = datetime.now() - timedelta(days=7)
    cleaned = {}
    for k, v in state.items():
        try:
            ts = datetime.fromisoformat(str(v))
            if ts > cutoff:
                cleaned[k] = v
        except (ValueError, TypeError):
            # Timestamp değilse (örn. durum bilgisi), koru
            cleaned[k] = v
    return cleaned


# ═══════════════════════════════════════════════════════════════════════════════
# ANA FONKSİYON
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    bugun = datetime.now()
    print("=" * 60)
    print(f"Halka Arz Botu — {bugun.strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    # ─── 1. CollectAPI'den halka arz listesini çek ────────────────
    print("\n[1/5] CollectAPI halka arz listesi çekiliyor...")
    ham_liste = fetch_halka_arz_listesi()
    if not ham_liste:
        print("[BİLGİ] CollectAPI'den veri alınamadı. Çıkılıyor.")
        return

    # ─── 2. Bildirim state'ini Firestore'dan oku ──────────────────
    print("\n[2/5] Bildirim durumu Firestore'dan okunuyor...")
    state = load_notification_state()
    print(f"[BİLGİ] {len(state)} bildirim kaydı yüklendi.")

    # ─── 3. Kategorize et + Firestore'a yaz ───────────────────────
    print("\n[3/5] Halka arzlar kategorize ediliyor ve Firestore'a yazılıyor...")

    talep_count = 0
    arz_count = 0
    islem_count = 0
    atlanan_count = 0

    islem_gorenler = []  # Fiyat takibi için

    for raw_item in ham_liste:
        parsed = parse_ipo_item(raw_item)
        kod = parsed["sirket_kodu"]
        adi = parsed["sirket_adi"]

        if not kod:
            atlanan_count += 1
            continue

        kategori = kategorize_et(raw_item, bugun)

        if kategori is None:
            # Taslak: tarihi belli değil → TAMAMEN YOK SAY
            atlanan_count += 1
            print(f"  [ATLANDI] {adi} ({kod}) — tarih belli değil")
            continue

        doc_path = f"{FIRESTORE_COLLECTION}/{kod}"

        if kategori == "talep":
            # ─── TALEP: Overwrite (merge=False) ──────────────
            doc_data = {
                "sirket_kodu": kod,
                "sirket_adi": adi,
                "durum": "talep",
                "arz_fiyati": parsed["arz_fiyati"],
                "tarih": parsed["tarih_str"],
                "guncelleme_zamani": bugun.isoformat(),
            }
            if firestore_set_doc(doc_path, doc_data, merge=False):
                print(f"  [TALEP] {adi} ({kod}) → Firestore ✓")
            talep_count += 1

            # Yeni arz bildirimi
            if check_yeni_arz(kod, state):
                send_fcm_notification(
                    title="🆕 Yeni Halka Arz!",
                    body=f"{adi} — ₺{parsed['arz_fiyati']}",
                    data={"type": "yeni_arz", "ticker": kod},
                )
                state[f"yeni_arz_{kod}"] = bugun.isoformat()

        elif kategori == "arz":
            # ─── ARZ: Overwrite (merge=False) ────────────────
            doc_data = {
                "sirket_kodu": kod,
                "sirket_adi": adi,
                "durum": "arz",
                "arz_fiyati": parsed["arz_fiyati"],
                "tarih": parsed["tarih_str"],
                "guncelleme_zamani": bugun.isoformat(),
            }
            if firestore_set_doc(doc_path, doc_data, merge=False):
                print(f"  [ARZ] {adi} ({kod}) → Firestore ✓")
            arz_count += 1

            # Yeni arz bildirimi
            if check_yeni_arz(kod, state):
                send_fcm_notification(
                    title="🆕 Yeni Halka Arz!",
                    body=f"{adi} — ₺{parsed['arz_fiyati']}",
                    data={"type": "yeni_arz", "ticker": kod},
                )
                state[f"yeni_arz_{kod}"] = bugun.isoformat()

            # Durum değişikliği: talep → arz
            durum_key = f"durum_degisim_{kod}_arz"
            if durum_key not in state:
                send_fcm_notification(
                    title="📢 Talep Toplama Başladı!",
                    body=f"{adi} halka arzı şu an talep topluyor!",
                    data={"type": "talep_basladi", "ticker": kod},
                )
                state[durum_key] = bugun.isoformat()

        elif kategori == "islem_goruyor":
            # ─── İŞLEM GÖRÜYOR: Fiyat geçmişi korunacak ────
            islem_gorenler.append(parsed)
            islem_count += 1

    print(f"\n[ÖZET] Talep: {talep_count} | Arz: {arz_count} | İşlem: {islem_count} | Atlanan: {atlanan_count}")

    # ─── 4. İşlem gören hisseler: Fiyat çek + Firestore güncelle + Bildirim ──
    print("\n[4/5] İşlem gören hisseler için fiyat kontrolü...")

    rtdb_prices: dict[str, float] = {}

    if islem_gorenler and not is_weekend(bugun):
        fiyat_map = fetch_hisse_fiyatlari()

        for ipo in islem_gorenler:
            kod = ipo["sirket_kodu"]
            adi = ipo["sirket_adi"]

            print(f"\n[KONTROL] {adi} ({kod})...")

            # Fiyat bilgisini al
            fiyat_bilgi = fiyat_map.get(kod)
            if not fiyat_bilgi:
                print(f"  [UYARI] {kod} fiyat bulunamadı, sadece temel bilgi yazılacak.")
                # Fiyat yoksa bile temel bilgiyi yaz (merge ile)
                doc_data = {
                    "sirket_kodu": kod,
                    "sirket_adi": adi,
                    "durum": "islem_goruyor",
                    "arz_fiyati": ipo["arz_fiyati"],
                    "tarih": ipo["tarih_str"],
                    "guncelleme_zamani": bugun.isoformat(),
                }
                firestore_set_doc(f"{FIRESTORE_COLLECTION}/{kod}", doc_data, merge=True)
                continue

            son_fiyat = fiyat_bilgi["son_fiyat"]
            onceki_kapanis = fiyat_bilgi["onceki_kapanis"]

            # RTDB için fiyat ekle
            rtdb_prices[kod] = son_fiyat

            # Mevcut Firestore dokümanını oku (fiyat geçmişini korumak için)
            doc_path = f"{FIRESTORE_COLLECTION}/{kod}"
            mevcut_doc = firestore_get_doc(doc_path) or {}
            fiyat_gecmisi = mevcut_doc.get("fiyat_gecmisi", {})
            if not isinstance(fiyat_gecmisi, dict):
                fiyat_gecmisi = {}

            # Bugünün tarihiyle fiyat ekle
            bugun_str = bugun.strftime("%Y-%m-%d")
            fiyat_gecmisi[bugun_str] = son_fiyat

            # Firestore'a yaz (merge=True — eski veriyi, özellikle fiyat_gecmisi'ni koru)
            doc_data = {
                "sirket_kodu": kod,
                "sirket_adi": adi,
                "durum": "islem_goruyor",
                "arz_fiyati": ipo["arz_fiyati"],
                "tarih": ipo["tarih_str"],
                "son_fiyat": son_fiyat,
                "onceki_kapanis": onceki_kapanis,
                "fiyat_gecmisi": fiyat_gecmisi,
                "guncelleme_zamani": bugun.isoformat(),
            }
            firestore_set_doc(doc_path, doc_data, merge=True)
            print(f"  [FIRESTORE ✓] {kod} → ₺{son_fiyat} (geçmiş: {len(fiyat_gecmisi)} gün)")

            # Tavan/Taban durum makinesi
            state = process_tavan_taban(kod, adi, son_fiyat, onceki_kapanis, state)

    elif is_weekend(bugun):
        print("[BİLGİ] Hafta sonu — fiyat çekme ve fiyat_gecmisi güncellemesi atlandı.")
        # Hafta sonu sadece temel bilgileri güncelle
        for ipo in islem_gorenler:
            kod = ipo["sirket_kodu"]
            doc_data = {
                "sirket_kodu": kod,
                "sirket_adi": ipo["sirket_adi"],
                "durum": "islem_goruyor",
                "arz_fiyati": ipo["arz_fiyati"],
                "tarih": ipo["tarih_str"],
                "guncelleme_zamani": bugun.isoformat(),
            }
            firestore_set_doc(f"{FIRESTORE_COLLECTION}/{kod}", doc_data, merge=True)

    # ─── 5. RTDB fiyat yazma + State kaydet ───────────────────────
    print(f"\n[5/5] Tamamlanıyor...")

    # RTDB'ye canlı fiyatları yaz
    if rtdb_prices:
        print(f"[RTDB] {len(rtdb_prices)} fiyat yazılıyor...")
        write_prices_to_rtdb(rtdb_prices)

    # Eski bildirim kayıtlarını temizle
    state = cleanup_old_states(state)

    # Bildirim state'ini Firestore'a kaydet
    save_notification_state(state)

    print("\n" + "=" * 60)
    print(f"[BİLGİ] Tamamlandı! Talep:{talep_count} | Arz:{arz_count} | "
          f"İşlem:{islem_count} | RTDB:{len(rtdb_prices)} fiyat")
    print("=" * 60)


if __name__ == "__main__":
    main()
