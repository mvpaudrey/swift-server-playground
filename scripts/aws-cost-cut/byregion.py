import sys, json
d = json.load(sys.stdin)
for g in sorted(d["ResultsByTime"][0]["Groups"], key=lambda g: -float(g["Metrics"]["UnblendedCost"]["Amount"])):
    a = float(g["Metrics"]["UnblendedCost"]["Amount"])
    if a >= 0.5:
        print(f"{a:8.2f}  {g['Keys'][0]}")
