class_name ThemeFactory
extends RefCounted
## Строит общую тему UI из Palette. Результат сохраняется в assets/ui/theme.tres
## скриптом tools/build_theme.gd (перегенерировать после правок здесь).
##
## Вариации типов (theme_type_variation):
##   Label:          TitleLabel, HeaderLabel, MonoLabel, DimLabel, StatLabel
##   Button:         AccentButton, MintButton, DangerButton, GhostButton
##   PanelContainer: CardPanel, GlassPanel, HudPanel
##   ProgressBar:    HPBar, XPBar, EnergyBar, MintBar

const THEME_PATH := "res://assets/ui/theme.tres"


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = Palette.FONT_TEXT
	t.default_font_size = 16

	var display := FontVariation.new()
	display.base_font = Palette.FONT_DISPLAY
	display.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}

	var italic := FontVariation.new()
	italic.base_font = Palette.FONT_TEXT
	italic.variation_transform = Transform2D(Vector2(1, 0.2), Vector2(0, 1), Vector2.ZERO)
	var bold_italic := FontVariation.new()
	bold_italic.base_font = Palette.FONT_TEXT_BOLD
	bold_italic.variation_transform = Transform2D(Vector2(1, 0.2), Vector2(0, 1), Vector2.ZERO)

	_labels(t, display)
	_buttons(t)
	_panels(t)
	_progress(t)
	_inputs(t)
	_rich_text(t, italic, bold_italic)
	_scrollbars(t)
	_tabs(t)
	_tooltip_and_dialogs(t)
	_form_controls(t)
	return t


static func _labels(t: Theme, display: Font) -> void:
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	_variation(t, "TitleLabel", "Label")
	t.set_font("font", "TitleLabel", display)
	t.set_font_size("font_size", "TitleLabel", 30)

	_variation(t, "HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", display)
	t.set_font_size("font_size", "HeaderLabel", 19)

	_variation(t, "MonoLabel", "Label")
	t.set_font("font", "MonoLabel", Palette.FONT_UI)
	t.set_font_size("font_size", "MonoLabel", 15)

	_variation(t, "StatLabel", "Label")
	t.set_font("font", "StatLabel", Palette.FONT_UI_BOLD)
	t.set_font_size("font_size", "StatLabel", 17)

	_variation(t, "DimLabel", "Label")
	t.set_color("font_color", "DimLabel", Palette.TEXT_DIM)
	t.set_font_size("font_size", "DimLabel", 14)


