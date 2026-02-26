import requests
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/122.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html",
}
r = requests.get("https://halkarz.com", headers=HEADERS)
with open("halkarz.html", "w") as f:
    f.write(r.text)

