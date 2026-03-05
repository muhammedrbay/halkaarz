#!/usr/bin/env python3
"""
Tek Seferlik Fiyat Geçmişi Doldurma
====================================
Her 'islem' hissesinin tarih alanından başlangıç tarihini çıkarır,
Yahoo Finance'ten günlük kapanış fiyatlarını çeker ve
Firestore fiyat_gecmisi alanına yazar.
"""

import json, os, sys, time
from datetime import datetime, timedelta

import requests
import yfinance as yf
from google.oauth2 import service_account
from google.auth.transport.requests import Request

# ─── Yapılandırma ────────────────────────────────────────
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "")
FIREBASE_SA_KEY_JSON = os.environ.get("FIREBASE_SA_KEY_JSON", "")
COLLECTION = "halka_arzlar"

# Türkçe ay isimleri
AY_MAP = {
    "ocak": 1, "şubat": 2, "mart": 3, "nisan": 4,
    "mayıs": 5, "haziran": 6, "temmuz": 7, "ağustos": 8,
    "eylül": 9, "ekim": 10, "kasım": 11, "aralık": 12,
}


# ─── Firebase Auth ───────────────────────────────────────
def get_token():
    sa = json.loads(FIREBASE_SA_KEY_JSON)
    creds = service_account.Credentials.from_service_account_info(
        sa, scopes=["https://www.googleapis.com/auth/datastore"]
    )
    creds.refresh(Request())
    return creds.token


def _fs_url(path):
    return f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/{path}"


def _from_fv(fv):
    if "stringValue" in fv: return fv["stringValue"]
    if "integerValue" in fv: return int(fv["integerValue"])
    if "doubleValue" in fv: return fv["doubleValue"]
    if "booleanValue" in fv: return fv["booleanValue"]
    if "mapValue" in fv: return {k: _from_fv(v) for k, v in fv.get("mapValue", {}).get("fields", {}).items()}
    return None


def _to_fv(val):
    if isinstance(val, bool): return {"booleanValue": val}
    if isinstance(val, int): return {"integerValue": str(val)}
    if isinstance(val, float): return {"doubleValue": val}
    if isinstance(val, str): return {"stringValue": val}
    if isinstance(val, dict): return {"mapValue": {"fields": {k: _to_fv(v) for k, v in val.items()}}}
    return {"stringValue": str(val)}


# ─── Firestore Okuma ─────────────────────────────────────
def get_islem_hisseleri(token):
    docs, pt = [], None
    while True:
        params = {"pageSize": 100}
        if pt: params["pageToken"] = pt
        r = requests.get(_fs_url(COLLECTION), params=params,
                         headers={"Authorization": f"Bearer {token}"}, timeout=30)
        if r.status_code != 200:
            print(f"  Firestore hata: {r.status_code}")
            break
        res = r.json()
        for doc in res.get("documents", []):
            p = {k: _from_fv(v) for k, v in doc.get("fields", {}).items()}
            p["_doc_id"] = doc["name"].split("/")[-1]
            if p.get("durum") == "islem":
                docs.append(p)
        pt = res.get("nextPageToken")
        if not pt: break
    return docs


# ─── Tarih Parse ─────────────────────────────────────────
def parse_turkish_tarih(s):
    """
    Türkçe tarih formatlarını parse eder:
    - "28-29-30 Ocak 2026" → son gün: 30 Ocak 2026
    - "25-26 Aralık 2025" → son gün: 26 Aralık 2025
    - "11-12-13 Şubat 2026" → son gün: 13 Şubat 2026
    - "05.03.2025" → DD.MM.YYYY
    - "05.03.2025 - 07.03.2025" → son gün: 07.03.2025
    """
    if not s:
        return None

    s = s.strip()

    # DD.MM.YYYY formatı
    if "." in s and not any(ay in s.lower() for ay in AY_MAP):
        try:
            # "05.03.2025 - 07.03.2025" → son tarihi al
            if " - " in s:
                part = s.split(" - ")[-1].strip()
            else:
                part = s.split(" ")[0].strip()
            parts = part.split(".")
            if len(parts) == 3:
                return datetime(int(parts[2]), int(parts[1]), int(parts[0]))
        except:
            pass

    # Türkçe format: "28-29-30 Ocak 2026"
    try:
        tokens = s.split()
        # Son token yıl olmalı
        yil = int(tokens[-1])
        # Sondan ikinci token ay olmalı
        ay_str = tokens[-2].lower()
        ay = AY_MAP.get(ay_str)
        if not ay:
            return None
        # İlk token(lar) günler: "28-29-30" veya "28"
        gunler_str = tokens[0]
        gunler = [int(g) for g in gunler_str.split("-")]
        son_gun = max(gunler)
        return datetime(yil, ay, son_gun)
    except:
        pass

    return None


