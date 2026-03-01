from bs4 import BeautifulSoup
import requests
import json
import os
import re
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, firestore

# --- 1) Firebase Firestore Kurulumu ---
# GitHub Secrets'tan alınacak JSON string formatındaki Firebase Service Account anahtarı.
cred_json = os.environ.get("FIREBASE_CREDENTIALS")
if cred_json:
    try:
        cred_dict = json.loads(cred_json)
        cred = credentials.Certificate(cred_dict)
        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)
        db = firestore.client()
        print("[BAŞARILI] Firebase veritabanı bağlantısı sağlandı.")
    except Exception as e:
        print(f"[HATA] Firebase sertifika ayrıştırma hatası: {e}")
        db = None
else:
    print("[UYARI] FIREBASE_CREDENTIALS environment değişkeni bulunamadı. Veriler veritabanına yazılmayacak.")
    db = None

# --- 2) KAP Sabitleri ve İstek Başlıkları ---
KAP_QUERY_URL = "https://www.kap.org.tr/tr/api/memberDisclosureQuery"
KAP_DETAIL_BASE = "https://www.kap.org.tr/tr/Bildirim/"

# Bot tespit sistemlerine (Cloudflare, WAF) karşı önlem amaçlı standart tarayıcı başvuru başlıkları
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Content-Type": "application/json",
    "Origin": "https://www.kap.org.tr",
    "Referer": "https://www.kap.org.tr/"
}


# --- 3) Halka Arz Duyurularını KAP API'sinden Çekme ---
def fetch_kap_disclosures():
    try:
        # Sunucu oturumu (session) başlatıyoruz ki CSRF / Cookie sorunlarını çözelim
        session = requests.Session()
        session.get("https://www.kap.org.tr/", headers=HEADERS, timeout=10)
        
        # Son bir yılın verilerini sorgulama (Tasarruf Sahiplerine Satış / İzahname)
        now = datetime.now()
        start_date = f"{now.year}-01-01"
        end_date = f"{now.year}-12-31"

        payload = {
            "fromDate": start_date,
            "toDate": end_date,
            "disclosureClass": "FR",
            "limit": 100,
            "offset": 0,
            "subjectList": ["TASARRUF SAHİPLERİNE SATIŞ DUYURUSU", "İZAHNAME"]
        }
        
        response = session.post(KAP_QUERY_URL, headers=HEADERS, json=payload, timeout=15)
        response.raise_for_status()
        
        # Sadece içerisinde Borsa Kodu bulunan, anlamlı duyuruları döndür
        data = response.json()
        return [d for d in data if d.get("stockCodes")]
    except Exception as e:
        print(f"[HATA] KAP sorgulama aşamasında bir sorun oluştu: {e}")
        return []


