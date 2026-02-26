import requests
from bs4 import BeautifulSoup

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

def main():
    resp = requests.get("https://halkarz.com", headers=HEADERS)
    soup = BeautifulSoup(resp.text, "html.parser")
    # Finding elements
    # Usually they might be in lists. Let's look for company names.
    for a in soup.find_all("h3"):
        print(a.text.strip())
        
main()