# ─── Yahoo Finance Geçmiş ───────────────────────────────
def fetch_history(kod, start_date):
    """Yahoo Finance'ten günlük kapanış fiyatlarını çeker."""
    sym = f"{kod}.IS"
    try:
        tk = yf.Ticker(sym)
        hist = tk.history(start=start_date.strftime("%Y-%m-%d"),
                          end=(datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d"))
        if hist.empty:
            print(f"    {kod}: Veri yok")
            return {}
        result = {}
        for date, row in hist.iterrows():
            key = date.strftime("%Y-%m-%d")
            result[key] = round(float(row["Close"]), 2)
        return result
    except Exception as e:
        print(f"    {kod}: Yahoo hata — {e}")
        return {}


# ─── Firestore Yazma ────────────────────────────────────
def write_fiyat_gecmisi(token, doc_id, fiyat_gecmisi):
    """fiyat_gecmisi alanını merge ile günceller."""
    url = _fs_url(f"{COLLECTION}/{doc_id}")
    body = {"fields": {"fiyat_gecmisi": _to_fv(fiyat_gecmisi)}}
    fp = "updateMask.fieldPaths=fiyat_gecmisi"
    r = requests.patch(f"{url}?{fp}", json=body,
                       headers={"Authorization": f"Bearer {token}",
                                "Content-Type": "application/json"}, timeout=15)
    return r.status_code == 200


# ─── Main ────────────────────────────────────────────────
def main():
    print("=" * 60)
    print("  Fiyat Geçmişi Backfill — Yahoo Finance → Firestore")
    print("=" * 60)

    if not FIREBASE_PROJECT_ID or not FIREBASE_SA_KEY_JSON:
        print("[HATA] FIREBASE_PROJECT_ID veya FIREBASE_SA_KEY_JSON ayarlanmadı!")
        sys.exit(1)

    token = get_token()

    # 1. İşlem gören hisseleri çek
    print("\n[1/3] Firestore'dan islem hisseleri çekiliyor...")
    hisseler = get_islem_hisseleri(token)
    print(f"  {len(hisseler)} hisse bulundu.")

    if not hisseler:
        print("  İşlem gören hisse yok!")
        return

    # 2. Her hisse için Yahoo Finance geçmişini çek
    print("\n[2/3] Yahoo Finance'ten geçmiş fiyatlar çekiliyor...")
    toplam = 0

    for h in hisseler:
        kod = h["_doc_id"]
        adi = h.get("sirket_adi", kod)
        tarih_str = h.get("bist_ilk_islem_tarihi", "") or h.get("tarih", "")
        mevcut_gecmis = h.get("fiyat_gecmisi", {})
        if not isinstance(mevcut_gecmis, dict):
            mevcut_gecmis = {}

        # Tarih parse — talep toplama bitiş tarihini al
        son_talep_tarihi = parse_turkish_tarih(tarih_str)
        if not son_talep_tarihi:
            print(f"  {kod} ({adi}): tarih parse edilemedi ('{tarih_str}') → atlanıyor")
            continue

        # İşleme başlama tarihi ≈ talep toplama bitişinden ~3 gün sonra
        # Ama Yahoo zaten sadece işlem günlerinde veri döndürür
        start_date = son_talep_tarihi + timedelta(days=1)

        print(f"  {kod} ({adi}): talep={tarih_str} → yahoo start={start_date.strftime('%d.%m.%Y')}...")
        yeni_fiyatlar = fetch_history(kod, start_date)

        if not yeni_fiyatlar:
            continue

        # Mevcut geçmişle birleştir
        birlesmis = {**mevcut_gecmis, **yeni_fiyatlar}
        gun_sayisi = len(yeni_fiyatlar)
        toplam_gun = len(birlesmis)

        # Token yenilemesi
        try:
            token = get_token()
        except:
            pass

        ok = write_fiyat_gecmisi(token, kod, birlesmis)
        status = "✓" if ok else "✗"
        print(f"    [{status}] {gun_sayisi} yeni gün → toplam {toplam_gun} gün")
        toplam += gun_sayisi

        time.sleep(0.5)  # Yahoo rate limit

    # 3. Özet
    print(f"\n[3/3] Tamamlandı!")
    print(f"  Toplam {toplam} fiyat noktası Firestore'a yazıldı.")
    print("=" * 60)


if __name__ == "__main__":
    main()
