#!/usr/bin/env python3
"""
Halka Arz Veri Çekme ve Güncelleme Motoru
- Ana kaynak: halkarz.com ana sayfası (İlk Halka Arzlar listesi)
- Tarih ve durum badge'lerine göre: Taslak / Talep / İşlem otomatik ayrıştırılır
- Yahoo Finance: İşlem görenlerin sparkline grafiklerini çeker
- FCM: Yeni arz tespit edilince bildirim gönderir
- Günde 1 kez çalışır (GitHub Actions - Sabah 10:00 TR)
"""

import json
import os
import re
import time
from datetime import datetime, timedelta
from typing import Optional

import requests
import yfinance as yf
from bs4 import BeautifulSoup

# --- Yapılandırma ---
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
OUTPUT_FILE = os.path.join(DATA_DIR, "ipos.json")
MANUAL_FILE = os.path.join(DATA_DIR, "manual_ipos.json")
STATE_FILE  = os.path.join(DATA_DIR, "notification_state.json")
REQUEST_DELAY = 3

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
}

FIREBASE_PROJECT_ID  = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_SA_KEY_JSON = os.environ.get("FIREBASE_SA_KEY_JSON", "")

# Türkçe ay adları
MONTHS_TR = {
    "ocak": 1, "şubat": 2, "mart": 3, "nisan": 4, "mayıs": 5,
    "haziran": 6, "temmuz": 7, "ağustos": 8, "eylül": 9,
    "ekim": 10, "kasım": 11, "aralık": 12,
}


# ─── FCM BİLDİRİMLER ──────────────────────────────────────────────

def get_fcm_access_token() -> Optional[str]:
    """Firebase Service Account ile OAuth2 access token alır."""
    if not FIREBASE_SA_KEY_JSON:
        return None
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import Request

        sa_info = json.loads(FIREBASE_SA_KEY_JSON)
        credentials = service_account.Credentials.from_service_account_info(
            sa_info,
            scopes=["https://www.googleapis.com/auth/firebase.messaging"],
        )
        credentials.refresh(Request())
        return credentials.token
    except Exception as e:
        print(f"[HATA] FCM token alınamadı: {e}")
        return None


def send_notification(title: str, body: str, data: Optional[dict] = None) -> bool:
    """FCM v1 API ile bildirim gönderir."""
    if not FIREBASE_PROJECT_ID:
        print(f"[BİLDİRİM SİMÜLE] {title} — {body}")
        return False

    token = get_fcm_access_token()
    if not token:
        return False

    url = f"https://fcm.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/messages:send"
    payload = {
        "message": {
            "topic": "halka_arz",
            "notification": {"title": title, "body": body},
            "android": {
                "priority": "high",
                "notification": {"sound": "default", "channel_id": "halka_arz_channel"},
            },
            "apns": {"payload": {"aps": {"sound": "default"}}},
            "data": {k: str(v) for k, v in (data or {}).items()},
        }
    }

    try:
        resp = requests.post(
            url, json=payload,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            timeout=10,
        )
        if resp.status_code == 200:
            print(f"[BİLDİRİM ✓] {title}")
            return True
        print(f"[HATA] FCM ({resp.status_code}): {resp.text}")
    except Exception as e:
        print(f"[HATA] FCM: {e}")
    return False


# ─── HTTP ─────────────────────────────────────────────────────────

def safe_request(url: str, timeout: int = 15) -> Optional[requests.Response]:
    """Rate-limited HTTP GET."""
    try:
        time.sleep(REQUEST_DELAY)
        response = requests.get(url, headers=HEADERS, timeout=timeout)
        response.raise_for_status()
        return response
    except requests.RequestException as e:
        print(f"[HATA] İstek: {url} → {e}")
        return None


# ─── TARİH YARDIMCISI ─────────────────────────────────────────────

