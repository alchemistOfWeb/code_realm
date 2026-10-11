extends SceneTree
## Генерирует assets/ui/theme.tres из ThemeFactory.
## Запуск: Godot --headless --path <project> --script res://tools/build_theme.gd

func _init() -> void:
	var theme := ThemeFactory.build()
	var err := ResourceSaver.save(theme, ThemeFactory.THEME_PATH)
	print("Theme saved to %s: %s" % [ThemeFactory.THEME_PATH, error_string(err)])
	quit(0 if err == OK else 1)
