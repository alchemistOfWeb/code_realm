class_name Loc
extends RefCounted
## Локализация. Исходный язык — русский (строки в коде и сценах), перевод — locale/en.json (русский → английский).
##
## Control/Label3D переводят свой text автоматически (auto_translate), поэтому простые строки можно
## присваивать как есть. Строки с подстановкой (%d, %s) и склейкой нужно переводить ДО форматирования:
##     label.text = Loc.t("Этаж %d") % n
## Поля данных (JSON): для английского берётся поле <key>_en, если оно есть — Loc.f(dict, "name").

const LANGS := {"ru": "Русский", "en": "English"}
const EN_PATH := "res://locale/en.json"

static var _loaded := false
static var _lang := "ru"


static func setup(lang_code: String) -> void:
	if not _loaded:
		_loaded = true
		var data = JSON.parse_string(FileAccess.get_file_as_string(EN_PATH)) if FileAccess.file_exists(EN_PATH) else {}
		if data is Dictionary:
			var tr_en := Translation.new()
			tr_en.locale = "en"
			for key in data:
				if String(data[key]) != "":
					tr_en.add_message(key, data[key])
			TranslationServer.add_translation(tr_en)
	_lang = lang_code if LANGS.has(lang_code) else "ru"
	TranslationServer.set_locale(_lang)


static func lang() -> String:
	return _lang


static func is_en() -> bool:
	return _lang == "en"


## Перевод строки (ключ — русский текст).
static func t(text: String) -> String:
	if _lang == "ru":
		return text
	return String(TranslationServer.translate(text))


## Локализованное поле словаря данных: d[key + "_en"] для английского, иначе d[key].
static func f(d: Dictionary, key: String, fallback: String = "") -> String:
	if _lang == "en":
		var en = d.get(key + "_en", null)
		if en != null and String(en) != "":
			return String(en)
		var src := String(d.get(key, fallback))
		return t(src)
	return String(d.get(key, fallback))


## Копия словаря с подставленными английскими полями (для кэшей данных: карты, враги, предметы).
static func localized(d: Dictionary, keys: Array) -> Dictionary:
	if _lang == "ru":
		return d
	var copy := d.duplicate(true)
	for key in keys:
		if d.has(key):
			copy[key] = f(d, key)
	return copy


## Склонение числительных: plural(5, "карта", "карты", "карт"). Для английского — 1 / остальное.
static func plural(n: int, one: String, few: String, many: String) -> String:
	if _lang == "en":
		return t(one) if n == 1 else t(many)
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return one
	if m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14):
		return few
	return many
