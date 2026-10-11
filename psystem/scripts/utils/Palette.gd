class_name Palette
extends RefCounted
## Цветовая схема и общие ресурсы UI.

const BG := Color("#0D0D1A")
const PANEL := Color("#13132A")
const PANEL_2 := Color("#1A1A38")
const PANEL_3 := Color("#23234A")
const BORDER := Color("#2C2C58")
const ACCENT := Color("#7B68EE")
const MINT := Color("#00D4AA")
const HP := Color("#FF6B6B")
const ENERGY := Color("#FFD700")
const PURPLE := Color("#9B59B6")
const GOLD := Color("#F5C542")
const TEXT := Color("#E6E6F2")
const TEXT_DIM := Color("#8C8CB0")
const TEXT_FAINT := Color("#55557A")
const CODE := Color("#7FDBCA")

const RARITY_COLORS := {
	"common": Color("#9AA0A6"),
	"uncommon": Color("#2ECC71"),
	"rare": Color("#4A9EFF"),
	"legendary": Color("#F5C542"),
}

const FONT_UI := preload("res://assets/fonts/JetBrainsMono-Regular.ttf")
const FONT_UI_BOLD := preload("res://assets/fonts/JetBrainsMono-Bold.ttf")
const FONT_TEXT := preload("res://assets/fonts/Inter-Regular.ttf")
const FONT_TEXT_SEMI := preload("res://assets/fonts/Inter-SemiBold.ttf")
const FONT_TEXT_BOLD := preload("res://assets/fonts/Inter-Bold.ttf")
const FONT_DISPLAY := preload("res://assets/fonts/Unbounded.ttf")


static func icon(icon_name: String) -> Texture2D:
	var path := "res://assets/icons/%s.svg" % icon_name
	if ResourceLoader.exists(path):
		return load(path)
	return load("res://assets/icons/circle-dot.svg")


## Иконка game-icons.net (assets/icons/game, CC BY 3.0).
static func game_icon(icon_name: String) -> Texture2D:
	var path := "res://assets/icons/game/%s.svg" % icon_name
	if ResourceLoader.exists(path):
		return load(path)
	return load("res://assets/icons/game/card-random.svg")


static var _italic: FontVariation


## Наклонный (синтетический курсив) Inter.
static func italic_font() -> Font:
	if _italic == null:
		_italic = FontVariation.new()
		_italic.base_font = FONT_TEXT
		_italic.variation_transform = Transform2D(Vector2(1, 0.2), Vector2(0, 1), Vector2.ZERO)
	return _italic


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w: int = 0, radius: int = 10,
		pad_h: float = 12.0, pad_v: float = 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = true
	return sb


static func glow_box(bg: Color, border: Color, glow: Color, glow_size: int = 10, radius: int = 10) -> StyleBoxFlat:
	var sb := box(bg, border, 2, radius)
	sb.shadow_color = glow
	sb.shadow_size = glow_size
	return sb