static func _buttons(t: Theme) -> void:
	t.set_stylebox("normal", "Button", Palette.box(Palette.PANEL_2, Palette.BORDER, 1, 8, 16, 9))
	t.set_stylebox("hover", "Button", Palette.box(Palette.PANEL_3, Palette.ACCENT, 1, 8, 16, 9))
	t.set_stylebox("pressed", "Button", Palette.box(Palette.ACCENT.darkened(0.45), Palette.ACCENT, 1, 8, 16, 9))
	t.set_stylebox("hover_pressed", "Button", Palette.box(Palette.ACCENT.darkened(0.35), Palette.ACCENT, 1, 8, 16, 9))
	t.set_stylebox("disabled", "Button", Palette.box(Palette.PANEL, Palette.BORDER.darkened(0.3), 1, 8, 16, 9))
	var focus := Palette.box(Color.TRANSPARENT, Palette.MINT.darkened(0.2), 1, 8)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_font("font", "Button", Palette.FONT_UI_BOLD)
	t.set_font_size("font_size", "Button", 15)
	t.set_color("font_color", "Button", Palette.TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Palette.TEXT)
	t.set_color("font_disabled_color", "Button", Palette.TEXT_FAINT)
	t.set_color("icon_normal_color", "Button", Palette.TEXT)
	t.set_color("icon_hover_color", "Button", Color.WHITE)
	t.set_color("icon_pressed_color", "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Palette.TEXT_FAINT)
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 20)

	_variation(t, "AccentButton", "Button")
	_button_colors(t, "AccentButton", Palette.ACCENT.darkened(0.15), Palette.ACCENT.lightened(0.25), Palette.ACCENT.lightened(0.1), Color.WHITE)

	_variation(t, "MintButton", "Button")
	_button_colors(t, "MintButton", Palette.MINT.darkened(0.25), Palette.MINT.lightened(0.3), Palette.MINT, Color("#04241D"))
	t.set_color("icon_normal_color", "MintButton", Color("#04241D"))
	t.set_color("icon_hover_color", "MintButton", Color("#04241D"))
	# Выключенная мятная кнопка = «уже выполнено»: читаемая, но спокойная
	t.set_stylebox("disabled", "MintButton", Palette.box(Color(Palette.MINT, 0.12), Color(Palette.MINT, 0.55), 1, 8, 18, 10))
	t.set_color("font_disabled_color", "MintButton", Palette.MINT)
	t.set_color("icon_disabled_color", "MintButton", Palette.MINT)

	_variation(t, "DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", Palette.box(Palette.PANEL_2, Palette.HP.darkened(0.4), 1, 8, 16, 9))
	t.set_stylebox("hover", "DangerButton", Palette.box(Palette.HP.darkened(0.7), Palette.HP, 1, 8, 16, 9))
	t.set_stylebox("pressed", "DangerButton", Palette.box(Palette.HP.darkened(0.5), Palette.HP, 1, 8, 16, 9))
	t.set_color("font_color", "DangerButton", Palette.HP)
	t.set_color("icon_normal_color", "DangerButton", Palette.HP)

	_variation(t, "GhostButton", "Button")
	var ghost := Palette.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 8, 10, 6)
	t.set_stylebox("normal", "GhostButton", ghost)
	t.set_stylebox("hover", "GhostButton", Palette.box(Color(Palette.PANEL_3, 0.7), Color.TRANSPARENT, 0, 8, 10, 6))
	t.set_stylebox("pressed", "GhostButton", Palette.box(Palette.PANEL_3, Color.TRANSPARENT, 0, 8, 10, 6))
	t.set_stylebox("disabled", "GhostButton", ghost)
	t.set_color("font_color", "GhostButton", Palette.TEXT_DIM)
	t.set_color("icon_normal_color", "GhostButton", Palette.TEXT_DIM)


static func _button_colors(t: Theme, type: String, base: Color, border: Color, hover: Color, font: Color) -> void:
	t.set_stylebox("normal", type, Palette.box(base, border.darkened(0.15), 1, 8, 18, 10))
	t.set_stylebox("hover", type, Palette.glow_box(hover, border, Color(hover, 0.35), 8, 8))
	t.set_stylebox("pressed", type, Palette.box(base.darkened(0.25), border, 1, 8, 18, 10))
	t.set_stylebox("disabled", type, Palette.box(base.darkened(0.6), Color(border, 0.2), 1, 8, 18, 10))
	var hover_sb: StyleBoxFlat = t.get_stylebox("hover", type)
	hover_sb.content_margin_left = 18
	hover_sb.content_margin_right = 18
	hover_sb.content_margin_top = 10
	hover_sb.content_margin_bottom = 10
	t.set_color("font_color", type, font)
	t.set_color("font_hover_color", type, font)
	t.set_color("font_pressed_color", type, font)
	t.set_color("font_focus_color", type, font)
	t.set_color("font_disabled_color", type, Color(font, 0.4))
	t.set_color("icon_normal_color", type, font)
	t.set_color("icon_hover_color", type, font)


static func _panels(t: Theme) -> void:
	var panel := Palette.box(Color(Palette.PANEL, 0.94), Palette.BORDER, 1, 14, 16, 14)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	_variation(t, "CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", Palette.box(Palette.PANEL_2, Palette.BORDER, 1, 12, 14, 12))

	_variation(t, "GlassPanel", "PanelContainer")
	var glass := Palette.box(Color(Palette.PANEL, 0.72), Color(Palette.ACCENT, 0.35), 1, 16, 18, 14)
	glass.shadow_color = Color(0, 0, 0, 0.35)
	glass.shadow_size = 12
	t.set_stylebox("panel", "GlassPanel", glass)

	_variation(t, "HudPanel", "PanelContainer")
	var hud := Palette.box(Color("#090913", 0.94), Palette.BORDER, 0, 0, 18, 8)
	hud.border_width_bottom = 1
	hud.border_color = Color(Palette.ACCENT, 0.35)
	hud.shadow_color = Color(0, 0, 0, 0.5)
	hud.shadow_size = 8
	t.set_stylebox("panel", "HudPanel", hud)

	var sep := StyleBoxLine.new()
	sep.color = Palette.BORDER
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = Palette.BORDER
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)


