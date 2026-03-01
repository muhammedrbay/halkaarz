import re

text = "- %25 Şirkete ait filo araçlarının yenilenmesi ve filonun genişletilmesi.\n- %15 Ar-Ge yatırımları.\n- %30 Yurt içi ve yurt dışı şirket kurulumu / ortaklıklar.\n- %30 İşletme sermayesi ve Şirket'in operasyonel faaliyetlerinin finansmanı."
text2 = "- %100-85 Proje maliyetlerinin finansmanı.\n- %0-15 İşletme sermayesi."

def parse_fon(t):
    res = {}
    lines = t.split('\n')
    for line in lines:
        m = re.search(r'%(\d+(?:-\d+)?)\s*(.*)', line)
        if m:
            pct_str = m.group(1)
            desc = m.group(2).strip()
            if len(desc) > 30:
                desc = desc[:27] + "..."
            # If range like 100-85, take average or just first
            if '-' in pct_str:
                p1, p2 = pct_str.split('-')
                pct = (int(p1) + int(p2)) / 2
            else:
                pct = float(pct_str)
            res[desc] = pct
    return res

print(parse_fon(text))
print(parse_fon(text2))
