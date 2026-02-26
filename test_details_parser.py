import requests
from bs4 import BeautifulSoup
import re

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
}

def clean_money(text):
    text = text.replace('TL', '').replace('₺', '').strip()
    text = text.split('/')[0].strip() # 22,00 TL / 24,00 TL -> 22,00 TL
    text = text.replace('.', '').replace(',', '.')
    try:
        return float(text)
    except:
        return 0.0

def clean_lot(text):
    # '38.000.000 Lot' -> 38000000
    text = text.lower().replace('lot', '').replace('.', '').strip()
    try:
        return int(text)
    except:
        return 0

def fetch_details(url):
    print(f"Fetching {url}")
    resp = requests.get(url, headers=HEADERS)
    soup = BeautifulSoup(resp.text, 'html.parser')

    arz_fiyati = 0.0
    toplam_lot = 0
    dagitim_sekli = "Eşit"
    
    tables = soup.find_all('table')
    for tbl in tables:
        for tr in tbl.find_all('tr'):
            text = tr.text.strip().replace('\n', ' ')
            if 'Halka Arz Fiyatı' in text:
                val = text.split(':')[-1].strip()
                arz_fiyati = clean_money(val)
            elif 'Dağıtım Yöntemi' in text:
                val = text.split(':')[-1].strip()
                if 'Oransal' in val: dagitim_sekli = "Oransal"
            elif 'Pay' in text and 'Lot' in text:
                val = text.split(':')[-1].strip()
                toplam_lot = clean_lot(val)

    return arz_fiyati, toplam_lot, dagitim_sekli

print(fetch_details("https://halkarz.com/empa-elektronik-san-ve-tic-a-s/"))
print(fetch_details("https://halkarz.com/gentas-kimya-san-ve-tic-pazarlama-a-s/"))
