extends MinigameBase

@onready var background: TextureRect = $Background
@onready var phone_body: Panel = $PhoneBody
@onready var screen: Panel = $Screen
@onready var ads_container: Control = $Screen/AdsContainer
@onready var timer_label: Label = $TimerLabel
@onready var counter_label: Label = $CounterLabel
@onready var status_label: Label = $StatusLabel

@export_dir var item_path: String = "res://MiniG/minigames/ads"
@export var ext: String = ".png"
@export var portrait_count: int = 6
@export var landscape_count: int = 6
@export var x_style_count: int = 3

@export var phone_size: Vector2 = Vector2(300, 620)
@export var max_ads_on_screen: int = 4
@export var spawn_schedule: Array = [[5, 2.5], [4, 2.0], [7, 1.5]]  # [how many ads, seconds between them]
@export var x_time_limit: float = 4.0
@export var misclick_penalty: float = 1.0
@export var x_size: float = 30.0


var portrait_tex: Array = []
var landscape_tex: Array = []
var x_tex: Array = []

var running: bool = false
var spawn_timer: float = 0.0
var x_time_left: float = 0.0
var total_ads: int = 0
var ads_spawned: int = 0
var ads_open: int = 0
var ads_closed: int = 0


func _ready() -> void:
	randomize()
	if get_tree().current_scene == self:
		setup()


func setup(_context: Dictionary = {}) -> void:
	_apply_layout()

	portrait_tex = _load_set("Portrait_Ads_", portrait_count)
	landscape_tex = _load_set("Landscape_Ads_", landscape_count)
	x_tex = _load_set("X_Button_Style_", x_style_count)
	print("Ads: portrait ", portrait_tex.size(), " landscape ", landscape_tex.size(), " x ", x_tex.size())

	for c in ads_container.get_children():
		c.queue_free()

	total_ads = 0
	for group in spawn_schedule:
		total_ads += int(group[0])

	ads_spawned = 0
	ads_open = 0
	ads_closed = 0
	x_time_left = x_time_limit
	spawn_timer = 0.5
	status_label.text = ""
	_update_counter()
	running = true


func _load_set(prefix: String, count: int) -> Array:
	var out: Array = []
	for i in range(1, count + 1):
		var p: String = item_path.path_join(prefix + str(i) + ext)
		if ResourceLoader.exists(p):
			out.append(load(p))
		else:
			push_warning("Ads minigame: missing file " + p)
	return out


func _delay_for(index: int) -> float:
	var passed: int = 0
	for group in spawn_schedule:
		passed += int(group[0])
		if index < passed:
			return float(group[1])
	return float(spawn_schedule[-1][1])


func _apply_layout() -> void:
	var vp: Vector2 = get_viewport_rect().size

	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.modulate = Color(0.7, 0.7, 0.7)

	var phone_pos: Vector2 = (vp - phone_size) / 2.0
	phone_body.position = phone_pos
	phone_body.size = phone_size
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.07, 0.07, 0.09)
	body.border_color = Color(0.3, 0.3, 0.35)
	body.set_border_width_all(4)
	body.set_corner_radius_all(36)
	phone_body.add_theme_stylebox_override("panel", body)
	phone_body.mouse_filter = Control.MOUSE_FILTER_IGNORE

	screen.position = phone_pos + Vector2(12, 34)
	screen.size = phone_size - Vector2(24, 58)
	screen.clip_contents = true
	var scr := StyleBoxFlat.new()
	scr.bg_color = Color(0, 0, 0)
	scr.set_corner_radius_all(18)
	screen.add_theme_stylebox_override("panel", scr)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	ads_container.position = Vector2.ZERO
	ads_container.size = screen.size
	ads_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	timer_label.position = Vector2(20, 20)
	counter_label.position = Vector2(20, 50)
	status_label.position = Vector2(20, vp.y - 50)


func _process(delta: float) -> void:
	if not running:
		return

	if ads_open > 0:
		x_time_left -= delta
		if x_time_left <= 0.0:
			timer_label.text = "0.0"
			_finish(false)
			return
	timer_label.text = "%.1f" % max(x_time_left, 0.0)

	if ads_spawned < total_ads:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			_spawn_ad()
			spawn_timer = _delay_for(ads_spawned)

	if ads_open > max_ads_on_screen:
		_finish(false)


func _spawn_ad() -> void:
	var is_portrait: bool = randf() < 0.5
	var pool: Array = portrait_tex if is_portrait else landscape_tex
	if pool.is_empty():
		pool = landscape_tex if is_portrait else portrait_tex
	if pool.is_empty():
		return

	var tex: Texture2D = pool.pick_random()
	var area: Vector2 = ads_container.size

	var w: float = randf_range(150.0, 190.0) if is_portrait else randf_range(220.0, 250.0)
	w = min(w, area.x)
	var aspect: float = tex.get_height() / float(tex.get_width())
	var h: float = w * aspect
	if h > area.y * 0.6:
		h = area.y * 0.6
		w = h / aspect
	var ad_size := Vector2(w, h)

	var ad := TextureRect.new()
	ad.texture = tex
	ad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ad.stretch_mode = TextureRect.STRETCH_SCALE
	ad.size = ad_size
	ad.pivot_offset = ad_size / 2.0
	ad.mouse_filter = Control.MOUSE_FILTER_STOP
	ad.position = Vector2(
		randf_range(0.0, max(0.0, area.x - w)),
		randf_range(0.0, max(0.0, area.y - h)))
	ad.gui_input.connect(_on_ad_gui_input.bind(ad))

	var xb := TextureButton.new()
	xb.texture_normal = x_tex.pick_random() if not x_tex.is_empty() else null
	xb.ignore_texture_size = true
	xb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	xb.size = Vector2(x_size, x_size)
	xb.custom_minimum_size = xb.size
	xb.position = Vector2(
		randf_range(4.0, max(4.0, w - x_size - 4.0)),
		randf_range(4.0, max(4.0, h - x_size - 4.0)))
	xb.pressed.connect(_on_x_pressed.bind(ad))
	ad.add_child(xb)

	ads_container.add_child(ad)

	ad.scale = Vector2(0.8, 0.8)
	var tw := create_tween()
	tw.tween_property(ad, "scale", Vector2.ONE, 0.12)

	if ads_open == 0:
		x_time_left = x_time_limit
	ads_spawned += 1
	ads_open += 1
	_update_counter()


func _on_x_pressed(ad: TextureRect) -> void:
	if not running or ad.has_meta("closed"):
		return
	ad.set_meta("closed", true)
	ad.queue_free()
	ads_open -= 1
	ads_closed += 1
	x_time_left = x_time_limit
	_update_counter()

	if ads_spawned >= total_ads and ads_open <= 0:
		_finish(true)


func _on_ad_gui_input(event: InputEvent, ad: TextureRect) -> void:
	if not running:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		x_time_left -= misclick_penalty
		ad.modulate = Color(1, 0.4, 0.4)
		var tw := create_tween()
		tw.tween_property(ad, "modulate", Color.WHITE, 0.25)


func _update_counter() -> void:
	counter_label.text = "Ads closed: %d / %d" % [ads_closed, total_ads]


func _finish(success: bool) -> void:
	if not running:
		return
	running = false
	status_label.text = "Ads: " + ("Success!" if success else "Failed!")
	if success:
		_succeed(ads_closed)
	else:
		_fail(ads_closed)
