#!/usr/bin/env python3
"""
Halka Arz Veri Çekme ve Güncelleme Motoru
KAP duyurularından ve resmi kaynaklardan halka arz verisi çeker.
Yeni halka arz bulunursa FCM bildirim gönderir.
Günde 2 kez çalışır (GitHub Actions).
"""

import json
import os
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
STATE_FILE = os.path.join(DATA_DIR, "notification_state.json")
REQUEST_DELAY = 3

HEADERS = {
    "User-Agent": "Mozilla/5.0 (compatible; HalkaArzTakip/1.0)",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
}

# FCM v1 API (bildirimler price_checker.py tarafından da kullanılır)
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_SA_KEY_JSON = os.environ.get("FIREBASE_SA_KEY_JSON", "")


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


def parse_kap_halka_arz() -> list[dict]:
    """KAP halka arz duyurularını çeker."""
    results = []

    # KAP bildirim API
    url = "https://www.kap.org.tr/tr/api/memberDisclosureQuery"
    payload = {
        "fromDate": (datetime.now() - timedelta(days=30)).strftime("%Y-%m-%d"),
        "toDate": datetime.now().strftime("%Y-%m-%d"),
        "subject": "halka arz",
    }

    try:
        time.sleep(REQUEST_DELAY)
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
                                "tarih": item.get("publishDate", ""),
                            })
                    except Exception:
                        continue
            print(f"[BİLGİ] KAP'tan {len(results)} duyuru bulundu.")
        else:
            print(f"[UYARI] KAP API ({resp.status_code})")
    except Exception as e:
        print(f"[HATA] KAP: {e}")

    return results


def parse_halkarz_drafts() -> list[dict]:
    """halkarz.com 'Taslak Arzlar' ve 'İlk Halka Arzlar' sekmelerinden verileri çeker."""
    results = []
    print("[BİLGİ] halkarz.com üzerinden liste kontrol ediliyor...")
    resp = safe_request("https://halkarz.com")
    if not resp:
        return results
        
    soup = BeautifulSoup(resp.text, "html.parser")
    # Tüm listeleri al (Taslaklar ve İlk Halka Arzlar)
    draft_lists = soup.find_all("ul", class_="halka-arz-list")
    if not draft_lists:
        print("[UYARI] halkarz.com listeleri bulunamadı.")
        return results
        
    for draft_list in draft_lists:
        for li in draft_list.find_all("li", recursive=False):
            article = li.find("article")
            if not article: continue
                
            h3 = article.find("h3", class_="il-halka-arz-sirket")
            if not h3: continue
                
            name = h3.text.strip()
        
            bist_kod_span = article.find("span", class_="il-bist-kod")
            bist_kod = bist_kod_span.text.strip() if bist_kod_span else ""
            
            # Eğer henüz BIST kodu belli değilse geçici bir kod oluştur (anahtar olarak kullanmak için)
            code = bist_kod.upper()
            if not code:
                import hashlib
                name_hash = hashlib.md5(name.encode('utf-8')).hexdigest()[:4].upper()
                code = f"TAS_{name_hash}"
                
            durum_span = li.find("span", class_="il-durum")
            durum_text = durum_span.text.strip().lower() if durum_span else ""
            
            durum = "taslak"
            if "toplanıyor" in durum_text:
                durum = "talep_topluyor"
            elif "işlem görüyor" in durum_text:
                durum = "islem_goruyor"
                
            results.append(create_ipo_entry(
                sirket_kodu=code,
                sirket_adi=name,
                durum=durum
            ))
            
    print(f"[BİLGİ] halkarz.com'dan {len(results)} şirket tespit edildi.")
    return results


