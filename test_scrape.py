import requests
from bs4 import BeautifulSoup
headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'}
try:
    r = requests.get('https://halkaarz.net/', headers=headers, timeout=5)
    print(r.status_code)
    if r.status_code == 200:
        soup = BeautifulSoup(r.text, 'html.parser')
        # find the list of IPOs
        # halkaarz.net lists IPOs with classes like "post-title"
        for a in soup.select('h3.post-title a')[:5]:
            print(a.text, a['href'])
except Exception as e:
    print('Failed net:', e)

try:
    r = requests.get('https://halkaarz.com/', headers=headers, timeout=5)
    print(r.status_code)
    if r.status_code == 200:
        soup = BeautifulSoup(r.text, 'html.parser')
        for a in soup.select('h3 a')[:5]:
            print(a.text, a['href'])
except Exception as e:
    print('Failed com:', e)
