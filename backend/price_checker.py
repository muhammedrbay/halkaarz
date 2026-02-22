#!/usr/bin/env python3
"""
Fiyat Takibi, Realtime DB Güncellemesi ve Bildirim Sistemi
Yahoo Finance → Firebase Realtime Database (REST) + FCM v1 bildirimleri
GitHub Actions üzerinde 15 dakikada bir çalışır.
"""

import json
import os
from datetime import datetime, timedelta
from typing import Optional

import requests
import yfinance as yf
from google.oauth2 import service_account
from google.auth.transport.requests import Request

# --- Yapılandırma ---
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
IPOS_FILE = os.path.join(DATA_DIR, "ipos.json")
STATE_FILE = os.path.join(DATA_DIR, "notification_state.json")

# Firebase
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_SA_KEY_JSON = os.environ.get("FIREBASE_SA_KEY_JSON", "")  # Service Account JSON string
FIREBASE_RTDB_URL = os.environ.get("FIREBASE_RTDB_URL", "")        # https://proje-default-rtdb.firebaseio.com

FCM_V1_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

# BIST limitleri
TAVAN_CARPANI = 1.10
TABAN_CARPANI = 0.90
TAVAN_ESIGI = 0.999   # %0.1 tolerans (tavan "yakını" sayılır)
TABAN_ESIGI = 1.001   # %0.1 tolerans


# ─── Firebase Auth ────────────────────────────────────────────────────────────

def get_fcm_access_token() -> Optional[str]:
    """Firebase Service Account ile OAuth2 access token alır (FCM için)."""
    if not FIREBASE_SA_KEY_JSON:
        print("[UYARI] FIREBASE_SA_KEY_JSON ayarlanmadı.")
        return None
    try:
        sa_info = json.loads(FIREBASE_SA_KEY_JSON)
        credentials = service_account.Credentials.from_service_account_info(
            sa_info,
            scopes=["https://www.googleapis.com/auth/firebase.messaging"],
        )
        credentials.refresh(Request())
        return credentials.token
    except Exception as e:
        print(f"[HATA] FCM access token alınamadı: {e}")
        return None


def get_rtdb_access_token() -> Optional[str]:
    """Firebase Realtime Database yazmak için OAuth2 token alır."""
    if not FIREBASE_SA_KEY_JSON:
        print("[UYARI] FIREBASE_SA_KEY_JSON ayarlanmadı.")
        return None
    try:
        sa_info = json.loads(FIREBASE_SA_KEY_JSON)
        credentials = service_account.Credentials.from_service_account_info(
            sa_info,
            scopes=["https://www.googleapis.com/auth/firebase.database",
                    "https://www.googleapis.com/auth/userinfo.email"],
        )
        credentials.refresh(Request())
        return credentials.token
    except Exception as e:
        print(f"[HATA] RTDB access token alınamadı: {e}")
        return None


# ─── FCM Bildirimleri ─────────────────────────────────────────────────────────

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


