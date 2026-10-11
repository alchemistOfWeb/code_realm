extends Node
## Настройки приложения: окно, разрешение, масштаб интерфейса, VSync, громкость.
## Хранятся в user://settings.cfg (отдельно от игрового прогресса).
##
## Базовое разрешение интерфейса — 1280×720 (project.godot), stretch = canvas_items/expand:
## в большем окне UI масштабируется, на широком экране получает больше места.

signal changed(key: String)

const PATH := "user://settings.cfg"
const SECTION := "settings"
const MIN_WINDOW := Vector2i(960, 540)

## Пресеты разрешений окна (в списке остаются только помещающиеся на экран)
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1024, 576), Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1366, 768),
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const WINDOW_MODES := {"windowed": "В окне", "maximized": "Развёрнуто", "fullscreen": "Полный экран"}

const DEFAULTS := {
	"window_mode": "windowed",
	"resolution": "auto",          # "auto" или "1280x720"
	"ui_scale": 1.0,               # дополнительный множитель масштаба интерфейса
	"vsync": true,
	"master_volume": 0.8,          # 0..1
	"music_volume": 0.45,
	"sfx_volume": 0.75,
	"music_enabled": true,
	"ui_sounds": true,
}

var values: Dictionary = DEFAULTS.duplicate()


## Действия ввода экспедиции (регистрируются в коде, чтобы не править project.godot вручную).
const INPUT_ACTIONS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E], "pause": [KEY_SPACE], "sprint": [KEY_SHIFT],
}


func _ready() -> void:
	_register_input()
	load_settings()
	_apply_startup.call_deferred()


func _register_input() -> void:
	for action in INPUT_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in INPUT_ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _apply_startup() -> void:
	apply_window()
	apply_ui_scale()
	apply_vsync()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	save_settings()
	match key:
		"window_mode", "resolution":
			apply_window()
		"ui_scale":
			apply_ui_scale()
		"vsync":
			apply_vsync()
	changed.emit(key)


func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate()
	save_settings()
	_apply_startup()
	for key in values:
		changed.emit(key)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in DEFAULTS:
		var v = cfg.get_value(SECTION, key, DEFAULTS[key])
		if typeof(v) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and v is int):
			values[key] = v


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value(SECTION, key, values[key])
	cfg.save(PATH)


# ---------------------------------------------------------------- Окно

## Игра запущена внутри вкладки «Game» редактора — размером окна управляет редактор.
func is_embedded() -> bool:
	return Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor")


## Доступная область экрана (без панели задач).
func usable_screen_rect() -> Rect2i:
	var screen := DisplayServer.window_get_current_screen()
	var rect := DisplayServer.screen_get_usable_rect(screen)
	if rect.size.x <= 0 or rect.size.y <= 0:   # headless / нет данных об экране
		rect = Rect2i(0, 0, 1920, 1080)
	return rect


## Разрешения, которые помещаются на текущий экран вместе с рамкой окна.
func available_resolutions() -> Array[Vector2i]:
	var usable := usable_screen_rect().size
	var result: Array[Vector2i] = []
	for r in RESOLUTIONS:
		if r.x <= usable.x and r.y + 40 <= usable.y:
			result.append(r)
	if result.is_empty():
		result.append(RESOLUTIONS[0])
	return result


## Самое большое разрешение, которое комфортно помещается на экран.
func auto_resolution() -> Vector2i:
	var usable := usable_screen_rect().size
	var best := Vector2i(mini(usable.x - 40, 1280), mini(usable.y - 80, 720))
	for r in RESOLUTIONS:
		if r.x <= usable.x - 20 and r.y + 40 <= usable.y:   # +40 — заголовок окна
			best = r
	return best


func current_resolution() -> Vector2i:
	var res: String = get_value("resolution")
	if res == "auto" or not "x" in res:
		return auto_resolution()
	var parts := res.split("x")
	return Vector2i(parts[0].to_int(), parts[1].to_int())


static func resolution_to_string(r: Vector2i) -> String:
	return "%dx%d" % [r.x, r.y]


func apply_window() -> void:
	if is_embedded() or DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	window.min_size = MIN_WINDOW
	match get_value("window_mode"):
		"fullscreen":
			window.mode = Window.MODE_FULLSCREEN
		"maximized":
			window.mode = Window.MODE_MAXIMIZED
		_:
			window.mode = Window.MODE_WINDOWED
			var usable := usable_screen_rect()
			var target := current_resolution()
			target.x = mini(target.x, usable.size.x)
			target.y = mini(target.y, usable.size.y - 40)
			window.size = target
			# Центрируем с учётом заголовка окна
			var title_h := 31
			window.position = usable.position + Vector2i((usable.size.x - target.x) / 2, maxi(title_h, (usable.size.y - target.y + title_h) / 2))


func apply_ui_scale() -> void:
	get_tree().root.content_scale_factor = clampf(float(get_value("ui_scale")), 0.6, 2.0)


func apply_vsync() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("vsync") else DisplayServer.VSYNC_DISABLED)
