#!/usr/bin/env python3
"""
Fiyat Takibi ve Bildirim Sistemi
yfinance ile BIST hisselerini kontrol eder ve FCM bildirim gönderir.
GitHub Actions üzerinde 15 dakikada bir çalışır.
"""

import json
import os
import sys
from datetime import datetime, timedelta
from typing import Optional

import requests
import yfinance as yf

# --- Yapılandırma ---
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
IPOS_FILE = os.path.join(DATA_DIR, "ipos.json")
STATE_FILE = os.path.join(DATA_DIR, "notification_state.json")

# Firebase Cloud Messaging
FCM_URL = "https://fcm.googleapis.com/fcm/send"
FCM_SERVER_KEY = os.environ.get("FCM_SERVER_KEY", "")

# BIST tavan/taban limitleri (varsayılan %10)
TAVAN_CARPANI = 1.10
TABAN_CARPANI = 0.90


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
    """Firebase Cloud Messaging ile bildirim gönderir."""
    if not FCM_SERVER_KEY:
        print(f"[UYARI] FCM_SERVER_KEY ayarlanmadı. Bildirim gönderilmedi: {title}")
        return False

    payload = {
        "to": "/topics/halka_arz",
        "notification": {
            "title": title,
            "body": body,
            "sound": "default",
            "click_action": "FLUTTER_NOTIFICATION_CLICK",
        },
        "data": data or {},
    }

    headers = {
        "Authorization": f"key={FCM_SERVER_KEY}",
        "Content-Type": "application/json",
    }

    try:
        response = requests.post(FCM_URL, json=payload, headers=headers, timeout=10)
        if response.status_code == 200:
            print(f"[BİLDİRİM] Gönderildi: {title} - {body}")
            return True
        else:
            print(f"[HATA] FCM hatası ({response.status_code}): {response.text}")
            return False
    except requests.RequestException as e:
        print(f"[HATA] FCM isteği başarısız: {e}")
        return False


def get_stock_data(ticker: str) -> Optional[dict]:
    """
    Yahoo Finance'den hisse verisi çeker.
    BIST hisseleri için ticker formatı: SIRKET.IS (örn: THYAO.IS)
    """
    try:
        bist_ticker = f"{ticker}.IS"
        stock = yf.Ticker(bist_ticker)

        # Son 2 günlük veri çek
        hist = stock.history(period="2d")
        if hist.empty or len(hist) < 1:
            print(f"[UYARI] {bist_ticker} için veri bulunamadı.")
            return None

        # Güncel ve dünkü kapanış
        current_price = hist["Close"].iloc[-1]
        previous_close = hist["Close"].iloc[-2] if len(hist) >= 2 else hist["Close"].iloc[-1]

        # Gün içi en yüksek fiyat (tavan kontrolü için)
        today_high = hist["High"].iloc[-1]

        return {
            "ticker": ticker,
            "current_price": round(float(current_price), 2),
            "previous_close": round(float(previous_close), 2),
            "today_high": round(float(today_high), 2),
        }
    except Exception as e:
        print(f"[HATA] {ticker} verisi çekilemedi: {e}")
        return None


def check_tavan_bozdu(stock_data: dict, state: dict) -> bool:
    """
    Tavan Bozdu kontrolü:
    Dünkü kapanış * 1.10 = Tavan fiyatı
    Gün içinde tavana ulaştıysa VE şu an tavanın altındaysa → Tavan Bozdu
    """
    ticker = stock_data["ticker"]
    prev_close = stock_data["previous_close"]
    current = stock_data["current_price"]
    today_high = stock_data["today_high"]

    tavan_fiyat = round(prev_close * TAVAN_CARPANI, 2)

    # Gün içinde tavan yapıp sonra düştü mü?
    hit_tavan = today_high >= tavan_fiyat * 0.999  # Küçük tolerans
    currently_below = current < tavan_fiyat * 0.999

    if hit_tavan and currently_below:
        state_key = f"tavan_bozdu_{ticker}_{datetime.now().strftime('%Y-%m-%d')}"
        if state_key not in state:
            return True
    return False


def check_taban_yapti(stock_data: dict, state: dict) -> bool:
    """
    Taban Yaptı kontrolü:
    Anlık fiyat <= Dünkü Kapanış * 0.90 ise → Taban Yaptı
    """
    ticker = stock_data["ticker"]
    prev_close = stock_data["previous_close"]
    current = stock_data["current_price"]

    taban_fiyat = round(prev_close * TABAN_CARPANI, 2)

    if current <= taban_fiyat * 1.001:  # Küçük tolerans
        state_key = f"taban_yapti_{ticker}_{datetime.now().strftime('%Y-%m-%d')}"
        if state_key not in state:
            return True
    return False


