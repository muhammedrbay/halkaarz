#!/usr/bin/env python3
"""
Halka Arz Veri Çekme Motoru (Hibrit Akıllı Kazıma)
- Ana Tetikleyici: KAP / SPK API
- İlk Çalışma (Geçmiş): halkaarz.net üzerinden son 6 ay kazınır.
- Nokta Atışı Kazıma: Sadece KAP'ta görülen ve fiyatı eksik olan yeni IPO'lar kazınır.
- Anti-Ban: Gerçekçi User-Agent ve time.sleep gecikmeleri.
"""

import json
import os
import time
import random
from datetime import datetime, timedelta
from typing import Optional

import requests
import yfinance as yf
from bs4 import BeautifulSoup

# --- Yüzey ve Dosya Konumları ---
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
OUTPUT_FILE = os.path.join(DATA_DIR, "ipos.json")
MANUAL_FILE = os.path.join(DATA_DIR, "manual_ipos.json")
STATE_FILE = os.path.join(DATA_DIR, "notification_state.json")

# Varsayılan/Gerçekçi Başlıklar (Anti-Ban)
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
}

FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_SA_KEY_JSON = os.environ.get("FIREBASE_SA_KEY_JSON", "")


# ─── FCM BİLDİRİMLERİ ────────────────────────────────────────────
def get_fcm_access_token() -> Optional[str]:
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
            "android": {"priority": "high"},
            "data": {k: str(v) for k, v in (data or {}).items()},
        }
    }
    try:
        resp = requests.post(url, json=payload, headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, timeout=10)
        if resp.status_code == 200:
            print(f"[BİLDİRİM ✓] {title}")
            return True
        print(f"[HATA] FCM ({resp.status_code}): {resp.text}")
    except Exception as e:
        print(f"[HATA] FCM Gönderim: {e}")
    return False


# ─── YARDIMCI FONKSİYONLAR ─────────────────────────────────────
def safe_sleep():
    """Anti-Ban için 2-4 saniye arası rastgele bekleme."""
    time.sleep(random.uniform(2.0, 4.0))

def safe_request(url: str, timeout: int = 15) -> Optional[requests.Response]:
    """Saygılı HTTP GET."""
    try:
        safe_sleep()
        response = requests.get(url, headers=HEADERS, timeout=timeout)
        response.raise_for_status()
        return response
    except requests.RequestException as e:
        print(f"[HATA] İstek Başarısız: {url} → {e}")
        return None


# ─── 1. ANA TETİKLEYİCİ (KAP) ────────────────────────────────────
def parse_kap_halka_arz() -> list[dict]:
    """KAP API'den son 30 gün içinde açılmış Halka Arz duyurularını bulur."""
    results = []
    url = "https://www.kap.org.tr/tr/api/memberDisclosureQuery"
    payload = {
        "fromDate": (datetime.now() - timedelta(days=30)).strftime("%Y-%m-%d"),
        "toDate": datetime.now().strftime("%Y-%m-%d"),
        "subject": "halka arz",
    }
    try:
        resp = requests.post(url, json=payload, headers=HEADERS, timeout=15)
        if resp.status_code == 200:
            data = resp.json()
            if isinstance(data, list):
                for item in data:
                    try:
                        code = item.get("stockCodes", "").split(",")[0].strip()
                        if code:
                            results.append({
                                "sirket_kodu": code,
                                "sirket_adi": item.get("companyName", code),
                                "kaynak": "kap",
                            })
                    except Exception:
                        continue
            print(f"[BİLGİ] KAP'tan {len(results)} şirket tespit edildi.")
    except Exception as e:
        print(f"[HATA] KAP Çekilemedi: {e}")
    
    # Sadece benzersiz şirketleri döndür
    unique = {}
    for r in results:
        unique[r["sirket_kodu"]] = r
    return list(unique.values())


