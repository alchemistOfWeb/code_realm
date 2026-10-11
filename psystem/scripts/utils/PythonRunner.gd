class_name PythonRunner
extends RefCounted
## Проверка Python-кода сейфов: запускает установленный Python с тестами (assert) в отдельном
## процессе с таймаутом. Если Python не найден — запасная проверка регулярными выражениями
## (поле checks у сейфа).

const TIMEOUT_SEC := 4.0

static var _python := ""
static var _searched := false


## Путь к python.exe или "" если не найден.
static func find_python() -> String:
	if _searched:
		return _python
	_searched = true
	var candidates: Array = []
	var out: Array = []
	if OS.get_name() == "Windows":
		for name in ["python", "py", "python3"]:
			out.clear()
			if OS.execute("where", [name], out, true) == 0:
				for line in String(out[0]).split("\n"):
					var p := line.strip_edges()
					if p != "" and not "WindowsApps" in p:
						candidates.append(p)
	else:
		for name in ["python3", "python"]:
			out.clear()
			if OS.execute("which", [name], out) == 0:
				candidates.append(String(out[0]).strip_edges())
	for p in candidates:
		out.clear()
		if OS.execute(p, ["-c", "print(1)"], out) == 0:
			_python = p
			return p
	return ""


static func available() -> bool:
	return find_python() != ""


## Проверить код. Возвращает {ok, error, method: "python"|"pattern"}.
## host — любой узел в дереве (нужен для ожидания кадров).
static func check(host: Node, code: String, safe: Dictionary) -> Dictionary:
	var python := find_python()
	if python == "":
		return _pattern_check(code, safe)
	var dir := ProjectSettings.globalize_path("user://pyrun/")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := str(Time.get_ticks_msec())
	var script_path := dir.path_join("safe_%s.py" % stamp)
	var out_path := dir.path_join("result_%s.json" % stamp)
	var harness := """# -*- coding: utf-8 -*-
import json, traceback
USER_CODE = %s
TESTS = %s
OUT = %s
res = {"ok": False, "error": ""}
try:
    ns = {}
    exec(compile(USER_CODE, "<сейф>", "exec"), ns)
    exec(compile(TESTS, "<тесты>", "exec"), ns)
    res["ok"] = True
except AssertionError as e:
    res["error"] = "Тест не пройден" + (": " + str(e) if str(e) else "")
except RecursionError:
    res["error"] = "RecursionError: бесконечная рекурсия — нет базового случая?"
except Exception as e:
    tb = traceback.format_exception_only(type(e), e)
    res["error"] = "".join(tb).strip()
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False)
""" % [JSON.stringify(code), JSON.stringify(safe.get("tests", "")), JSON.stringify(out_path)]
	var f := FileAccess.open(script_path, FileAccess.WRITE)
	f.store_string(harness)
	f.close()
	var pid := OS.create_process(python, ["-I", script_path])
	if pid <= 0:
		return _pattern_check(code, safe)
	var start := Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - start < TIMEOUT_SEC * 1000.0:
		await host.get_tree().process_frame
	if OS.is_process_running(pid):
		OS.kill(pid)
		_cleanup(script_path, out_path)
		return {"ok": false, "error": Loc.t("Превышено время выполнения — бесконечный цикл?"), "method": "python"}
	var result := {"ok": false, "error": Loc.t("Python не вернул результат"), "method": "python"}
	if FileAccess.file_exists(out_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(out_path))
		if parsed is Dictionary:
			result.ok = parsed.get("ok", false)
			result.error = _localize_error(String(parsed.get("error", "")))
	_cleanup(script_path, out_path)
	return result


## Сообщения из Python-обвязки приходят по-русски — переводим известные префиксы.
static func _localize_error(err: String) -> String:
	for prefix in ["Тест не пройден", "RecursionError: бесконечная рекурсия — нет базового случая?"]:
		if err.begins_with(prefix):
			return Loc.t(prefix) + err.substr(prefix.length())
	return err


static func _pattern_check(code: String, safe: Dictionary) -> Dictionary:
	var re := RegEx.new()
	for pattern in safe.get("checks", []):
		re.compile(pattern)
		if re.search(code) == null:
			return {"ok": false, "error": Loc.t("Ошибка всё ещё в коде (проверка по шаблону: Python не найден)"), "method": "pattern"}
	if code.strip_edges() == String(safe.get("code", "")).strip_edges():
		return {"ok": false, "error": Loc.t("Код не изменён"), "method": "pattern"}
	return {"ok": true, "error": "", "method": "pattern"}


static func _cleanup(a: String, b: String) -> void:
	for p in [a, b]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