static func _progress(t: Theme) -> void:
	t.set_stylebox("background", "ProgressBar", Palette.box(Color("#0A0A16"), Palette.BORDER, 1, 6, 0, 0))
	t.set_stylebox("fill", "ProgressBar", Palette.box(Palette.ACCENT, Color.TRANSPARENT, 0, 6, 0, 0))
	t.set_font("font", "ProgressBar", Palette.FONT_UI_BOLD)
	t.set_font_size("font_size", "ProgressBar", 12)
	t.set_color("font_color", "ProgressBar", Palette.TEXT)
	t.set_color("font_outline_color", "ProgressBar", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "ProgressBar", 4)
	for pair in [["HPBar", Palette.HP], ["XPBar", Palette.ACCENT], ["EnergyBar", Palette.ENERGY], ["MintBar", Palette.MINT]]:
		_variation(t, pair[0], "ProgressBar")
		var fill := Palette.box(pair[1], pair[1].lightened(0.3), 0, 6, 0, 0)
		fill.shadow_color = Color(pair[1], 0.45)
		fill.shadow_size = 4
		t.set_stylebox("fill", pair[0], fill)


static func _inputs(t: Theme) -> void:
	for type in ["TextEdit", "LineEdit"]:
		t.set_stylebox("normal", type, Palette.box(Color("#0B0B18"), Palette.BORDER, 1, 8, 12, 10))
		t.set_stylebox("focus", type, Palette.box(Color("#0B0B18"), Palette.ACCENT, 1, 8, 12, 10))
		t.set_stylebox("read_only", type, Palette.box(Palette.PANEL, Palette.BORDER, 1, 8, 12, 10))
		t.set_font_size("font_size", type, 15)
		t.set_color("font_color", type, Palette.TEXT)
		t.set_color("font_placeholder_color", type, Palette.TEXT_FAINT)
		t.set_color("caret_color", type, Palette.MINT)
		t.set_color("selection_color", type, Color(Palette.ACCENT, 0.45))
	t.set_color("background_color", "TextEdit", Color(0, 0, 0, 0))
	t.set_color("current_line_color", "TextEdit", Color(1, 1, 1, 0.03))
	t.set_constant("line_spacing", "TextEdit", 5)


static func _rich_text(t: Theme, italic: Font, bold_italic: Font) -> void:
	t.set_font("normal_font", "RichTextLabel", Palette.FONT_TEXT)
	t.set_font("bold_font", "RichTextLabel", Palette.FONT_TEXT_BOLD)
	t.set_font("italics_font", "RichTextLabel", italic)
	t.set_font("bold_italics_font", "RichTextLabel", bold_italic)
	t.set_font("mono_font", "RichTextLabel", Palette.FONT_UI)
	for f in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		t.set_font_size(f, "RichTextLabel", 17)
	t.set_font_size("mono_font_size", "RichTextLabel", 15)
	t.set_color("default_color", "RichTextLabel", Color("#D2D2E6"))
	t.set_color("selection_color", "RichTextLabel", Color(Palette.ACCENT, 0.45))
	t.set_constant("line_separation", "RichTextLabel", 5)
	t.set_constant("table_h_separation", "RichTextLabel", 2)
	t.set_constant("table_v_separation", "RichTextLabel", 2)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())