# ─── 2. İLK ÇALIŞMA (GEÇMİŞİ TOPLAMA) ────────────────────────────
def scrape_full_history() -> list[dict]:
    """ipos.json boşsa çalışır, 6 aylık veriyi halkaarz sitelerinden çeker."""
    print("[BİLGİ] İlk Çalışma Tespiti! Geçmiş 6 ay kazınıyor...")
    history = []
    url = "https://halkaarz.net/halka-arz-olan-sirketler/"
    resp = safe_request(url)
    if not resp:
        return history
    
    soup = BeautifulSoup(resp.text, 'html.parser')
    # Basit bir deneme (Bu bölüm site HTML'sine göre ayarlıdır, değişebilir)
    for a in soup.select('h3 a')[:15]:
        href = a.get('href', '')
        text = a.text.strip().upper()
        # Kod bulmaya çalış
        if '(' in text and ')' in text:
            code = text.split('(')[1].split(')')[0].strip()
            history.append({
                "sirket_kodu": code,
                "sirket_adi": text.split('(')[0].strip(),
                "kaynak": "halkaarz.net",
            })
    print(f"[BİLGİ] Geçmiş Toplama: {len(history)} kayıt bulundu.")
    return history


# ─── 3. NOKTA ATIŞI KAZIMA ───────────────────────────────────────
def scrape_single_ipo(sirket_kodu: str) -> dict:
    """Belirli bir hissenin sayfasına nokta atışı gider ve arz bilgilerini alır."""
    print(f"[KAZIMA] Nokta Atışı Başladı: {sirket_kodu}")
    # Siteye göre tahmini URL: https://halkaarz.net/{sirket_kodu}-halka-arz/
    url = f"https://halkaarz.net/{sirket_kodu.lower()}-halka-arz/"
    resp = safe_request(url)
    
    scraped_data = {"arz_fiyati": 0.0, "toplam_lot": 0, "kisi_basi_lot": 0}
    
    if not resp or resp.status_code != 200:
        print(f"[UYARI] {sirket_kodu} için nokta atışı sayfa bulunamadı ({url}).")
        return scraped_data
        
    soup = BeautifulSoup(resp.text, 'html.parser')
    
    # Basit HTML parsing (Site tasarımına göre uyarlandı)
    text_content = soup.get_text().upper()
    try:
        # Fiyat bulma analizi (Örn: "Halka Arz Fiyatı: 35,50 TL")
        import re
        fiyat_match = re.search(r"FİYATI\s*[:\-]\s*(\d+[,.]\d+|\d+)\s*(TL|₺)", text_content)
        if fiyat_match:
            fiyat_str = fiyat_match.group(1).replace(',', '.')
            scraped_data["arz_fiyati"] = float(fiyat_str)
            
        lot_match = re.search(r"TOPLAM LOT\s*[:\-]\s*([\d.,]+)\s*(LOT|MİLYON|BİN)?", text_content)
        if lot_match:
            lot_str = lot_match.group(1).replace('.', '').replace(',', '')
            if lot_str.isdigit():
                scraped_data["toplam_lot"] = int(lot_str)
                
    except Exception as e:
        print(f"[HATA] {sirket_kodu} kazıma hatası: {e}")
        
    print(f"[KAZIMA BAŞARILI] {sirket_kodu} -> Fiyat: {scraped_data['arz_fiyati']}, Lot: {scraped_data['toplam_lot']}")
    return scraped_data


# ─── YARDIMCI VE BİRLEŞTİRME YÖNTEMLERİ ──────────────────────────
def load_json(filepath: str) -> list[dict]:
    if not os.path.exists(filepath):
        return []
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return []

def safe_merge_ipo(item: dict, details: dict) -> dict:
    """Temel özelliklerle yeni çekilen detayları birleştirir."""
    base = {
        "sirket_kodu": item.get("sirket_kodu", "").upper(),
        "sirket_adi": item.get("sirket_adi", ""),
        "arz_fiyati": details.get("arz_fiyati", item.get("arz_fiyati", 0.0)),
        "toplam_lot": details.get("toplam_lot", item.get("toplam_lot", 0)),
        "dagitim_sekli": item.get("dagitim_sekli", "Eşit"),
        "iskonto_orani": item.get("iskonto_orani", 0.0),
        "katilim_endeksine_uygun": item.get("katilim_endeksine_uygun", False),
        "durum": item.get("durum", "taslak"),
        "son_katilimci_sayilari": item.get("son_katilimci_sayilari", []),
        "sparkline": item.get("sparkline", []),
        "sparkline_dates": item.get("sparkline_dates", []),
        "guncelleme_zamani": datetime.now().isoformat()
    }
    return base


