extends Node
## Звук: шины Music/SFX, звуки интерфейса, джинглы, фоновая музыка (плейлист).
##
## Кнопки озвучиваются автоматически (клик + тихий hover) через SceneTree.node_added.
## Своё поведение для кнопки — meta "sfx": имя звука или "" (без звука).
## Кнопки с именем BackButton молчат — звук «назад» играет Main при возврате.

signal track_changed(title: String)

const SFX := {
	"click": preload("res://assets/audio/ui/click.ogg"),
	"hover": preload("res://assets/audio/ui/hover.ogg"),
	"back": preload("res://assets/audio/ui/back.ogg"),
	"open": preload("res://assets/audio/ui/open.ogg"),
	"confirm": preload("res://assets/audio/ui/confirm.ogg"),
	"error": preload("res://assets/audio/ui/error.ogg"),
	"toggle": preload("res://assets/audio/ui/toggle.ogg"),
	"select": preload("res://assets/audio/ui/select.ogg"),
	"notify": preload("res://assets/audio/ui/notify.ogg"),
	"drop": preload("res://assets/audio/ui/drop.ogg"),
	"whoosh": preload("res://assets/audio/ui/whoosh.ogg"),
	"levelup": preload("res://assets/audio/jingles/levelup.ogg"),
	"reward": preload("res://assets/audio/jingles/reward.ogg"),
	"fanfare": preload("res://assets/audio/jingles/fanfare_reward.ogg"),
	"card_flip": preload("res://assets/audio/rpg/card_flip.ogg"),
	"scroll_open": preload("res://assets/audio/rpg/scroll_open.ogg"),
	"cloth": preload("res://assets/audio/rpg/cloth.ogg"),
	"coins": preload("res://assets/audio/rpg/coins.ogg"),
	"chest_latch": preload("res://assets/audio/rpg/chest_latch.ogg"),
	"chest_creak": preload("res://assets/audio/rpg/chest_creak.ogg"),
	"book_place": preload("res://assets/audio/rpg/book_place.ogg"),
	"hit": preload("res://assets/audio/combat/hit.ogg"),
	"hit_heavy": preload("res://assets/audio/combat/hit_heavy.ogg"),
	"block": preload("res://assets/audio/combat/block.ogg"),
	"spell": preload("res://assets/audio/combat/spell.ogg"),
	"destroy": preload("res://assets/audio/combat/destroy.ogg"),
	"slash": preload("res://assets/audio/combat/slash.ogg"),
	"draw": preload("res://assets/audio/combat/draw.ogg"),
	"gate": preload("res://assets/audio/combat/gate.ogg"),
	"gear": preload("res://assets/audio/combat/gear.ogg"),
	"step": preload("res://assets/audio/combat/step_0.ogg"),
}
const STEPS := [
	preload("res://assets/audio/combat/step_0.ogg"), preload("res://assets/audio/combat/step_1.ogg"),
	preload("res://assets/audio/combat/step_2.ogg"), preload("res://assets/audio/combat/step_3.ogg"),
	preload("res://assets/audio/combat/step_4.ogg"),
]
const BATTLE_MUSIC := preload("res://assets/audio/music/battle_loop.ogg")
## Громкость отдельных звуков (дБ)
const SFX_VOLUME_DB := {"step": -16.0, "gear": -6.0, "hover": -14.0, "click": -4.0, "levelup": 0.0, "fanfare": -2.0, "notify": -6.0, "whoosh": -8.0, "card_flip": -2.0}

const MUSIC := [
	{"title": "Slow Stride — isaiah658", "stream": preload("res://assets/audio/music/slow_stride.ogg")},
	{"title": "Underwater Theme II — Cleyton Kauffman", "stream": preload("res://assets/audio/music/underwater_theme_ii.ogg")},
	{"title": "Heavenly Loop — isaiah658", "stream": preload("res://assets/audio/music/heavenly_loop.ogg")},
]
const MUSIC_DB := -6.0
const POOL_SIZE := 8
const HOVER_COOLDOWN_MS := 60

var _music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _pool_index := 0
var _track := -1
var _music_tween: Tween
var _last_hover_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.finished.connect(next_track)
	add_child(_music)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	apply_volumes()
	Settings.changed.connect(_on_setting_changed)
	get_tree().node_added.connect(_on_node_added)
	_track = randi() % MUSIC.size() - 1
	if Settings.get_value("music_enabled"):
		next_track.call_deferred()


# ---------------------------------------------------------------- Эффекты

## Проиграть звук по имени из SFX. pitch_jitter — случайный разброс высоты (0.05 = ±5%).
func play(sfx_name: String, pitch_jitter: float = 0.04) -> void:
	if not SFX.has(sfx_name) or not Settings.get_value("ui_sounds"):
		return
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	p.stream = SFX[sfx_name]
	p.volume_db = SFX_VOLUME_DB.get(sfx_name, 0.0)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## Шаг (случайный из набора, тихо).
