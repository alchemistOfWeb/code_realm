# Собирает все русские строки интерфейса и данных в locale/en.json (ключ — русский текст).
# Существующие переводы сохраняются, новые ключи получают пустое значение.
# usage: python tools/i18n/extract.py [--missing out.json]   — выгрузить непереведённые строки
import re, glob, os, sys, json

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
EN = os.path.join(ROOT, "locale", "en.json")
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
CYR = re.compile("[Ѐ-ӿ]")
SKIP_GD = {"smoke_test.gd", "ContentParser.gd", "QuizGenerator.gd", "ClaudeNotesExporter.gd", "model_viewer.gd", "PythonRunner.gd"}
keys = {}


def add(s, src):
    if s and CYR.search(s):
        keys.setdefault(s, src)


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


# --- GDScript
for path in glob.glob(os.path.join(ROOT, "**", "*.gd"), recursive=True):
    name = os.path.basename(path)
    if name in SKIP_GD:
        continue
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith("#"):
            continue
        for m in LIT.finditer(line):
            add(unescape(m.group(1)), name)
# PythonRunner: только сообщения об ошибках
for s in ["Превышено время выполнения — бесконечный цикл?", "Python не вернул результат", "Ошибка всё ещё в коде (проверка по шаблону: Python не найден)",
          "Код не изменён", "Тест не пройден", "RecursionError: бесконечная рекурсия — нет базового случая?"]:
    add(s, "PythonRunner.gd")

# --- Сцены
TSCN = re.compile(r'^(?:text|tooltip_text|placeholder_text|title) = "((?:[^"\\]|\\.)*)"', re.M)
for path in glob.glob(os.path.join(ROOT, "**", "*.tscn"), recursive=True):
    for m in TSCN.finditer(open(path, encoding="utf-8").read()):
        add(unescape(m.group(1)), os.path.basename(path))


# --- Данные
def walk(v, fields, src):
    if isinstance(v, dict):
        for k, x in v.items():
            if isinstance(x, str) and (fields is None or k in fields) and not k.endswith("_en"):
                if not (k + "_en") in v:
                    add(x, src)
            elif isinstance(x, list) and k in ("options",):
                for o in x:
                    if isinstance(o, str):
                        add(o, src)
            else:
                walk(x, fields, src)
    elif isinstance(v, list):
        for x in v:
            walk(x, fields, src)


DATA = {
    "dialogues.json": {"text", "name", "title", "desc"},
    "riddles.json": {"inscription", "question", "explanation", "options"},
    "safes.json": {"title", "story", "hint"},
    "cards_catalog.json": {"description", "flavor_text"},
    "enemies_catalog.json": {"title", "description"},
    "specializations.json": {"description", "desc", "short"},
}
for f, fields in DATA.items():
    p = os.path.join(ROOT, "data", f)
    if os.path.exists(p):
        walk(json.load(open(p, encoding="utf-8")), fields, f)

os.makedirs(os.path.dirname(EN), exist_ok=True)
old = json.load(open(EN, encoding="utf-8")) if os.path.exists(EN) else {}
merged = {k: old.get(k, "") for k in sorted(keys)}
for k, v in old.items():          # сохранить и устаревшие переводы (не мешают), пустые — выбросить
    if v:
        merged.setdefault(k, v)
json.dump(merged, open(EN, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent="\t", sort_keys=True)
missing = [k for k in keys if not merged.get(k)]
print("keys:", len(keys), "translated:", len(keys) - len(missing), "missing:", len(missing))
if "--missing" in sys.argv:
    out = sys.argv[sys.argv.index("--missing") + 1]
    by_src = {}
    for k in missing:
        by_src.setdefault(keys[k], []).append(k)
    json.dump(by_src, open(out, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
    for s, l in sorted(by_src.items(), key=lambda x: -len(x[1])):
        print(f"{len(l):5d} {s}")
