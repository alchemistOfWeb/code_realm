class_name MarkdownBBCode
extends RefCounted
## Конвертер markdown → BBCode для RichTextLabel.
## Поддержка: заголовки, **жирный**, *курсив*, _курсив_, ~~зачёркнутый~~, `код`, ```блоки```,
## списки (вложенные, нумерованные, чекбоксы), > цитаты, таблицы, ---, [ссылки](url).

const CODE_BG := "#0A0A16"
const TABLE_HEAD_BG := "#23234A"
const TABLE_ROW_BG := "#15152E,#1A1A38"
const TABLE_BORDER := "#2C2C58"
const KEYWORD_COLOR := "#C792EA"
const STRING_COLOR := "#C3E88D"
const NUMBER_COLOR := "#F78C6C"
const COMMENT_COLOR := "#5C6390"

static var _re: Dictionary = {}


static func _init_regex() -> void:
	if not _re.is_empty():
		return
	var patterns := {
		"link": "\\[lb\\]([^\\]]+)\\]\\(([^)\\s]+)\\)",
		"bold": "\\*\\*(.+?)\\*\\*",
		"bold2": "(?<!\\w)__(.+?)__(?!\\w)",
		"italic": "(?<![\\w*])\\*(?![\\s*])(.+?)(?<![\\s*])\\*(?![\\w*])",
		"italic2": "(?<!\\w)_(?![\\s_])(.+?)(?<![\\s_])_(?!\\w)",
		"strike": "~~(.+?)~~",
		"list": "^(\\s*)([-*+]|\\d+[.)])\\s+(.*)$",
		"table_sep": "^\\|?[\\s|:-]+\\|?$",
		"tok_hash": "(#.*$)|(\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*')|\\b(def|class|return|if|elif|else|for|while|in|import|from|as|with|try|except|finally|raise|async|await|yield|lambda|not|and|or|is|None|True|False|pass|break|continue|self|global|nonlocal|del|assert|func|var|const|extends|signal|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|INDEX|GROUP|ORDER|BY|HAVING|LIMIT|AND|OR|NOT|NULL|PRIMARY|KEY|REFERENCES|BEGIN|COMMIT|ROLLBACK)\\b|(\\b\\d+(?:\\.\\d+)?\\b)",
		"tok_sql": "(--.*$)|(\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*')|\\b(def|class|return|if|elif|else|for|while|in|import|from|as|with|try|except|finally|raise|async|await|yield|lambda|not|and|or|is|None|True|False|pass|break|continue|self|global|nonlocal|del|assert|func|var|const|extends|signal|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|INDEX|GROUP|ORDER|BY|HAVING|LIMIT|AND|OR|NOT|NULL|PRIMARY|KEY|REFERENCES|BEGIN|COMMIT|ROLLBACK)\\b|(\\b\\d+(?:\\.\\d+)?\\b)",
		"tok_slash": "(//.*$)|(\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*')|\\b(def|class|return|if|elif|else|for|while|in|import|from|as|with|try|except|finally|raise|async|await|yield|lambda|not|and|or|is|None|True|False|pass|break|continue|self|global|nonlocal|del|assert|func|var|const|extends|signal|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|ON|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|INDEX|GROUP|ORDER|BY|HAVING|LIMIT|AND|OR|NOT|NULL|PRIMARY|KEY|REFERENCES|BEGIN|COMMIT|ROLLBACK)\\b|(\\b\\d+(?:\\.\\d+)?\\b)",
	}
	for key in patterns:
		var r := RegEx.new()
		var err := r.compile(patterns[key])
		if err != OK:
			push_error("MarkdownBBCode: bad regex " + key)
		_re[key] = r


static func to_bbcode(md: String, accent: Color = Palette.ACCENT) -> String:
	_init_regex()
	var acc := Palette.hex(accent)
	var out := PackedStringArray()
	var lines := md.replace("\r", "").split("\n")
	var i := 0
	while i < lines.size():
		var line: String = lines[i]
		var s := line.strip_edges()

		# Блок кода
		if s.begins_with("```") or s.begins_with("~~~"):
			var fence := s.substr(0, 3)
			var lang := s.substr(3).strip_edges().to_lower()
			var code := PackedStringArray()
			i += 1
			while i < lines.size() and not lines[i].strip_edges().begins_with(fence):
				code.append(lines[i])
				i += 1
			i += 1
			out.append(_code_block(code, lang))
			continue

		# Таблица
		if s.begins_with("|"):
			var rows: Array = []
			while i < lines.size() and lines[i].strip_edges().begins_with("|"):
				rows.append(lines[i].strip_edges())
				i += 1
			out.append(_table(rows, acc))
			continue

		i += 1
		if s.begins_with("<!--") and s.ends_with("-->"):
			continue   # служебные комментарии (quiz и т.п.) не показываем
		if s == "":
			out.append("")
		elif s == "---" or s == "***" or s == "___":
			out.append("[center][color=%s]─────────────  ◆  ─────────────[/color][/center]" % TABLE_BORDER)
		elif s.begins_with("#"):
			var level := 0
			while level < s.length() and s[level] == "#":
				level += 1
			var text := s.substr(level).strip_edges()
			var size: int = [0, 26, 23, 20, 18, 17, 16][mini(level, 6)]
			out.append("[font_size=%d][b][color=%s]%s[/color][/b][/font_size]" % [size, acc, _inline(text, acc)])
		elif s.begins_with(">"):
			var text := s.trim_prefix(">").strip_edges()
			out.append("[indent][color=#A4A4CC][i]┃ %s[/i][/color][/indent]" % _inline(text, acc))
		else:
			var m: RegExMatch = _re.list.search(line)
			if m:
				var depth := mini(int(m.get_string(1).replace("\t", "    ").length() / 2.0), 4)
				var marker := m.get_string(2)
				var text := m.get_string(3)
				var bullet := "•" if marker in ["-", "*", "+"] else marker
				if text.begins_with("[ ] "):
					bullet = "☐"
					text = text.substr(4)
				elif text.begins_with("[x] ") or text.begins_with("[X] "):
					bullet = "☑"
					text = text.substr(4)
				var item := "[color=%s]%s[/color] %s" % [acc, bullet, _inline(text, acc)]
				for _d in depth + 1:
					item = "[indent]" + item + "[/indent]"
				out.append(item)
			else:
				out.append(_inline(s, acc))
	return "\n".join(out)


