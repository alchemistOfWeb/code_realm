extends Control
## Лавка «Медный молот»: базовое снаряжение и оружие за золото (карты здесь не продаются).
## Наведение — примерка на героя, клик — выбор, «Купить» / «Купить и надеть». Вкладка «Продать» — 50% цены.

const MERCHANT_LOOK := {"gender": "male", "race": "dwarf", "skin": 1, "hair": "Hair_Long", "hair_color": 5, "beard": true, "outfit_variant": 1}
const MERCHANT_GEAR := {"outfit": {"body": "ranger", "arms": "ranger", "legs": "peasant", "feet": "ranger", "head": "", "shoulders": ""},
	"variants": {"ranger": 1, "peasant": 0}, "weapon": "Hammer_Small", "offhand": ""}
const GREETINGS := [
	"Заходи, путник! Сталь свежая, цены честные.",
	"Без доброго клинка в Шепчущую рощу не ходят.",
	"Щит — лучший друг того, кто не любит терять здоровье.",
	"Карты? Нет, карты ищи в сундуках. У меня — железо!",
]

var _category := "weapons"
var _tabs: HBoxContainer
var _grid: GridContainer
var _hero: HeroPreview
var _merchant: HeroPreview
var _gold: Label
var _details: VBoxContainer
var _selected: Dictionary = {}
var _selling := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameManager.world.flags["visited_shop"] = true
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)
	var back := Button.new()
	back.text = Loc.t("Назад")
	back.icon = Palette.icon("arrow-left")
	back.pressed.connect(EventBus.back)
	header.add_child(back)
	var title := Label.new()
	title.text = Loc.t("Лавка «Медный молот»")
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_gold = Label.new()
	_gold.theme_type_variation = &"StatLabel"
	_gold.add_theme_color_override("font_color", Palette.GOLD)
	_gold.add_theme_font_size_override("font_size", 20)
	header.add_child(_gold)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)

	# Торговец
	var left := PanelContainer.new()
	left.theme_type_variation = &"CardPanel"
	left.custom_minimum_size.x = 230
	body.add_child(left)
	var lbox := VBoxContainer.new()
	left.add_child(lbox)
	_merchant = HeroPreview.new()
	_merchant.custom_minimum_size = Vector2(210, 300)
	_merchant.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbox.add_child(_merchant)
	_merchant.show_custom(MERCHANT_LOOK, MERCHANT_GEAR, "Idle_Talking")
	var mname := Label.new()
	mname.text = Loc.t("Торин Медный Молот")
	mname.add_theme_font_override("font", Palette.FONT_UI_BOLD)
	mname.add_theme_color_override("font_color", Color("#E8C872"))
	mname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbox.add_child(mname)
	var say := Label.new()
	say.text = GREETINGS[randi() % GREETINGS.size()]
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	say.theme_type_variation = &"DimLabel"
	say.custom_minimum_size.x = 200
	lbox.add_child(say)

	# Товары
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 10)
	body.add_child(center)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	center.add_child(_tabs)
	for cat in ItemDatabase.CATEGORIES:
		_tabs.add_child(_tab_button(ItemDatabase.CATEGORIES[cat].name, cat))
	_tabs.add_child(_tab_button(Loc.t("Продать"), "sell"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	var gm := MarginContainer.new()
	gm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		gm.add_theme_constant_override("margin_" + side, 6)
	scroll.add_child(gm)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	gm.add_child(_grid)
	scroll.resized.connect(func(): _grid.columns = maxi(1, int((scroll.size.x - 12) / 146.0)))

	# Герой и детали
	var right := PanelContainer.new()
	right.theme_type_variation = &"CardPanel"
	right.custom_minimum_size.x = 290
	body.add_child(right)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 8)
	right.add_child(rbox)
	_hero = HeroPreview.new()
	_hero.custom_minimum_size = Vector2(270, 250)
	rbox.add_child(_hero)
	_hero.show_player()
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 6)
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rbox.add_child(_details)

	GameManager.player_changed.connect(_refresh_gold)
	_refresh_gold()
	_show_category("weapons")


func on_resume() -> void:
	_hero.show_player()
	_refresh_gold()
	_show_category(_category)