def create_ipo_entry(
    sirket_kodu: str,
    sirket_adi: str,
    arz_fiyati: float = 0,
    toplam_lot: int = 0,
    dagitim_sekli: str = "Eşit",
    konsorsiyum_lideri: str = "",
    iskonto_orani: float = 0.0,
    fon_kullanim_yeri: Optional[dict] = None,
    katilim_endeksine_uygun: bool = False,
    talep_baslangic: str = "",
    talep_bitis: str = "",
    borsada_islem_tarihi: str = "",
    durum: str = "taslak",
    son_katilimci_sayilari: Optional[list] = None,
) -> dict:
    """Standart IPO veri girişi oluşturur."""
    return {
        "sirket_kodu": sirket_kodu.upper(),
        "sirket_adi": sirket_adi,
        "arz_fiyati": arz_fiyati,
        "toplam_lot": toplam_lot,
        "dagitim_sekli": dagitim_sekli,
        "konsorsiyum_lideri": konsorsiyum_lideri,
        "iskonto_orani": iskonto_orani,
        "fon_kullanim_yeri": fon_kullanim_yeri or {
            "yatirim": 0, "borc_odeme": 0, "isletme_sermayesi": 0
        },
        "katilim_endeksine_uygun": katilim_endeksine_uygun,
        "talep_baslangic": talep_baslangic,
        "talep_bitis": talep_bitis,
        "borsada_islem_tarihi": borsada_islem_tarihi,
        "durum": durum,
        "son_katilimci_sayilari": son_katilimci_sayilari or [],
        "guncelleme_zamani": datetime.now().isoformat(),
    }