def check_sure_bitiyor(ipo: dict, state: dict) -> bool:
    """
    Süre Bitiyor kontrolü:
    Talep toplama bitimine 30 dakika kala bildirim gönder.
    """
    talep_bitis = ipo.get("talep_bitis", "")
    if not talep_bitis:
        return False

    try:
        bitis_zamani = datetime.fromisoformat(talep_bitis.replace("Z", ""))
        now = datetime.now()
        kalan = bitis_zamani - now

        # 30 dakika (1800 saniye) kala bildirim
        if timedelta(minutes=0) < kalan <= timedelta(minutes=30):
            state_key = f"sure_bitiyor_{ipo['sirket_kodu']}_{bitis_zamani.strftime('%Y-%m-%d')}"
            if state_key not in state:
                return True
    except (ValueError, TypeError):
        pass

    return False


def process_islem_gorenler(ipos: list[dict], state: dict) -> dict:
    """İşlem gören halka arzların fiyatlarını kontrol eder."""
    for ipo in ipos:
        if ipo.get("durum") != "islem_goruyor":
            continue

        ticker = ipo["sirket_kodu"]
        sirket_adi = ipo.get("sirket_adi", ticker)

        print(f"[KONTROL] {sirket_adi} ({ticker}) kontrol ediliyor...")
        stock_data = get_stock_data(ticker)
        if not stock_data:
            continue

        print(
            f"  Fiyat: {stock_data['current_price']} TL | "
            f"Dünkü Kapanış: {stock_data['previous_close']} TL | "
            f"Gün İçi Yüksek: {stock_data['today_high']} TL"
        )

        # Tavan Bozdu kontrolü
        if check_tavan_bozdu(stock_data, state):
            tavan = round(stock_data["previous_close"] * TAVAN_CARPANI, 2)
            send_fcm_notification(
                title="⚠️ Tavan Bozdu!",
                body=f"Dikkat! {sirket_adi} tavan bozdu! "
                     f"Tavan: {tavan} TL → Anlık: {stock_data['current_price']} TL",
                data={"type": "tavan_bozdu", "ticker": ticker},
            )
            state_key = f"tavan_bozdu_{ticker}_{datetime.now().strftime('%Y-%m-%d')}"
            state[state_key] = datetime.now().isoformat()

        # Taban Yaptı kontrolü
        if check_taban_yapti(stock_data, state):
            taban = round(stock_data["previous_close"] * TABAN_CARPANI, 2)
            send_fcm_notification(
                title="🔴 Taban Yaptı!",
                body=f"Uyarı! {sirket_adi} taban yaptı! "
                     f"Taban: {taban} TL → Anlık: {stock_data['current_price']} TL",
                data={"type": "taban_yapti", "ticker": ticker},
            )
            state_key = f"taban_yapti_{ticker}_{datetime.now().strftime('%Y-%m-%d')}"
            state[state_key] = datetime.now().isoformat()

    return state


def process_talep_toplayanlar(ipos: list[dict], state: dict) -> dict:
    """Talep toplayan halka arzların süresini kontrol eder."""
    for ipo in ipos:
        if ipo.get("durum") != "talep_topluyor":
            continue

        sirket_adi = ipo.get("sirket_adi", ipo["sirket_kodu"])

        # Süre Bitiyor kontrolü
        if check_sure_bitiyor(ipo, state):
            send_fcm_notification(
                title="⏰ Son 30 Dakika!",
                body=f"Son 30 Dakika! {sirket_adi} halka arzı birazdan kapanıyor.",
                data={"type": "sure_bitiyor", "ticker": ipo["sirket_kodu"]},
            )
            bitis = ipo.get("talep_bitis", "")
            bitis_dt = datetime.fromisoformat(bitis.replace("Z", ""))
            state_key = f"sure_bitiyor_{ipo['sirket_kodu']}_{bitis_dt.strftime('%Y-%m-%d')}"
            state[state_key] = datetime.now().isoformat()

    return state


def cleanup_old_states(state: dict) -> dict:
    """3 günden eski bildirim kayıtlarını temizler."""
    cutoff = datetime.now() - timedelta(days=3)
    cleaned = {}
    for key, timestamp in state.items():
        try:
            ts = datetime.fromisoformat(timestamp)
            if ts > cutoff:
                cleaned[key] = timestamp
        except (ValueError, TypeError):
            pass
    return cleaned


def main():
    """Ana çalıştırma fonksiyonu."""
    print("=" * 60)
    print(f"Fiyat Takip ve Bildirim Sistemi - {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    # 1. Verileri yükle
    ipos = load_ipos()
    if not ipos:
        print("[BİLGİ] İşlenecek IPO verisi yok.")
        return

    state = load_notification_state()
    print(f"[BİLGİ] {len(ipos)} adet IPO yüklendi. Bildirim durumu: {len(state)} kayıt.")

    # 2. İşlem gören hisseleri kontrol et
    state = process_islem_gorenler(ipos, state)

    # 3. Talep toplayan arzların süresini kontrol et
    state = process_talep_toplayanlar(ipos, state)

    # 4. Eski state kayıtlarını temizle
    state = cleanup_old_states(state)

    # 5. State kaydet
    save_notification_state(state)

    print("=" * 60)
    print("[BİLGİ] Kontrol tamamlandı.")


if __name__ == "__main__":
    main()