# ─── Firebase Realtime Database ───────────────────────────────────────────────

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
        resp = requests.patch(  # PATCH: mevcut verileri silmeden günceller
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


# ─── Fiyat Çekme ─────────────────────────────────────────────────────────────

def get_stock_data(ticker: str) -> Optional[dict]:
    """Yahoo Finance'den hisse verisi çeker."""
    try:
        bist_ticker = f"{ticker}.IS"
        stock = yf.Ticker(bist_ticker)
        hist = stock.history(period="2d")

        if hist.empty or len(hist) < 1:
            print(f"[UYARI] {bist_ticker} için veri bulunamadı.")
            return None

        current_price = float(hist["Close"].iloc[-1])
        previous_close = float(hist["Close"].iloc[-2]) if len(hist) >= 2 else current_price
        today_high = float(hist["High"].iloc[-1])
        today_low = float(hist["Low"].iloc[-1])

        return {
            "ticker": ticker,
            "current_price": round(current_price, 2),
            "previous_close": round(previous_close, 2),
            "today_high": round(today_high, 2),
            "today_low": round(today_low, 2),
        }
    except Exception as e:
        print(f"[HATA] {ticker} verisi: {e}")
        return None


# ─── Durum Makinesi (State Machine) Bildirim Sistemi ──────────────────────────
#
# Her hissenin durumu: "normal", "tavan", "taban"
# Bildirim sadece durum DEĞİŞTİĞİNDE gider:
#   normal → tavan  = "Tavan Yaptı!"
#   tavan  → normal = "Tavan Bozdu!"
#   normal → taban  = "Taban Yaptı!"
#   taban  → normal = "Taban Bozdu!"
#   tavan  → taban  = "Tavan Bozdu!" + "Taban Yaptı!" (iki bildirim)
#   taban  → tavan  = "Taban Bozdu!" + "Tavan Yaptı!" (iki bildirim)
#
# Aynı durumda kalınca (örn. tavan → tavan) bildirim GİTMEZ.

def _today() -> str:
    return datetime.now().strftime("%Y-%m-%d")


def get_stock_state(stock_data: dict) -> str:
    """
    Hissenin mevcut durumunu belirler.
    Dönüş: "tavan", "taban", veya "normal"
    """
    prev = stock_data["previous_close"]
    current = stock_data["current_price"]

    tavan = round(prev * TAVAN_CARPANI, 2)
    taban = round(prev * TABAN_CARPANI, 2)

    if current >= tavan * TAVAN_ESIGI:
        return "tavan"
    elif current <= taban * TABAN_ESIGI:
        return "taban"
    else:
        return "normal"


def get_previous_state(ticker: str, state: dict) -> str:
    """State dosyasından hissenin son bilinen durumunu oku."""
    return state.get(f"stock_state_{ticker}", "normal")


def set_stock_state(ticker: str, new_state: str, state: dict):
    """Hissenin durumunu state'e yaz."""
    state[f"stock_state_{ticker}"] = new_state
    state[f"stock_state_ts_{ticker}"] = datetime.now().isoformat()


def check_sure_bitiyor(ipo: dict, state: dict) -> bool:
    """Talep toplama bitimine 30 dakika kala bildirim."""
    talep_bitis = ipo.get("talep_bitis", "")
    if not talep_bitis:
        return False
    try:
        bitis = datetime.fromisoformat(talep_bitis.replace("Z", ""))
        kalan = bitis - datetime.now()
        if timedelta(minutes=0) < kalan <= timedelta(minutes=30):
            key = f"sure_bitiyor_{ipo['sirket_kodu']}_{bitis.strftime('%Y-%m-%d')}"
            if key not in state:
                return True
    except (ValueError, TypeError):
        pass
    return False


def check_yeni_arz(ipo: dict, state: dict) -> bool:
    key = f"yeni_arz_{ipo['sirket_kodu']}"
    return key not in state


# ─── Ana İşlem Bloğu ──────────────────────────────────────────────────────────

def process_islem_gorenler(ipos: list[dict], state: dict) -> tuple[dict, dict[str, float]]:
    """
    İşlem gören hisselerin fiyatlarını kontrol eder.
    Durum makinesi ile bildirim gönderir — sadece durum değişince.
    Dönüş: (güncel state, {ticker: fiyat} dict)
    """
    islem_gorenler = [i for i in ipos if i.get("durum") == "islem_goruyor"]
    prices: dict[str, float] = {}

    for ipo in islem_gorenler:
        ticker = ipo["sirket_kodu"]
        adi = ipo.get("sirket_adi", ticker)

        print(f"[KONTROL] {adi} ({ticker})...")
        sd = get_stock_data(ticker)
        if not sd:
            continue

        prices[ticker] = sd["current_price"]

        tavan = round(sd["previous_close"] * TAVAN_CARPANI, 2)
        taban = round(sd["previous_close"] * TABAN_CARPANI, 2)

        print(
            f"  ₺{sd['current_price']} | Tavan: ₺{tavan} | Taban: ₺{taban} "
            f"| Yük: ₺{sd['today_high']} | Düş: ₺{sd['today_low']}"
        )

        # Mevcut ve önceki durumu belirle
        current_state = get_stock_state(sd)
        previous_state = get_previous_state(ticker, state)

        print(f"  Durum: {previous_state} → {current_state}")

        # Durum değişmediyse bildirim gönderme
        if current_state == previous_state:
            continue

        # ─── Durum Geçişleri ─────────────────────────────

        # normal/taban → tavan = "Tavan Yaptı!"
        if current_state == "tavan" and previous_state != "tavan":
            # Eğer tabandan geliyorsa önce "Taban Bozdu" gönder
            if previous_state == "taban":
                send_fcm_notification(
                    title="📈 Taban Bozdu!",
                    body=f"{adi} tabandan çıktı! Taban: ₺{taban} → Anlık: ₺{sd['current_price']}",
                    data={"type": "taban_bozdu", "ticker": ticker},
                )
            send_fcm_notification(
                title="🚀 Tavan Yaptı!",
                body=f"{adi} tavan yaptı! Tavan: ₺{tavan} | Anlık: ₺{sd['current_price']}",
                data={"type": "tavan_yapti", "ticker": ticker},
            )

        # tavan → normal/taban = "Tavan Bozdu!"
        elif previous_state == "tavan" and current_state != "tavan":
            send_fcm_notification(
                title="⚠️ Tavan Bozdu!",
                body=f"{adi} tavan bozdu! Tavan: ₺{tavan} → Anlık: ₺{sd['current_price']}",
                data={"type": "tavan_bozdu", "ticker": ticker},
            )
            # Eğer doğrudan tabana düştüyse "Taban Yaptı" da gönder
            if current_state == "taban":
                send_fcm_notification(
                    title="📉 Taban Yaptı!",
                    body=f"{adi} tabana indi! Taban: ₺{taban} | Anlık: ₺{sd['current_price']}",
                    data={"type": "taban_yapti", "ticker": ticker},
                )

        # normal/tavan → taban = "Taban Yaptı!"
        elif current_state == "taban" and previous_state != "taban":
            send_fcm_notification(
                title="📉 Taban Yaptı!",
                body=f"{adi} tabana indi! Taban: ₺{taban} | Anlık: ₺{sd['current_price']}",
                data={"type": "taban_yapti", "ticker": ticker},
            )

        # taban → normal = "Taban Bozdu!"
        elif previous_state == "taban" and current_state == "normal":
            send_fcm_notification(
                title="📈 Taban Bozdu!",
                body=f"{adi} tabandan çıktı! Taban: ₺{taban} → Anlık: ₺{sd['current_price']}",
                data={"type": "taban_bozdu", "ticker": ticker},
            )

        # Durumu güncelle
        set_stock_state(ticker, current_state, state)

    return state, prices


def process_talep_toplayanlar(ipos: list[dict], state: dict) -> dict:
    """Talep toplayan arzların süresini kontrol eder."""
    for ipo in ipos:
        if ipo.get("durum") != "talep_topluyor":
            continue
        adi = ipo.get("sirket_adi", ipo["sirket_kodu"])
        if check_sure_bitiyor(ipo, state):
            send_fcm_notification(
                title="⏰ Son 30 Dakika!",
                body=f"{adi} halka arzı birazdan kapanıyor! Acele edin.",
                data={"type": "sure_bitiyor", "ticker": ipo["sirket_kodu"]},
            )
            bitis = datetime.fromisoformat(ipo["talep_bitis"].replace("Z", ""))
            state[f"sure_bitiyor_{ipo['sirket_kodu']}_{bitis.strftime('%Y-%m-%d')}"] = datetime.now().isoformat()
    return state


def process_yeni_arzlar(ipos: list[dict], state: dict) -> dict:
    """Yeni eklenen halka arzlar için bildirim gönderir."""
    for ipo in ipos:
        if check_yeni_arz(ipo, state):
            adi = ipo.get("sirket_adi", ipo["sirket_kodu"])
            fiyat = ipo.get("arz_fiyati", 0)
            katilim = " ✅ Katılım" if ipo.get("katilim_endeksine_uygun") else ""
            send_fcm_notification(
                title="🆕 Yeni Halka Arz!",
                body=f"{adi} — ₺{fiyat}{katilim}",
                data={"type": "yeni_arz", "ticker": ipo["sirket_kodu"]},
            )
            state[f"yeni_arz_{ipo['sirket_kodu']}"] = datetime.now().isoformat()
    return state


def cleanup_old_states(state: dict) -> dict:
    """7 günden eski bildirim kayıtlarını temizler."""
    cutoff = datetime.now() - timedelta(days=7)
    return {
        k: v for k, v in state.items()
        if _safe_ts(v) > cutoff
    }


def _safe_ts(ts_str: str) -> datetime:
    try:
        return datetime.fromisoformat(ts_str)
    except (ValueError, TypeError):
        return datetime.now()


# ─── State IO ─────────────────────────────────────────────────────────────────

def load_ipos() -> list[dict]:
    if not os.path.exists(IPOS_FILE):
        print("[HATA] IPO veri dosyası bulunamadı.")
        return []
    with open(IPOS_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def load_state() -> dict:
    if not os.path.exists(STATE_FILE):
        return {}
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def save_state(state: dict):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print(f"Fiyat Takip & Bildirim — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    ipos = load_ipos()
    if not ipos:
        print("[BİLGİ] İşlenecek IPO yok.")
        return

    state = load_state()
    print(f"[BİLGİ] {len(ipos)} IPO | {len(state)} bildirim kaydı")

    # 1. Yeni arzlar bildirimi
    state = process_yeni_arzlar(ipos, state)

    # 2. İşlem gören hisseler: fiyat çek + tavan/taban kontrol + RTDB yaz
    state, prices = process_islem_gorenler(ipos, state)
    print(f"\n[RTDB] {len(prices)} fiyat yazılıyor...")
    write_prices_to_rtdb(prices)

    # 3. Süre bitiyor bildirimi
    state = process_talep_toplayanlar(ipos, state)

    # 4. Temizlik + kaydet
    state = cleanup_old_states(state)
    save_state(state)

    print("=" * 60)
    print(f"[BİLGİ] Tamamlandı. {len(prices)} fiyat RTDB'ye yazıldı.")


if __name__ == "__main__":
    main()