# --- 4) Her Bir Duyurunun İçindeki HTML Verilerini Ayrıştırma ---
def extract_ipo_details_from_html(html_content):
    """
    Sadece standart BeautifulSoup ve Regex kullanarak 
    karmaşık/düzensiz KAP HTML metinlerinden istenen değerleri çıkarır.
    """
    soup = BeautifulSoup(html_content, 'html.parser')
    
    # Varsayılan başlangıç değerleri
    details = {
        "arz_fiyati": 0.0,
        "toplam_lot": 0,
        "kisi_basi_lot": 0,
        "dagitim_sekli": "Bilinmiyor",
        "konsorsiyum_lideri": "Bilinmiyor",
        "katilim_endeksine_uygun": False,
        "talep_baslangic": "",
        "talep_bitis": "",
        "durum": "taslak",
        "bireysel_pay": ""
    }

    # Bütün HTML etiketlerini temizleyip aralarına boşluk atarak saf, okunabilir metin (text) oluştururuz
    text = soup.get_text(separator=' ', strip=True)
    lower_text = text.lower()

    try:
        # 4.1 Arz Fiyatı (Ör: 15,30 TL, 45.00 TL)
        # Fiyat terimini gördükten sonra gelen ilk ondalıklı sayıyı yakalamaya çalışır.
        fiyat_match = re.search(r'(?:halka arz fiyatı|satış fiyatı|birim pay fiyatı).*?(\d+[,.]\d+)\s*(?:tl|₺)', lower_text)
        if fiyat_match:
            # parseFloat işlemi (virgülü noktaya çevir)
            details["arz_fiyati"] = float(fiyat_match.group(1).replace(',', '.'))
            
        # 4.2 Toplam Lot Sayısı (Ör: 50.000.000 Lot)
        lot_match = re.search(r'(?:halka arz edilecek toplam pay|toplam lot|nominal değerli).*?(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d+)?)\s*(?:tl|lot|adet|pay)', lower_text)
        if lot_match:
            details["toplam_lot"] = int(lot_match.group(1).replace('.', '').replace(',', ''))
            
        # 4.3 Dağıtım Metodu 
        # (Özet bilgiler genelde sadece oransal veya eşit kelimesini barındırır)
        if "oransal" in lower_text:
            details["dagitim_sekli"] = "Oransal"
        elif "eşit" in lower_text:
            details["dagitim_sekli"] = "Eşit"
            
        # 4.4 Katılım Endeksi Uygunluk Statüsü
        if "katılım endeksine uygun" in lower_text or "katilim endeksine uygun" in lower_text:
             details["katilim_endeksine_uygun"] = True
             
        # 4.5 Konsorsiyum Lideri (Aracı Kurum)
        lider_match = re.search(r'(?:konsorsiyum lideri|aracı kurum).*?:?\s*([a-zA-ZğüşöçİĞÜŞÖÇ\s]+(?:menkul|yatırım))', lower_text)
        if lider_match:
            details["konsorsiyum_lideri"] = lider_match.group(1).strip().title()
            
        # 4.6 Bireysele Ayrılan Pay (Yüzde)
        bireysel_match = re.search(r'(?:bireysel yatırımcı|yurtiçi bireysel).*?(%?\s*\d+[,.]?\d*\s*%?)', lower_text)
        if bireysel_match:
            details["bireysel_pay"] = bireysel_match.group(1).strip()
            
        # 4.7 Koleksiyon / Talep Toplama Tarihleri ve "Durum" Analizi
        # Regex Açıklaması: Bir ve iki basamaklı iki günü tire (-) ile ayrılmış şekilde, peşine ay ismi ve 4 haneli yıl
        # Örnek: "12-13 Eylül 2024", "1 - 2 Ekim 2025" vb.
        date_match = re.search(r'(\d{1,2})\s*(?:-|–)\s*(\d{1,2})\s*([a-zA-ZğüşöçİĞÜŞÖÇ]+)\s*(\d{4})', text)
        
        today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        
        if date_match:
            start_d, end_d, month_str, year_str = date_match.groups()
            
            # Türkçe Ay -> Numerik Eşleme Tablosu
            aylar = {
                "ocak": 1, "şubat": 2, "subat": 2, "mart": 3, "nisan": 4, "mayıs": 5, "mayis": 5,
                "haziran": 6, "temmuz": 7, "ağustos": 8, "agustos": 8, "eylül": 9, "eylul": 9,
                "ekim": 10, "kasım": 11, "kasim": 11, "aralık": 12, "aralik": 12
            }
            
            ay_num = aylar.get(month_str.lower(), today.month)
            yil_num = int(year_str)
            
            # Başlangıç ve bitiş datetime objeleri
            start_date = datetime(yil_num, ay_num, int(start_d))
            end_date = datetime(yil_num, ay_num, int(end_d))
            
            details["talep_baslangic"] = start_date.strftime('%Y-%m-%dT00:00:00')
            details["talep_bitis"] = end_date.strftime('%Y-%m-%dT00:00:00')
            
            # Hafta sonu dahil 'Zaman Mantığı' algoritması (Bugün bu aralıktaysa talep topluyor)
            if end_date < today:
                details["durum"] = "gecmis"
            elif start_date <= today <= end_date:
                details["durum"] = "talep_topluyor"
            elif start_date > today:
                details["durum"] = "taslak"
        else:
            # Eğer belirli bir tarih aralığı tabloda okunamazsa, varsayılan olarak henüz belirsiz (taslak) kabul et
            details["durum"] = "taslak"

    except Exception as e:
        print(f"[UYARI] Detay ayrıştırmada hatalı yapı (Regex hatası es geçiliyor): {e}")

    return details


