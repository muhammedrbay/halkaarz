#!/usr/bin/env python3
"""
Fiyat Takibi ve Bildirim Sistemi
yfinance ile BIST hisselerini kontrol eder ve FCM v1 API üzerinden bildirim gönderir.
GitHub Actions üzerinde 15 dakikada bir çalışır.
"""

import json
import os
import sys
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

# Firebase Cloud Messaging v1 API
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_SA_KEY_JSON = os.environ.get("FIREBASE_SA_KEY_JSON", "")  # Service Account JSON string
FCM_V1_URL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

# BIST tavan/taban limitleri (varsayılan %10)
TAVAN_CARPANI = 1.10
TABAN_CARPANI = 0.90


def get_fcm_access_token() -> Optional[str]:
    """Firebase Service Account ile OAuth2 access token alır."""
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


def load_ipos() -> list[dict]:
    """IPO verilerini yükler."""
    if not os.path.exists(IPOS_FILE):
        print("[HATA] IPO veri dosyası bulunamadı.")
        return []
    with open(IPOS_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def load_notification_state() -> dict:
    """Bildirim durumunu yükler (tekrar gönderimi önlemek için)."""
    if not os.path.exists(STATE_FILE):
        return {}
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def save_notification_state(state: dict):
    """Bildirim durumunu kaydeder."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def send_fcm_notification(title: str, body: str, data: Optional[dict] = None) -> bool:
    """FCM v1 API ile bildirim gönderir (topic: halka_arz)."""
    if not FIREBASE_PROJECT_ID:
        print(f"[UYARI] FIREBASE_PROJECT_ID ayarlanmadı. Bildirim atlandı: {title}")
        return False

    access_token = get_fcm_access_token()
    if not access_token:
        print(f"[UYARI] Access token alınamadı. Bildirim atlandı: {title}")
        return False

    url = FCM_V1_URL.format(project_id=FIREBASE_PROJECT_ID)

    # FCM v1 payload
    message = {
        "message": {
            "topic": "halka_arz",
            "notification": {
                "title": title,
                "body": body,
            },
            "android": {
                "priority": "high",
                "notification": {
                    "sound": "default",
                    "channel_id": "halka_arz_channel",
                    "click_action": "FLUTTER_NOTIFICATION_CLICK",
                },
            },
            "apns": {
                "payload": {
                    "aps": {
                        "sound": "default",
                        "badge": 1,
                    }
                }
            },
            "data": {k: str(v) for k, v in (data or {}).items()},
        }
    }

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; UTF-8",
    }

    try:
        response = requests.post(url, json=message, headers=headers, timeout=10)
        if response.status_code == 200:
            print(f"[BİLDİRİM ✓] {title} — {body}")
            return True
        else:
            print(f"[HATA] FCM v1 ({response.status_code}): {response.text}")
            return False
    except requests.RequestException as e:
        print(f"[HATA] FCM isteği başarısız: {e}")
        return False


def get_stock_data(ticker: str) -> Optional[dict]:
    """Yahoo Finance'den hisse verisi çeker. BIST: SIRKET.IS"""
    try:
        bist_ticker = f"{ticker}.IS"
        stock = yf.Ticker(bist_ticker)
        hist = stock.history(period="2d")

        if hist.empty or len(hist) < 1:
            print(f"[UYARI] {bist_ticker} için veri bulunamadı.")
            return None

        current_price = hist["Close"].iloc[-1]
        previous_close = hist["Close"].iloc[-2] if len(hist) >= 2 else hist["Close"].iloc[-1]
        today_high = hist["High"].iloc[-1]
        today_low = hist["Low"].iloc[-1]

        return {
            "ticker": ticker,
            "current_price": round(float(current_price), 2),
            "previous_close": round(float(previous_close), 2),
            "today_high": round(float(today_high), 2),
            "today_low": round(float(today_low), 2),
        }
    except Exception as e:
        print(f"[HATA] {ticker} verisi çekilemedi: {e}")
        return None


def check_tavan_bozdu(stock_data: dict, state: dict) -> bool:
    """Gün içinde tavana ulaşıp sonra düştüyse → Tavan Bozdu."""
    ticker = stock_data["ticker"]
    prev_close = stock_data["previous_close"]
    current = stock_data["current_price"]
    today_high = stock_data["today_high"]

    tavan_fiyat = round(prev_close * TAVAN_CARPANI, 2)
    hit_tavan = today_high >= tavan_fiyat * 0.999
    currently_below = current < tavan_fiyat * 0.999

    if hit_tavan and currently_below:
        state_key = f"tavan_bozdu_{ticker}_{datetime.now().strftime('%Y-%m-%d')}"
        if state_key not in state:
            return True
    return False


def check_taban_yapti(stock_data: dict, state: dict) -> bool:
    """Fiyat tabana ulaştıysa → Taban Yaptı."""
    ticker = stock_data["ticker"]
    prev_close = stock_data["previous_close"]
    current = stock_data["current_price"]

    taban_fiyat = round(prev_close * TABAN_CARPANI, 2)
    if current <= taban_fiyat * 1.001:
        state_key = f"taban_yapti_{ticker}_{datetime.now().strftime('%Y-%m-%d')}"
        if state_key not in state:
            return True
    return False


def check_sure_bitiyor(ipo: dict, state: dict) -> bool:
    """Talep toplama bitimine 30 dakika kala bildirim."""
    talep_bitis = ipo.get("talep_bitis", "")
    if not talep_bitis:
        return False

    try:
        bitis_zamani = datetime.fromisoformat(talep_bitis.replace("Z", ""))
        kalan = bitis_zamani - datetime.now()

        if timedelta(minutes=0) < kalan <= timedelta(minutes=30):
            state_key = f"sure_bitiyor_{ipo['sirket_kodu']}_{bitis_zamani.strftime('%Y-%m-%d')}"
            if state_key not in state:
                return True
    except (ValueError, TypeError):
        pass
    return False


def check_yeni_halka_arz(ipo: dict, state: dict) -> bool:
    """Yeni halka arz eklendiyse bildirim gönder."""
    code = ipo["sirket_kodu"]
    state_key = f"yeni_arz_{code}"
    if state_key not in state:
        return True
    return False


def process_islem_gorenler(ipos: list[dict], state: dict) -> dict:
    """İşlem gören halka arzların fiyatlarını kontrol eder."""
    islem_gorenler = [i for i in ipos if i.get("durum") == "islem_goruyor"]

    for ipo in islem_gorenler:
        ticker = ipo["sirket_kodu"]
        sirket_adi = ipo.get("sirket_adi", ticker)

        print(f"[KONTROL] {sirket_adi} ({ticker})...")
        stock_data = get_stock_data(ticker)
        if not stock_data:
            continue

        print(
            f"  Fiyat: {stock_data['current_price']} TL | "
            f"Önceki Kpn: {stock_data['previous_close']} TL | "
            f"Yüksek: {stock_data['today_high']} TL"
        )

        # Tavan Bozdu
        if check_tavan_bozdu(stock_data, state):
            tavan = round(stock_data["previous_close"] * TAVAN_CARPANI, 2)
            send_fcm_notification(
                title="⚠️ Tavan Bozdu!",
                body=f"{sirket_adi} tavan bozdu! Tavan: {tavan}₺ → Anlık: {stock_data['current_price']}₺",
                data={"type": "tavan_bozdu", "ticker": ticker},
            )
            state[f"tavan_bozdu_{ticker}_{datetime.now().strftime('%Y-%m-%d')}"] = datetime.now().isoformat()

        # Taban Yaptı
        if check_taban_yapti(stock_data, state):
            taban = round(stock_data["previous_close"] * TABAN_CARPANI, 2)
            send_fcm_notification(
                title="🔴 Taban Yaptı!",
                body=f"{sirket_adi} taban yaptı! Taban: {taban}₺ → Anlık: {stock_data['current_price']}₺",
                data={"type": "taban_yapti", "ticker": ticker},
            )
            state[f"taban_yapti_{ticker}_{datetime.now().strftime('%Y-%m-%d')}"] = datetime.now().isoformat()

    return state


def process_talep_toplayanlar(ipos: list[dict], state: dict) -> dict:
    """Talep toplayan arzların süresini kontrol eder."""
    for ipo in ipos:
        if ipo.get("durum") != "talep_topluyor":
            continue

        sirket_adi = ipo.get("sirket_adi", ipo["sirket_kodu"])

        if check_sure_bitiyor(ipo, state):
            send_fcm_notification(
                title="⏰ Son 30 Dakika!",
                body=f"{sirket_adi} halka arzı birazdan kapanıyor! Acele edin.",
                data={"type": "sure_bitiyor", "ticker": ipo["sirket_kodu"]},
            )
            bitis = ipo.get("talep_bitis", "")
            bitis_dt = datetime.fromisoformat(bitis.replace("Z", ""))
            state[f"sure_bitiyor_{ipo['sirket_kodu']}_{bitis_dt.strftime('%Y-%m-%d')}"] = datetime.now().isoformat()

    return state


def process_yeni_arzlar(ipos: list[dict], state: dict) -> dict:
    """Yeni eklenen halka arzlar için bildirim gönderir."""
    for ipo in ipos:
        if check_yeni_halka_arz(ipo, state):
            sirket_adi = ipo.get("sirket_adi", ipo["sirket_kodu"])
            fiyat = ipo.get("arz_fiyati", 0)
            katilim = "✅ Katılım Endeksine Uygun" if ipo.get("katilim_endeksine_uygun") else ""

            send_fcm_notification(
                title="🆕 Yeni Halka Arz!",
                body=f"{sirket_adi} — Arz Fiyatı: {fiyat}₺ {katilim}".strip(),
                data={"type": "yeni_arz", "ticker": ipo["sirket_kodu"]},
            )
            state[f"yeni_arz_{ipo['sirket_kodu']}"] = datetime.now().isoformat()

    return state


def cleanup_old_states(state: dict) -> dict:
    """7 günden eski bildirim kayıtlarını temizler."""
    cutoff = datetime.now() - timedelta(days=7)
    cleaned = {}
    for key, timestamp in state.items():
        try:
            ts = datetime.fromisoformat(timestamp)
            if ts > cutoff:
                cleaned[key] = timestamp
        except (ValueError, TypeError):
            cleaned[key] = timestamp  # Geçersiz format, koru
    return cleaned


def main():
    """Ana çalıştırma fonksiyonu."""
    print("=" * 60)
    print(f"Fiyat Takip & Bildirim — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    ipos = load_ipos()
    if not ipos:
        print("[BİLGİ] İşlenecek IPO yok.")
        return

    state = load_notification_state()
    print(f"[BİLGİ] {len(ipos)} IPO yüklendi. {len(state)} bildirim kaydı.")

    # 1. Yeni arzlar
    state = process_yeni_arzlar(ipos, state)

    # 2. İşlem gören hisseler — tavan/taban kontrolü
    state = process_islem_gorenler(ipos, state)

    # 3. Talep toplayan — süre bitiyor
    state = process_talep_toplayanlar(ipos, state)

    # 4. Eski kayıtları temizle
    state = cleanup_old_states(state)

    # 5. Kaydet
    save_notification_state(state)
    print("=" * 60)
    print("[BİLGİ] Tamamlandı.")


if __name__ == "__main__":
    main()