func _tab_button(text: String, cat: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.set_meta("cat", cat)
	b.pressed.connect(_show_category.bind(cat))
	return b


func _refresh_gold() -> void:
	_gold.text = Loc.t("Золото: %d") % GameManager.player_data.gold


func _show_category(cat: String) -> void:
	_category = cat
	_selling = cat == "sell"
	for b in _tabs.get_children():
		b.button_pressed = b.get_meta("cat") == cat
	for c in _grid.get_children():
		c.queue_free()
	var items: Array = []
	if _selling:
		for id in GameManager.player_data.inventory:
			items.append(ItemDatabase.get_item(id))
		if items.is_empty():
			var empty := Label.new()
			empty.text = Loc.t("В инвентаре нечего продать. Надетые вещи сначала сними во вкладке «Снаряжение».")
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty.custom_minimum_size.x = 360
			empty.theme_type_variation = &"DimLabel"
			_grid.add_child(empty)
	else:
		items = ItemDatabase.shop_items(cat)
	for it in items:
		var price := ItemDatabase.sell_price(it) if _selling else int(it.price)
		var tile := ItemTile.make(it, ("+%d" if _selling else "%d") % price + " ◉", Vector2(136, 150))
		if not _selling:
			var affordable: bool = GameManager.player_data.gold >= price
			var owned := GameManager.owns_item(it.id)
			tile.set_sub(("✓ " if owned else "") + "%d ◉" % price, Palette.GOLD if affordable else Palette.HP)
		else:
			tile.set_sub("+%d ◉" % price, Palette.GOLD)
		tile.pressed.connect(_select.bind(it))
		tile.mouse_entered.connect(func(): _hero.try_item(it))
		tile.mouse_exited.connect(func(): _hero.try_item(_selected) if not _selected.is_empty() else _hero.show_player())
		_grid.add_child(tile)
	_select({})


func _select(it: Dictionary) -> void:
	_selected = it
	for c in _details.get_children():
		c.queue_free()
	if it.is_empty():
		_hero.show_player()
		var hint := Label.new()
		hint.text = Loc.t("Выбери предмет: наведи курсор, чтобы примерить.") if not _selling else Loc.t("Выбери предмет для продажи.")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.theme_type_variation = &"DimLabel"
		_details.add_child(hint)
		return
	_hero.try_item(it)
	_details.add_child(ItemTile.tooltip_for(it))
	var current := ItemDatabase.get_item(GameManager.equipped(it.slot))
	if not _selling and not current.is_empty() and current.id != it.id:
		var cmp := Label.new()
		cmp.text = Loc.t("Сейчас надето: %s") % current.name
		cmp.theme_type_variation = &"DimLabel"
		cmp.add_theme_font_size_override("font_size", 12)
		_details.add_child(cmp)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_details.add_child(row)
	if _selling:
		var sell := Button.new()
		sell.text = Loc.t("Продать за %d") % ItemDatabase.sell_price(it)
		sell.theme_type_variation = &"AccentButton"
		sell.pressed.connect(func():
			var gold := GameManager.sell_item(it.id)
			if gold > 0:
				Audio.play("coins")
				EventBus.notify(Loc.t("Продано: %s (+%d золота)") % [it.name, gold], "success")
			_show_category("sell"))
		row.add_child(sell)
		return
	var reason := GameManager.buy_block_reason(it.id)
	var buy := Button.new()
	buy.text = Loc.t("Купить за %d") % it.price
	buy.disabled = reason != ""
	buy.tooltip_text = reason
	buy.pressed.connect(_buy.bind(it, false))
	row.add_child(buy)
	var buy_eq := Button.new()
	buy_eq.text = Loc.t("Купить и надеть")
	buy_eq.theme_type_variation = &"AccentButton"
	buy_eq.disabled = reason != ""
	buy_eq.pressed.connect(_buy.bind(it, true))
	row.add_child(buy_eq)
	if int(it.get("level", 1)) > int(GameManager.player_data.level):
		var warn := Label.new()
		warn.text = Loc.t("Рекомендуемый уровень: %d") % int(it.level)
		warn.add_theme_color_override("font_color", Palette.ENERGY)
		warn.add_theme_font_size_override("font_size", 12)
		_details.add_child(warn)


func _buy(it: Dictionary, equip_now: bool) -> void:
	if not GameManager.buy_item(it.id):
		EventBus.notify(GameManager.buy_block_reason(it.id), "error")
		return
	Audio.play("coins")
	if equip_now:
		GameManager.equip(it.id)
		Audio.play("cloth")
	EventBus.notify(Loc.t("Куплено: %s") % it.name, "success")
	SaveSystem.save_all()
	_show_category(_category)