def _parse_halkarz_date(tarih_str: str) -> Optional[datetime]:
    """
    halkarz.com tarih stringini parse eder.
    Örnekler:
      '2-3-4 Mart 2026'           → son gün (Borsaya giriş) = 4 Mart 2026
      '26-27 Şubat, 2 Mart 2026' → son gün = 2 Mart 2026
      'Hazırlanıyor...'           → None
    """
    if not tarih_str or "hazırlanıyor" in tarih_str.lower():
        return None
    try:
        # Birden fazla tarih aralığı virgülle ayrılmış olabilir → son parçayı al
        parts = re.split(r",\s*", tarih_str.strip())
        last_part = parts[-1].strip()
        # "2-3-4 Mart 2026" tokenize et
        tokens = last_part.split()
        if len(tokens) >= 2:
            yil    = int(tokens[-1])
            ay_str = tokens[-2].lower().rstrip(",")
            ay     = MONTHS_TR.get(ay_str)
            if ay:
                # "2-3-4" → son gün = 4
                gun = int(tokens[0].split("-")[-1])
                return datetime(yil, ay, gun)
    except Exception:
        pass
    return None


# ─── ANA KAYNAK: HALKARZ.COM ──────────────────────────────────────

def parse_halkarz_com() -> list[dict]:
    """
    halkarz.com ana sayfasındaki "İlk Halka Arzlar" ve "Taslak Arzlar"
    listelerindeki tüm şirketleri çeker ve durum belirleme yapar:

    Durum Tespiti:
      - div.il-tt  (Talep toplanıyor)  → talep_topluyor
      - div.il-gonk (Gong! - bugün/dün borsaya girdi) → islem_goruyor
      - Tarihi geçmiş ama badge yok    → islem_goruyor
      - Tarihi gelmemiş                → taslak
      - Tarih yok                      → taslak
    """
    results = []
    print("[BİLGİ] halkarz.com ana sayfası taranıyor...")
    resp = safe_request("https://halkarz.com")
    if not resp:
        return results

    soup = BeautifulSoup(resp.text, "html.parser")
    now  = datetime.now()

    all_lists = soup.find_all("ul", class_="halka-arz-list")
    for ul in all_lists:
        for li in ul.find_all("li", recursive=False):
            article = li.find("article")
            if not article:
                continue

            # ── Şirket adı ve BIST kodu ──────────────────────────
            h3 = article.find("h3", class_="il-halka-arz-sirket")
            if not h3:
                continue
            sirket_adi = h3.get_text(strip=True)

            bist_span = article.find("span", class_="il-bist-kod")
            sirket_kodu = bist_span.get_text(strip=True).upper() if bist_span else ""
            if not sirket_kodu:
                # Geçici benzersiz anahtar
                import hashlib
                sirket_kodu = "TAS_" + hashlib.md5(sirket_adi.encode()).hexdigest()[:4].upper()

            # ── Tarih ────────────────────────────────────────────
            tarih_span = article.find("span", class_="il-halka-arz-tarihi")
            tarih_str  = tarih_span.get_text(strip=True) if tarih_span else ""
            borsaya_giris = _parse_halkarz_date(tarih_str)

            # ── Durum Tespiti (badge öncelikli) ──────────────────
            badge = article.find("div", class_="il-badge")
            badge_text = badge.get_text(strip=True).lower() if badge else ""

            if "talep toplaniyor" in badge_text or "talep toplanıyor" in badge_text or article.find("div", class_="il-tt"):
                durum = "talep_topluyor"
            elif "gong" in badge_text or article.find("div", class_="il-gonk"):
                durum = "islem_goruyor"
            elif borsaya_giris and borsaya_giris.date() <= now.date():
                # Tarihi bugün veya geçmişte → borsaya girmiş/işlem görüyor
                durum = "islem_goruyor"
            elif borsaya_giris and borsaya_giris.date() > now.date():
                # Tarihi gelecekte → taslak (yakında talep) 
                # Eğer talep başlangıcı yaklaştıysa "taslak_onaylandi" da denilebilir
                # ama tek durum olarak taslak tutuyoruz; uygulama tarih gösterir
                durum = "taslak"
            else:
                # Tarih yok → taslak
                durum = "taslak"

            results.append({
                "sirket_kodu": sirket_kodu,
                "sirket_adi":  sirket_adi,
                "durum":       durum,
                "borsada_islem_tarihi": borsaya_giris.isoformat() if borsaya_giris else "",
                "kaynak": "halkarz.com",
            })

    print(f"[BİLGİ] halkarz.com → {len(results)} şirket tespit edildi.")
    return results