func play_step() -> void:
	if not Settings.get_value("ui_sounds"):
		return
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % POOL_SIZE
	p.stream = STEPS.pick_random()
	p.volume_db = -18.0
	p.pitch_scale = randf_range(0.9, 1.1)
	p.play()


# ---------------------------------------------------------------- Временная музыка (бой)

var _music_stack: Array = []   # сохранённые [stream, position, track]


## Включить временную музыку (например, боевую) с возвратом через pop_music().
func push_music(stream: AudioStream) -> void:
	_music_stack.append([_music.stream, _music.get_playback_position(), _track, _music.playing])
	if not Settings.get_value("music_enabled"):
		return
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()   # не трогаем общий ресурс плейлиста
		stream.loop = true
	_music.stream = stream
	_music.volume_db = -30.0
	_music.play()
	_fade_music_to(MUSIC_DB, 1.0)


func pop_music() -> void:
	if _music_stack.is_empty():
		return
	var prev: Array = _music_stack.pop_back()
	_music.stop()
	if not Settings.get_value("music_enabled"):
		return
	if prev[0] != null and prev[3]:
		_music.stream = prev[0]
		_track = prev[2]
		_music.volume_db = -30.0
		_music.play(prev[1])
		_fade_music_to(MUSIC_DB, 1.5)
	else:
		next_track()


func play_hover() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hover_ms < HOVER_COOLDOWN_MS:
		return
	_last_hover_ms = now
	play("hover", 0.08)


## Джингл/фанфара поверх музыки: музыка приглушается на время звучания.
func play_jingle(sfx_name: String) -> void:
	play(sfx_name, 0.0)
	if _music.playing and SFX.has(sfx_name):
		var length: float = SFX[sfx_name].get_length()
		_fade_music_to(MUSIC_DB - 18.0, 0.3)
		get_tree().create_timer(maxf(length - 0.5, 0.8)).timeout.connect(_restore_music)


func _restore_music() -> void:
	if _music.playing:
		_fade_music_to(MUSIC_DB, 1.5)


# ---------------------------------------------------------------- Музыка

func next_track() -> void:
	if not Settings.get_value("music_enabled"):
		return
	_track = (_track + 1) % MUSIC.size()
	_music.stream = MUSIC[_track].stream
	_music.volume_db = -40.0
	_music.play()
	_fade_music_to(MUSIC_DB, 2.5)
	track_changed.emit(MUSIC[_track].title)


func current_track_title() -> String:
	return MUSIC[_track].title if _track >= 0 and _music.playing else ""


func set_music_enabled(on: bool) -> void:
	Settings.set_value("music_enabled", on)


func _start_or_stop_music() -> void:
	if Settings.get_value("music_enabled"):
		if not _music.playing:
			next_track()
	elif _music.playing:
		_fade_music_to(-40.0, 0.8)
		_music_tween.tween_callback(_music.stop)
		track_changed.emit("")


func _fade_music_to(db: float, duration: float) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", db, duration)


# ---------------------------------------------------------------- Громкость

func apply_volumes() -> void:
	_set_bus_volume("Master", Settings.get_value("master_volume"))
	_set_bus_volume("Music", Settings.get_value("music_volume"))
	_set_bus_volume("SFX", Settings.get_value("sfx_volume"))


func _set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func _ensure_bus(bus: String) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus)
	AudioServer.set_bus_send(idx, "Master")


func _on_setting_changed(key: String) -> void:
	if key.ends_with("_volume"):
		apply_volumes()
	elif key == "music_enabled":
		_start_or_stop_music()


# ---------------------------------------------------------------- Автоозвучка UI

func _on_node_added(node: Node) -> void:
	# reparent() снова вызывает node_added — не подключаемся дважды
	if node.has_meta("_ui_sfx"):
		return
	node.set_meta("_ui_sfx", true)
	if node is BaseButton:
		node.pressed.connect(_on_button_pressed.bind(node))
		node.mouse_entered.connect(_on_button_hover.bind(node))
	elif node is TabContainer:
		node.tab_changed.connect(func(_t): play("select"))


func _on_button_pressed(button: BaseButton) -> void:
	var sfx_name := "click"
	if button.has_meta("sfx"):
		sfx_name = button.get_meta("sfx")
	elif button.name == "BackButton":
		return
	elif button is CheckBox or button is CheckButton:
		sfx_name = "toggle"
	if sfx_name != "":
		play(sfx_name)


func _on_button_hover(button: BaseButton) -> void:
	if not button.disabled and button.is_visible_in_tree():
		play_hover()