static func _scrollbars(t: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		var track := Palette.box(Color(0, 0, 0, 0.25), Color.TRANSPARENT, 0, 4, 4, 4)
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		t.set_stylebox("grabber", type, Palette.box(Palette.PANEL_3, Color.TRANSPARENT, 0, 4, 4, 4))
		t.set_stylebox("grabber_highlight", type, Palette.box(Palette.ACCENT.darkened(0.3), Color.TRANSPARENT, 0, 4, 4, 4))
		t.set_stylebox("grabber_pressed", type, Palette.box(Palette.ACCENT, Color.TRANSPARENT, 0, 4, 4, 4))


static func _tabs(t: Theme) -> void:
	for type in ["TabContainer", "TabBar"]:
		var selected := Palette.box(Palette.PANEL, Palette.ACCENT, 0, 8, 20, 10)
		selected.border_width_bottom = 2
		selected.corner_radius_bottom_left = 0
		selected.corner_radius_bottom_right = 0
		t.set_stylebox("tab_selected", type, selected)
		t.set_stylebox("tab_unselected", type, Palette.box(Color(Palette.PANEL_2, 0.6), Color.TRANSPARENT, 0, 8, 20, 10))
		t.set_stylebox("tab_hovered", type, Palette.box(Palette.PANEL_3, Color.TRANSPARENT, 0, 8, 20, 10))
		t.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		t.set_font("font", type, Palette.FONT_UI_BOLD)
		t.set_font_size("font_size", type, 15)
		t.set_color("font_selected_color", type, Color.WHITE)
		t.set_color("font_unselected_color", type, Palette.TEXT_DIM)
		t.set_color("font_hovered_color", type, Palette.TEXT)
	t.set_stylebox("panel", "TabContainer", Palette.box(Color(Palette.PANEL, 0.94), Palette.BORDER, 1, 12, 18, 16))


static func _tooltip_and_dialogs(t: Theme) -> void:
	t.set_stylebox("panel", "TooltipPanel", Palette.box(Color("#0B0B18", 0.97), Color(Palette.ACCENT, 0.6), 1, 8, 12, 8))
	t.set_color("font_color", "TooltipLabel", Palette.TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)

	var border := Palette.box(Palette.PANEL, Palette.ACCENT, 1, 12, 0, 0)
	border.expand_margin_top = 34
	border.expand_margin_left = 6
	border.expand_margin_right = 6
	border.expand_margin_bottom = 6
	border.shadow_color = Color(0, 0, 0, 0.6)
	border.shadow_size = 20
	t.set_stylebox("embedded_border", "Window", border)
	t.set_stylebox("embedded_unfocused_border", "Window", border)
	t.set_font("title_font", "Window", Palette.FONT_UI_BOLD)
	t.set_font_size("title_font_size", "Window", 15)
	t.set_color("title_color", "Window", Palette.TEXT)
	t.set_constant("title_height", "Window", 34)
	t.set_stylebox("panel", "AcceptDialog", Palette.box(Palette.PANEL, Color.TRANSPARENT, 0, 12, 18, 14))


## OptionButton, PopupMenu, CheckBox/CheckButton, HSlider — для экрана настроек.
static func _form_controls(t: Theme) -> void:
	var popup := Palette.box(Color("#0B0B18", 0.98), Color(Palette.ACCENT, 0.5), 1, 8, 6, 6)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", Palette.box(Palette.ACCENT.darkened(0.4), Color.TRANSPARENT, 0, 6, 8, 4))
	t.set_font("font", "PopupMenu", Palette.FONT_UI)
	t.set_font_size("font_size", "PopupMenu", 14)
	t.set_color("font_color", "PopupMenu", Palette.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", Palette.TEXT_FAINT)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_constant("h_separation", "PopupMenu", 8)

	for type in ["CheckBox", "CheckButton"]:
		var empty := Palette.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 6, 4, 4)
		var hover := Palette.box(Color(Palette.PANEL_3, 0.6), Color.TRANSPARENT, 0, 6, 4, 4)
		for state in ["normal", "pressed", "disabled", "hover_pressed"]:
			t.set_stylebox(state, type, empty)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("hover_pressed", type, hover)
		t.set_font("font", type, Palette.FONT_TEXT)
		t.set_font_size("font_size", type, 15)
		t.set_color("font_color", type, Palette.TEXT)
		t.set_color("font_pressed_color", type, Palette.TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("icon_normal_color", type, Palette.ACCENT.lightened(0.2))
		t.set_color("icon_pressed_color", type, Palette.MINT)
		t.set_color("icon_hover_color", type, Color.WHITE)
		t.set_color("icon_hover_pressed_color", type, Palette.MINT)
		t.set_constant("h_separation", type, 10)

	var track := Palette.box(Color("#0A0A16"), Palette.BORDER, 1, 4, 0, 3)
	t.set_stylebox("slider", "HSlider", track)
	var fill := Palette.box(Palette.ACCENT, Color.TRANSPARENT, 0, 4, 0, 3)
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_hi := Palette.box(Palette.ACCENT.lightened(0.2), Color.TRANSPARENT, 0, 4, 0, 3)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)


static func _variation(t: Theme, name: String, base: String) -> void:
	t.set_type_variation(name, base)
