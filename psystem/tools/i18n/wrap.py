# Оборачивает русские строковые литералы в .gd в Loc.t("…"), чтобы они переводились
# (в т.ч. строки с подстановкой %d/%s и склейкой). Пропускает: комментарии, const-блоки,
# @export, сигнатуры функций, шаблоны match, ключи словарей, уже обёрнутые строки, тесты.
# usage: python tools/i18n/wrap.py [--dry]
import re, glob, os, sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
CYR = re.compile("[Ѐ-ӿ]")
SKIP_FILES = {"smoke_test.gd", "Loc.gd"}
dry = "--dry" in sys.argv
total = 0
for path in glob.glob(os.path.join(ROOT, "**", "*.gd"), recursive=True):
    if os.path.basename(path) in SKIP_FILES:
        continue
    lines = open(path, encoding="utf-8").read().split("\n")
    out = []
    depth = 0          # глубина скобок внутри const-блока
    in_const = False
    changed = 0
    for line in lines:
        stripped = line.strip()
        if not in_const and re.match(r"^(static\s+)?const\s", stripped):
            in_const = True
            depth = 0
        if in_const:
            depth += line.count("{") + line.count("[") + line.count("(") - line.count("}") - line.count("]") - line.count(")")
            out.append(line)
            if depth <= 0:
                in_const = False
            continue
        if stripped.startswith("#") or stripped.startswith("@export") or stripped.startswith("func ") or stripped.startswith("static func "):
            out.append(line)
            continue
        if re.match(r'^"[^"]*"\s*(,\s*"[^"]*"\s*)*:$', stripped):    # шаблон match
            out.append(line)
            continue
        code, _, comment = line.partition(" #") if '"' not in line.split(" #")[-1] else (line, "", "")
        result = []
        pos = 0
        for m in LIT.finditer(code):
            s, e = m.start(), m.end()
            text = m.group(1)
            before = code[:s]
            after = code[e:]
            wrap = bool(CYR.search(text))
            if wrap and (before.rstrip().endswith("Loc.t(") or before.rstrip().endswith("tr(")):
                wrap = False
            if wrap and re.match(r"^\s*:", after) and not re.match(r"^\s*:\s*$", after):   # ключ словаря
                wrap = False
            if wrap and before.rstrip().endswith(("has_meta(", "get_meta(", "set_meta(", "has(", "get(")):
                wrap = False
            result.append(code[pos:s])
            result.append('Loc.t("%s")' % text if wrap else code[s:e])
            if wrap:
                changed += 1
            pos = e
        result.append(code[pos:])
        new_line = "".join(result) + ((" #" + comment) if comment else "")
        out.append(new_line)
    if changed:
        total += changed
        print(f"{changed:4d} {os.path.relpath(path, ROOT)}")
        if not dry:
            open(path, "w", encoding="utf-8").write("\n".join(out))
print("wrapped:", total)