def load_manual_data() -> list[dict]:
    """Manuel IPO verilerini yükler."""
    if not os.path.exists(MANUAL_FILE):
        return []
    try:
        with open(MANUAL_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[HATA] Manuel veri: {e}")
        return []


def load_existing_data() -> list[dict]:
    """Mevcut IPO verilerini yükler."""
    if not os.path.exists(OUTPUT_FILE):
        return []
    try:
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[HATA] Mevcut veri: {e}")
        return []


def load_notification_state() -> dict:
    """Bildirim state yükler."""
    if not os.path.exists(STATE_FILE):
        return {}
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return {}


def save_notification_state(state: dict):
    """Bildirim state kaydeder."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)


def merge_ipo_data(existing: list[dict], new_data: list[dict]) -> list[dict]:
    """Mevcut ve yeni verileri birleştirir (şirket koduna göre)."""
    merged = {item["sirket_kodu"]: item for item in existing}
    for item in new_data:
        code = item["sirket_kodu"]
        if code in merged:
            existing_item = merged[code]
            item["guncelleme_zamani"] = datetime.now().isoformat()
            merged[code] = {**existing_item, **item}
        else:
            merged[code] = item
    return list(merged.values())


def update_ipo_statuses(ipos: list[dict]) -> list[dict]:
    """IPO durumlarını tarihlere göre otomatik günceller."""
    now = datetime.now()
    for ipo in ipos:
        try:
            talep_bas = ipo.get("talep_baslangic", "")
            talep_bit = ipo.get("talep_bitis", "")
            islem_tar = ipo.get("borsada_islem_tarihi", "")

            if islem_tar:
                islem_date = datetime.fromisoformat(islem_tar.replace("Z", ""))
                if now >= islem_date:
                    ipo["durum"] = "islem_goruyor"
                    continue

            if talep_bas and talep_bit:
                bas_date = datetime.fromisoformat(talep_bas.replace("Z", ""))
                bit_date = datetime.fromisoformat(talep_bit.replace("Z", ""))
                if bas_date <= now <= bit_date:
                    ipo["durum"] = "talep_topluyor"
                elif now > bit_date:
                    ipo["durum"] = "talep_topluyor"  # Bitti ama henüz işlem görmüyor
                else:
                    ipo["durum"] = "taslak"
        except (ValueError, TypeError):
            pass
    return ipos


def fetch_historical_sparklines(ipos: list[dict]) -> list[dict]:
    """Yahoo Finance'den son 30 günlük kapanışları ve istatistikleri çeker."""
    for ipo in ipos:
        # Sadece işlem görenlerin geçmiş grafiğini alalım
        if ipo.get("durum") != "islem_goruyor":
            continue
            
        try:
            ticker = f"{ipo['sirket_kodu']}.IS"
            # period="2y" ile ilk gününden itibaren tüm veriyi almak garanti olur 
            # ancak biz sparkline için son 30 günü, tavan hesabı için tüm günleri kullanacağız.
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
            
            # Tavan gün sayısı hesapla
            tavan_count = 0
            arz_fiyati = float(ipo.get("arz_fiyati", 0))
            
            # İlk gün tavan kontrolü
            if arz_fiyati > 0 and (closes[0] - arz_fiyati) / arz_fiyati >= 0.095:
                tavan_count += 1
                
            # Diğer günler tavan kontrolü
            for i in range(1, len(closes)):
                if closes[i-1] > 0 and (closes[i] - closes[i-1]) / closes[i-1] >= 0.095:
                    tavan_count += 1
                    
            ipo["tavan_gun"] = tavan_count
            
            # Son 6 ayda çıkanların tüm grafiğini kaydet, daha eskiler için son 30 günü al
            include_full_chart = False
            islem_tarihi_str = ipo.get("borsada_islem_tarihi", "")
            if islem_tarihi_str:
                try:
                    islem_date = datetime.fromisoformat(islem_tarihi_str.replace("Z", ""))
                    if datetime.now() - islem_date <= timedelta(days=180):
                        include_full_chart = True
                except:
                    pass

            if include_full_chart:
                ipo["sparkline"] = [float(x) for x in closes]
                ipo["sparkline_dates"] = dates
            else:
                ipo["sparkline"] = [float(x) for x in closes[-30:]] if len(closes) > 30 else [float(x) for x in closes]
                ipo["sparkline_dates"] = dates[-30:] if len(dates) > 30 else dates
                
            ipo["static_fetched"] = True
            ipo["static_fetched_at"] = datetime.now().isoformat()
            
            print(f"[YAHOO] {ticker} verisi güncellendi: {tavan_count} tavan, fiyat {closes[-1]:.2f}")
        except Exception as e:
            print(f"[HATA] Yahoo Finance iterasyonu {ipo['sirket_kodu']}: {e}")
            
    return ipos


def notify_new_ipos(existing_codes: set, all_ipos: list[dict], state: dict) -> dict:
    """Yeni eklenen IPO'lar için bildirim gönderir."""
    for ipo in all_ipos:
        code = ipo["sirket_kodu"]
        state_key = f"yeni_arz_{code}"
        if code not in existing_codes and state_key not in state:
            send_notification(
                title="🆕 Yeni Halka Arz!",
                body=f"{ipo.get('sirket_adi', code)} halka arza hazırlanıyor.",
                data={"type": "yeni_arz", "ticker": code},
            )
            state[state_key] = datetime.now().isoformat()
    return state


def save_data(ipos: list[dict]):
    """IPO verilerini JSON'a kaydeder."""
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(ipos, f, ensure_ascii=False, indent=2)
    print(f"[BİLGİ] {len(ipos)} IPO kaydedildi → {OUTPUT_FILE}")


def main():
    """Ana fonksiyon."""
    print("=" * 60)
    print(f"Halka Arz Veri Motoru — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    # 1. Mevcut veriler
    existing_data = load_existing_data()
    existing_codes = {item["sirket_kodu"] for item in existing_data}
    print(f"[BİLGİ] Mevcut: {len(existing_data)} IPO")

    # 2. KAP'tan çek
    kap_data = parse_kap_halka_arz()
    print(f"[BİLGİ] KAP: {len(kap_data)} kayıt")

    # 3. halkarz.com Taslaklar
    halkarz_drafts = parse_halkarz_drafts()

    # 4. Manuel veriler
    manual_data = load_manual_data()
    print(f"[BİLGİ] Manuel: {len(manual_data)} kayıt")

    # 5. Birleştir
    all_new = kap_data + halkarz_drafts + manual_data
    merged = merge_ipo_data(existing_data, all_new)

    # 5. Durumları güncelle
    updated = update_ipo_statuses(merged)

    # 6. Yahoo Finance'den sparkline grafik verilerini çek
    print("[BİLGİ] Grafik verileri güncelleniyor (YFinance)...")
    updated_with_sparklines = fetch_historical_sparklines(updated)

    # 7. Yeni IPO'lar için bildirim
    state = load_notification_state()
    state = notify_new_ipos(existing_codes, updated_with_sparklines, state)
    save_notification_state(state)

    # 8. Kaydet
    save_data(updated_with_sparklines)

    print("=" * 60)
    print("[BİLGİ] İşlem tamamlandı.")


if __name__ == "__main__":
    main()
