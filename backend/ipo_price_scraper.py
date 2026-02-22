#!/usr/bin/env python3
"""
Halka Arz Fiyatı Kazıma → ipos.json Güncelleme
================================================
Kaynak: halkarz.com
- Ana sayfadan tüm halka arz linklerini toplar
- Her birinin detay sayfasından BIST kodu + arz fiyatını kazır
- ipos.json'daki arz_fiyati alanını günceller
- GitHub Actions üzerinde günde 1 kez çalışır → ipos.json commit edilir

Anti-ban: Gerçekçi User-Agent, rastgele gecikmeler
"""

import json
import os
import re
import random
import time
from datetime import datetime
from typing import Optional

import requests
from bs4 import BeautifulSoup

# --- Yapılandırma ---
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
IPOS_FILE = os.path.join(DATA_DIR, "ipos.json")

BASE_URL = "https://halkarz.com"

# Gerçekçi Chrome/Mac User-Agent
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
    "Connection": "keep-alive",
}


# ─── Yardımcılar ──────────────────────────────────────────────────────────────

def safe_get(url: str, timeout: int = 15) -> Optional[requests.Response]:
    """Rate-limited HTTP GET."""
    delay = random.uniform(1.0, 2.5)
    time.sleep(delay)
    try:
        resp = requests.get(url, headers=HEADERS, timeout=timeout)
        resp.raise_for_status()
        return resp
    except requests.RequestException as e:
        print(f"  [HATA] {url} → {e}")
        return None


# ─── halkarz.com Kazıma ──────────────────────────────────────────────────────

def get_all_ipo_links() -> list[str]:
    """
    halkarz.com ana sayfasından tüm halka arz detay sayfa URL'lerini toplar.
    """
    print("[1/3] halkarz.com ana sayfası taranıyor...")
    resp = safe_get(BASE_URL)
    if not resp:
        print("  [HATA] Ana sayfa yüklenemedi!")
        return []

    soup = BeautifulSoup(resp.text, "html.parser")
    urls = set()

    for a in soup.find_all("a", href=True):
        href = a["href"]
        full_url = href if href.startswith("http") else BASE_URL + href

        if not full_url.startswith(BASE_URL + "/"):
            continue

        path = full_url.replace(BASE_URL, "").strip("/")
        if not path or "/" in path:
            continue
        if any(x in path for x in ["bist-endeks", "wp-content", "wp-admin"]):
            continue

        # Sadece şirket sayfalarını al (en az bir tire içermeli)
        if "-" in path:
            urls.add(full_url.rstrip("/") + "/")

    print(f"  {len(urls)} benzersiz şirket linki bulundu.")
    return list(urls)


def scrape_ipo_detail(url: str) -> Optional[dict]:
    """
    Bir halka arz detay sayfasından BIST kodu ve arz fiyatını kazır.
    """
    resp = safe_get(url)
    if not resp:
        return None

    soup = BeautifulSoup(resp.text, "html.parser")
    data = {"url": url}

    for tr in soup.find_all("tr"):
        cells = tr.find_all("td")
        if len(cells) < 2:
            continue

        label = cells[0].get_text(strip=True).lower()
        value = cells[1].get_text(strip=True)

        if "bist kodu" in label:
            data["bist_kodu"] = value.upper().strip()

        elif "halka arz fiyat" in label or "arz fiyat" in label:
            price_text = value.replace("TL", "").strip()
            price_text = price_text.replace(".", "").replace(",", ".")

            if "-" in price_text:
                price_text = price_text.split("-")[0].strip()

            try:
                data["arz_fiyati"] = float(price_text)
            except ValueError:
                match = re.search(r"(\d+\.?\d*)", price_text)
                if match:
                    data["arz_fiyati"] = float(match.group(1))

    return data if "bist_kodu" in data and "arz_fiyati" in data else None


def build_price_lookup(target_codes: set[str]) -> dict[str, float]:
    """
    halkarz.com'dan hedef BIST kodlarının arz fiyatlarını kazır.
    Dönüş: {BIST_KODU: arz_fiyati}
    """
    urls = get_all_ipo_links()
    if not urls:
        return {}

    results = {}
    found = set()
    total = len(urls)

    print(f"\n[2/3] {total} detay sayfası taranıyor (hedef: {len(target_codes)} kod)...\n")

    for i, url in enumerate(urls):
        # Hedef kodların hepsini bulduysa erken çık
        if found >= target_codes:
            print(f"\n  Tüm hedef kodlar bulundu ({len(found)}/{len(target_codes)}), erken çıkılıyor.")
            break

        # Her 20 sayfada durum bildir
        if (i + 1) % 20 == 0:
            print(f"  ... {i+1}/{total} sayfa tarandı, {len(found)}/{len(target_codes)} kod bulundu")

        detail = scrape_ipo_detail(url)
        if not detail:
            continue

        bist_kodu = detail["bist_kodu"]

        # Sadece hedeflediğimiz kodları al
        if bist_kodu in target_codes:
            results[bist_kodu] = detail["arz_fiyati"]
            found.add(bist_kodu)
            print(f"  [{len(found)}/{len(target_codes)}] {bist_kodu}: ₺{detail['arz_fiyati']} ✓")

    print(f"\n[halkarz.com ✓] {len(results)} arz fiyatı kazındı.")

    # Bulunamayan kodları raporla
    missing = target_codes - found
    if missing:
        print(f"  [UYARI] Bulunamayan kodlar: {', '.join(sorted(missing))}")

    return results


# ─── ipos.json İşlemleri ──────────────────────────────────────────────────────

def load_ipos() -> list:
    if not os.path.exists(IPOS_FILE):
        print("[HATA] ipos.json bulunamadı!")
        return []
    try:
        with open(IPOS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[HATA] ipos.json okuma: {e}")
        return []


def save_ipos(ipos: list):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(IPOS_FILE, "w", encoding="utf-8") as f:
        json.dump(ipos, f, ensure_ascii=False, indent=2)
    print(f"[✓] {len(ipos)} kayıt → ipos.json")


# ─── Ana Fonksiyon ────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print(f"IPO Fiyat Güncelleme (halkarz.com) — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print("=" * 60)

    ipos = load_ipos()
    if not ipos:
        print("[BİLGİ] İşlenecek IPO yok.")
        return

    # Hedef kodları çıkar
    target_codes = {ipo["sirket_kodu"].upper() for ipo in ipos if ipo.get("sirket_kodu")}
    print(f"[BİLGİ] ipos.json'da {len(ipos)} kayıt | Hedef: {', '.join(sorted(target_codes))}\n")

    # halkarz.com'dan fiyatları kazı
    scraped = build_price_lookup(target_codes)

    if not scraped:
        print("[UYARI] halkarz.com'dan fiyat alınamadı!")
        return

    # Fiyatları güncelle
    print(f"\n[3/3] Fiyatlar güncelleniyor...\n")
    updated_count = 0
    for ipo in ipos:
        code = ipo.get("sirket_kodu", "").upper()
        if code not in scraped:
            continue

        scraped_price = scraped[code]
        old_price = ipo.get("arz_fiyati", 0)

        if old_price != scraped_price:
            print(f"  {code}: ₺{old_price} → ₺{scraped_price}")
            ipo["arz_fiyati"] = scraped_price
            updated_count += 1

    if updated_count > 0:
        save_ipos(ipos)
        print(f"\n[✓] {updated_count} arz fiyatı güncellendi.")
    else:
        print("[BİLGİ] Tüm fiyatlar zaten doğru — güncelleme yok.")

    print("=" * 60)


if __name__ == "__main__":
    main()
