# Поиск строковых литералов с кириллицей в .gd (для локализации).
# usage: python tools/i18n/scan.py [--files]
import re, glob, sys, os
LIT = re.compile(r'"((?:[^"\\n]|\.)*)"')
CYR = re.compile("[Ѐ-ӿ]")
root = os.path.join(os.path.dirname(__file__), "..", "..")
total = set()
per = {}
for f in glob.glob(os.path.join(root, "**", "*.gd"), recursive=True):
    n = 0
    for line in open(f, encoding="utf-8"):
        if line.lstrip().startswith("#"):
            continue
        for m in LIT.finditer(line):
            if CYR.search(m.group(1)):
                total.add(m.group(1))
                n += 1
    if n:
        per[os.path.relpath(f, root)] = n
print("unique:", len(total), "occurrences:", sum(per.values()))
if "--files" in sys.argv:
    for f, n in sorted(per.items(), key=lambda x: -x[1]):
        print(f"{n:5d} {f}")