def update_missing_details(ipos: dict):
    """Fiyatı 0 olan veya yeni eklenenleri bulup nokta atışı kazır."""
    for code, ipo in ipos.items():
        # Fiyatı yoksa ve durum henüz geçmişte değilse
        if ipo.get("arz_fiyati", 0) <= 0:
            details = scrape_single_ipo(code)
            if details["arz_fiyati"] > 0:
                ipo["arz_fiyati"] = details["arz_fiyati"]
            if details["toplam_lot"] > 0:
                ipo["toplam_lot"] = details["toplam_lot"]
            ipos[code] = ipo


def fetch_historical_sparklines(ipos: list[dict]) -> list[dict]:
    """Yahoo Finance'den grafik (sparkline) verisini güvenli çeker."""
    for ipo in ipos:
        if ipo.get("durum", "") != "islem_goruyor":
            continue
        try:
            ticker = f"{ipo['sirket_kodu']}.IS"
            hist = yf.Ticker(ticker).history(period="1y", interval="1d")
            if hist.empty:
                continue
                
            closes = hist["Close"].dropna().tolist()
            dates = [d.strftime("%Y-%m-%d") for d in hist.index]
            if not closes:
                continue
            
            ipo["ilk_gun_kapanis"] = float(closes[0])
            ipo["max_fiyat"] = float(max(closes))
            ipo["min_fiyat"] = float(min(closes))
            
            # Tavan hesaplama
            tavan = 0
            arz_fiyat = float(ipo.get("arz_fiyati", 0))
            if arz_fiyat > 0 and (closes[0] - arz_fiyat)/arz_fiyat >= 0.095:
                tavan += 1
            for i in range(1, len(closes)):
                if closes[i-1] > 0 and (closes[i] - closes[i-1])/closes[i-1] >= 0.095:
                    tavan += 1
            ipo["tavan_gun"] = tavan
            
            is_recent = False
            islem_str = ipo.get("borsada_islem_tarihi", "")
            if islem_str:
                try:
                    islem = datetime.fromisoformat(islem_str.replace("Z", ""))
                    if datetime.now() - islem <= timedelta(days=180):
                        is_recent = True
                except:
                    pass
            
            if is_recent:
                ipo["sparkline"] = [float(x) for x in closes]
                ipo["sparkline_dates"] = dates
            else:
                l = min(len(closes), 30)
                ipo["sparkline"] = [float(x) for x in closes[-l:]]
                ipo["sparkline_dates"] = dates[-l:]
                
            ipo["static_fetched"] = True
            ipo["static_fetched_at"] = datetime.now().isoformat()
        except:
            pass
    return ipos


# ─── ANA MOTOR ───────────────────────────────────────────────────
def main():
    print("=" * 60)
    print(f"Akıllı Kazıma Motoru — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    # 1. Mevcut JSON verisini yükle
    existing_data = load_json(OUTPUT_FILE)
    ipos_dict = {item["sirket_kodu"]: item for item in existing_data}
    print(f"[BİLGİ] Mevcut Veri: {len(ipos_dict)} şirket")

    # 2. Eğer hiç veri yoksa, 6 aylık geçmişi kazı
    if not ipos_dict:
        history = scrape_full_history()
        for item in history:
            ipos_dict[item["sirket_kodu"]] = safe_merge_ipo(item, {})

    # 3. KAP'tan anlık veri tespiti
    kap_items = parse_kap_halka_arz()
    for item in kap_items:
        code = item["sirket_kodu"]
        if code not in ipos_dict:
            print(f"[YENİ ARZ TESPİTİ] {code}")
            ipos_dict[code] = safe_merge_ipo(item, {})
            # Yeni arz bulunduğunda bildirim at:
            send_notification(
                title="🆕 Yeni Halka Arz Tespit Edildi!",
                body=f"{code} koduyla halka arza hazırlanıyor.",
                data={"type": "yeni_arz", "ticker": code}
            )

    # 4. Nokta Atışı Eksik Veri Tamamlama
    update_missing_details(ipos_dict)

    # 5. Grafik ve Borsa Fiyatı (YFinance)
    updated_list = fetch_historical_sparklines(list(ipos_dict.values()))

    # 6. Kayıt
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(updated_list, f, ensure_ascii=False, indent=2)
    print(f"[BİLGİ] Kazıma tamamlandı, {len(updated_list)} IPO kaydedildi.")

if __name__ == "__main__":
    main()