# ─── YARDIMCI DOSYA OPERASYONLARİ ────────────────────────────────

def load_existing_data() -> list[dict]:
    if not os.path.exists(OUTPUT_FILE):
        return []
    try:
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[HATA] Mevcut veri okunamadı: {e}")
        return []


def load_manual_data() -> list[dict]:
    if not os.path.exists(MANUAL_FILE):
        return []
    try:
        with open(MANUAL_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[HATA] Manuel veri okunamadı: {e}")
        return []


def load_notification_state() -> dict:
    if not os.path.exists(STATE_FILE):
        return {}
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def save_notification_state(state: dict):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def save_data(ipos: list[dict]):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(ipos, f, ensure_ascii=False, indent=2)
    print(f"[BİLGİ] {len(ipos)} IPO kaydedildi → {OUTPUT_FILE}")


# ─── BİRLEŞTİRME ─────────────────────────────────────────────────

def merge_ipo_data(existing: list[dict], new_data: list[dict]) -> list[dict]:
    """
    Mevcut ve yeni verileri birleştirir.
    Öncelik: Mevcut veri korunur, yeni veriden sadece eksik alanlar eklenir.
    Özel durum: Eğer yeni veri 'islem_goruyor' diyorsa mutlaka güncelle.
    """
    merged = {item["sirket_kodu"]: item for item in existing}

    for item in new_data:
        code = item["sirket_kodu"]
        if code in merged:
            existing_item = merged[code]
            # Durum güncelleme
            new_durum = item.get("durum", "")
            old_durum = existing_item.get("durum", "")

            # İşlem görmeye başladıysa veya yeni borsa tarihi geldiyse güncelle
            if new_durum == "islem_goruyor" or (new_durum and new_durum != old_durum):
                existing_item["durum"] = new_durum

            # Borsa tarihi yoksa veya geldi ise güncelle
            if item.get("borsada_islem_tarihi") and not existing_item.get("borsada_islem_tarihi"):
                existing_item["borsada_islem_tarihi"] = item["borsada_islem_tarihi"]

            existing_item["guncelleme_zamani"] = datetime.now().isoformat()
            merged[code] = existing_item
        else:
            # Yeni şirket — temel yapı oluştur
            item.setdefault("arz_fiyati", 0)
            item.setdefault("toplam_lot", 0)
            item.setdefault("dagitim_sekli", "Eşit")
            item.setdefault("konsorsiyum_lideri", "")
            item.setdefault("iskonto_orani", 0.0)
            item.setdefault("fon_kullanim_yeri", {"yatirim": 0, "borc_odeme": 0, "isletme_sermayesi": 0})
            item.setdefault("katilim_endeksine_uygun", False)
            item.setdefault("talep_baslangic", "")
            item.setdefault("talep_bitis", "")
            item.setdefault("son_katilimci_sayilari", [])
            item.setdefault("sparkline", [])
            item.setdefault("sparkline_dates", [])
            item["guncelleme_zamani"] = datetime.now().isoformat()
            merged[code] = item

    return list(merged.values())


# ─── SPARKLINE (YAHOO FINANCE) ────────────────────────────────────

def fetch_historical_sparklines(ipos: list[dict]) -> list[dict]:
    """Yahoo Finance'den işlem gören hisselerin fiyat geçmişini çeker."""
    for ipo in ipos:
        if ipo.get("durum") != "islem_goruyor":
            continue

        try:
            ticker = f"{ipo['sirket_kodu']}.IS"
            hist = yf.Ticker(ticker).history(period="1y", interval="1d")

            if hist.empty:
                continue

            closes = hist["Close"].dropna().tolist()
            dates  = [d.strftime("%Y-%m-%d") for d in hist.index]
            if not closes:
                continue

            ipo["ilk_gun_kapanis"] = float(closes[0])
            ipo["max_fiyat"]       = float(max(closes))
            ipo["min_fiyat"]       = float(min(closes))

            # Tavan gün sayısı
            tavan_count = 0
            arz_fiyati  = float(ipo.get("arz_fiyati", 0))
            if arz_fiyati > 0 and (closes[0] - arz_fiyati) / arz_fiyati >= 0.095:
                tavan_count += 1
            for i in range(1, len(closes)):
                if closes[i-1] > 0 and (closes[i] - closes[i-1]) / closes[i-1] >= 0.095:
                    tavan_count += 1
            ipo["tavan_gun"] = tavan_count

            # Son 6 ayda çıkanların tüm grafiği, eskiler için son 30 gün
            include_full = False
            islem_str = ipo.get("borsada_islem_tarihi", "")
            if islem_str:
                try:
                    islem_date = datetime.fromisoformat(islem_str.replace("Z", ""))
                    if datetime.now() - islem_date <= timedelta(days=180):
                        include_full = True
                except Exception:
                    pass

            if include_full:
                ipo["sparkline"]       = [float(x) for x in closes]
                ipo["sparkline_dates"] = dates
            else:
                ipo["sparkline"]       = [float(x) for x in closes[-30:]] if len(closes) > 30 else [float(x) for x in closes]
                ipo["sparkline_dates"] = dates[-30:] if len(dates) > 30 else dates

            ipo["static_fetched"]    = True
            ipo["static_fetched_at"] = datetime.now().isoformat()

            print(f"[YAHOO] {ticker} → {tavan_count} tavan, fiyat {closes[-1]:.2f}")
        except Exception as e:
            print(f"[HATA] Yahoo Finance {ipo['sirket_kodu']}: {e}")

    return ipos


# ─── BİLDİRİM ────────────────────────────────────────────────────

def notify_new_ipos(existing_codes: set, all_ipos: list[dict], state: dict) -> dict:
    """Yeni eklenen IPO'lar için bildirim gönderir."""
    for ipo in all_ipos:
        code      = ipo["sirket_kodu"]
        state_key = f"yeni_arz_{code}"
        if code not in existing_codes and state_key not in state:
            send_notification(
                title="🆕 Yeni Halka Arz!",
                body=f"{ipo.get('sirket_adi', code)} halka arza hazırlanıyor.",
                data={"type": "yeni_arz", "ticker": code},
            )
            state[state_key] = datetime.now().isoformat()
    return state


# ─── ANA FONKSİYON ───────────────────────────────────────────────

def main():
    print("=" * 60)
    print(f"Halka Arz Veri Motoru — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    # 1. Mevcut veriyi yükle
    existing_data  = load_existing_data()
    existing_codes = {item["sirket_kodu"] for item in existing_data}
    print(f"[BİLGİ] Mevcut: {len(existing_data)} IPO")

    # 2. halkarz.com'dan tüm listeyi çek (ana kaynak)
    halkarz_data = parse_halkarz_com()

    # 3. Manuel veriler
    manual_data = load_manual_data()
    print(f"[BİLGİ] Manuel: {len(manual_data)} kayıt")

    # 4. Birleştir
    merged = merge_ipo_data(existing_data, halkarz_data + manual_data)

    # 5. Yahoo Finance'den grafik verileri
    print("[BİLGİ] Grafik verileri güncelleniyor (YFinance)...")
    merged = fetch_historical_sparklines(merged)

    # 6. Bildirimler
    state = load_notification_state()
    state = notify_new_ipos(existing_codes, merged, state)
    save_notification_state(state)

    # 7. Kaydet
    save_data(merged)

    print("=" * 60)
    print("[BİLGİ] İşlem tamamlandı.")


if __name__ == "__main__":
    main()
