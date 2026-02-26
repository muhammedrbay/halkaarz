import requests
from bs4 import BeautifulSoup
import json

def parse_halkarz_drafts():
    with open("halkarz.html", "r") as f:
        html = f.read()
    
    soup = BeautifulSoup(html, "html.parser")
    drafts = []
    
    # Locate the list of draft ipos
    draft_list = soup.find("ul", class_="halka-arz-list taslak")
    if not draft_list:
        print("Could not find draft list.")
        return
        
    for li in draft_list.find_all("li", recursive=False):
        article = li.find("article")
        if not article: continue
            
        h3 = article.find("h3", class_="il-halka-arz-sirket")
        if not h3: continue
            
        name = h3.text.strip()
        
        bist_kod_span = article.find("span", class_="il-bist-kod")
        bist_kod = bist_kod_span.text.strip() if bist_kod_span else ""
        
        drafts.append({
            "sirket_adi": name,
            "sirket_kodu": bist_kod,
            "durum": "taslak"
        })
        
    print(json.dumps(drafts, indent=2, ensure_ascii=False))
    
parse_halkarz_drafts()