static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


## Инлайн-разметка. Код в `...` сначала заменяется плейсхолдерами,
## чтобы **`code`** и подобные комбинации работали корректно.
static func _inline(text: String, acc: String) -> String:
	var codes: Array[String] = []
	var parts := text.split("`")
	var n := parts.size()
	var buf := ""
	for k in n:
		var unmatched := n % 2 == 0 and k == n - 1
		if k % 2 == 1 and not unmatched:
			buf += "\u0001%d\u0002" % codes.size()
			codes.append(parts[k])
		else:
			if unmatched:
				buf += "`"
			buf += parts[k]
	buf = _format(_esc(buf), acc)
	for idx in codes.size():
		buf = buf.replace("\u0001%d\u0002" % idx, "[code][color=#7FDBCA]%s[/color][/code]" % _esc(codes[idx]))
	return buf


static func _format(t: String, _acc: String) -> String:
	t = _re.link.sub(t, "[url=$2][color=#4A9EFF][u]$1[/u][/color][/url]", true)
	t = _re.bold.sub(t, "[b][color=#FFFFFF]$1[/color][/b]", true)
	t = _re.bold2.sub(t, "[b][color=#FFFFFF]$1[/color][/b]", true)
	t = _re.italic.sub(t, "[i]$1[/i]", true)
	t = _re.italic2.sub(t, "[i][color=#A8A8CC]$1[/color][/i]", true)
	t = _re.strike.sub(t, "[s]$1[/s]", true)
	return t


static func _code_block(code: PackedStringArray, lang: String = "") -> String:
	var tokenizer: RegEx = _re.tok_hash
	if lang in ["sql", "postgresql", "psql"]:
		tokenizer = _re.tok_sql
	elif lang in ["js", "javascript", "ts", "typescript", "c", "cpp", "c++", "csharp", "cs", "java", "go", "rust", "glsl", "gdshader", "hlsl", "json"]:
		tokenizer = _re.tok_slash
	var body := PackedStringArray()
	for line in code:
		body.append(_highlight(line, tokenizer))
	return "[table=1][cell bg=%s padding=14,10,14,10][code]%s[/code][/cell][/table]" % [CODE_BG, "\n".join(body)]


## Простейшая подсветка: комментарии, строки, ключевые слова, числа.
static func _highlight(line: String, tokenizer: RegEx) -> String:
	var out := ""
	var pos := 0
	for m in tokenizer.search_all(line):
		out += "[color=#D6DEEB]%s[/color]" % _esc(line.substr(pos, m.get_start() - pos))
		var token := _esc(m.get_string())
		var color := NUMBER_COLOR
		if m.get_string(1) != "":
			color = COMMENT_COLOR
		elif m.get_string(2) != "":
			color = STRING_COLOR
		elif m.get_string(3) != "":
			color = KEYWORD_COLOR
		out += "[color=%s]%s[/color]" % [color, token]
		pos = m.get_end()
	out += "[color=#D6DEEB]%s[/color]" % _esc(line.substr(pos))
	return out


static func _table(rows: Array, acc: String) -> String:
	var parsed: Array = []
	var has_header := rows.size() > 1 and _re.table_sep.search(rows[1]) != null
	var cols := 0
	for idx in rows.size():
		var row: String = rows[idx]
		if idx == 1 and has_header:
			continue
		var cells := Array(row.trim_prefix("|").trim_suffix("|").split("|"))
		cols = maxi(cols, cells.size())
		parsed.append(cells)
	if cols == 0:
		return ""
	var out := "[table=%d]" % cols
	for r in parsed.size():
		var cells: Array = parsed[r]
		for c in cols:
			var text: String = cells[c].strip_edges() if c < cells.size() else ""
			if r == 0 and has_header:
				out += "[cell bg=%s border=%s padding=8,6,8,6][b][color=%s]%s[/color][/b][/cell]" % [TABLE_HEAD_BG, TABLE_BORDER, acc, _inline(text, acc)]
			else:
				out += "[cell bg=%s border=%s padding=8,4,8,4]%s[/cell]" % [TABLE_ROW_BG, TABLE_BORDER, _inline(text, acc)]
	return out + "[/table]"