# --- 5) KAP Duyurularının İşlenmesi ve Veritabanı (Firestore) Yazımı ---
def process_and_upsert_disclosures(disclosures):
    if not db:
        print("[UYARI] Firestore Admin başlatılamadığı için sadece okuma (Dry Run) yapılacak.")
    
    upserted_count = 0
    seen_codes = set()
    
    for d in disclosures:
        try:
            raw_codes = d.get('stockCodes', '')
            company_name = d.get('companyName', 'Bilinmeyen Şirket')
            disclosure_id = d.get('disclosureIndex')
            
            if not raw_codes or not disclosure_id:
                continue
                
            # Bazı kayıtlarda birden fazla kod bulunabileceği için (virgülle ayırarak) ilk asıl kodu baz alıyoruz
            bist_code = raw_codes.split(',')[0].strip().upper()
            
            # Aynı hisseden birden fazla duyuru gelirse, en günceli (listede en üstte olanı) baz alarak mükerrer işlemden kaçınıyoruz.
            if bist_code in seen_codes:
                continue
            seen_codes.add(bist_code)
            
            print(f"-> İnceleniyor: {bist_code} - {company_name}")
            
            # Detay sayfası çağrısı (KAP'taki id bazlı hedef bildirim url'si)
            detail_url = f"{KAP_DETAIL_BASE}{disclosure_id}"
            resp = requests.get(detail_url, headers=HEADERS, timeout=10)
            
            # HTML Verisinin ayrıştırılması (Algoritma safhası)
            parsed_details = extract_ipo_details_from_html(resp.text)
            
            status = parsed_details["durum"]
            
            # Kullanıcının talebi: Sadece Talep ve Taslaklar tutulacak. Geçmişteki IPO'lara dokunma, atla.
            if status == "gecmis":
                print(f"      [ATLANDI] {bist_code} Süresi dolmuş geçmiş bildirim.")
                continue

            # Firestore için kaydetmeye hazır doküman objesi (idempotent format)
            doc_data = {
                "sirket_kodu": bist_code,
                "sirket_adi": company_name,
                "durum": status,
                "detay_url": detail_url,
                "arz_fiyati": parsed_details["arz_fiyati"],
                "toplam_lot": parsed_details["toplam_lot"],
                "kisi_basi_lot": parsed_details["kisi_basi_lot"],
                "dagitim_sekli": parsed_details["dagitim_sekli"],
                "konsorsiyum_lideri": parsed_details["konsorsiyum_lideri"],
                "katilim_endeksine_uygun": parsed_details["katilim_endeksine_uygun"],
                "talep_baslangic": parsed_details["talep_baslangic"],
                "talep_bitis": parsed_details["talep_bitis"],
                "bireysel_pay": parsed_details["bireysel_pay"],
                "guncelleme_zamani": datetime.now().isoformat()
            }
            
            # Firebase tarafına ID bazlı Upsert işlemi (Üzerine yazma / Güncelleme)
            # Böylece aynı BIST kodu tekrar geldiğinde mükerrer veri (duplicate) oluşmaz.
            if db:
                db.collection("ipos").document(bist_code).set(doc_data, merge=True)
                print(f"      [YAZILDI] ({bist_code}) Firestore'a güncellendi -> {status}")
            else:
                print(f"      [TEST-KAYDI] ({bist_code}) -> {status}")
                
            upserted_count += 1
            
        except Exception as e:
            print(f"[HATA] {d.get('companyName')} İşlenirken Arıza Tespit Edildi: {e}")
            
    print(f"\n[İŞLEM TAMAM] Toplam {upserted_count} adet aktif (Taslak & Talep) halka arz başarıyla kaydedildi.")


# Başlatıcı
if __name__ == "__main__":
    print(f"--- KAP Halka Arz Botu Başlatılıyor ({datetime.now().strftime('%Y-%m-%d %H:%M:%S')}) ---")
    disclosures = fetch_kap_disclosures()
    
    if disclosures:
        print(f"KAP Platformunda Toplam {len(disclosures)} Adet İlgili Duyuru / İzahname Saptandı.")
        process_and_upsert_disclosures(disclosures)
    else:
        print("[BİLGİ] İlgili tarihlerde yeni halka arz bildirimi bulunamadı veya KAP sunucularına ulaşılamadı.")
