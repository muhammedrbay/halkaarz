import requests
import json

url = "https://www.kap.org.tr/tr/api/memberDisclosureQuery"
headers = {"Content-Type": "application/json"}
payload = {
    "fromDate": "2024-01-01",
    "toDate": "2025-12-31",
    "disclosureClass": "FR",
    "limit": 100,
    "offset": 0,
    "subjectList": ["TASARRUF SAHİPLERİNE SATIŞ DUYURUSU", "İZAHNAME"]
}
r = requests.post(url, headers=headers, json=payload)
print(r.status_code)
if r.status_code == 200:
    data = r.json()
    print(json.dumps(data[:5], indent=2, ensure_ascii=False))
else:
    print(r.text)
