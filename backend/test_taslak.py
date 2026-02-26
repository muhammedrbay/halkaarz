import requests
from bs4 import BeautifulSoup
import json

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

resp = requests.get("https://halkarz.com", headers=HEADERS)
soup = BeautifulSoup(resp.text, "html.parser")

drafts = []
taslak_tab = soup.find(id="taslak-halka-arzlar")
if taslak_tab:
    for li in taslak_tab.find_all("li"):
        h3 = li.find("h3")
        a = li.find("a")
        if h3 and a:
            name = h3.text.strip()
            link = a["href"]
            print(f"Draft: {name} - {link}")
elif soup.find(id="taslaklar"):
    # Check if the id is different
    pass

# also try the 'halka-arzlar' class or id
for h3 in soup.find_all("h3"):
    if "Kimya" in h3.text or "Gentaş" in h3.text:
         print("Found related:", h3.text)

