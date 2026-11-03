extends MinigameBase

@onready var background: ColorRect = $Background
@onready var phone_body: Panel = $PhoneBody
@onready var screen: Panel = $Screen
@onready var wallpaper: TextureRect = $Screen/Wallpaper
@onready var cards_container: Control = $Screen/CardsContainer
@onready var timer_label: Label = $TimerLabel
@onready var counter_label: Label = $CounterLabel
@onready var status_label: Label = $StatusLabel

@export_dir var item_path: String = "res://MiniG/minigames/apps"
@export var phone_size: Vector2 = Vector2(300, 620)
@export var time_limit: float = 25.0
@export var swipe_distance: float = 80.0    # how far up to drag to close a card
@export var card_width_ratio: float = 0.62  # card width vs. phone screen width
@export var card_height_ratio: float = 0.72
@export var card_gap: float = 1.0
@export var cards_per_game: int = 50

enum Mode { NONE, VERTICAL, HORIZONTAL }

var cards: Array = []
var total_cards: int = 0
var closed: int = 0
var focus: float = 0.0          # which card is centered (can be fractional while dragging)
var card_size: Vector2
var base_y: float = 0.0

var running: bool = false
var time_left: float = 0.0

var pressing: bool = false
var mode: Mode = Mode.NONE
var press_pos: Vector2
var start_focus: float = 0.0
var drag_card: Control = null


func _ready() -> void:
	randomize()
	if get_tree().current_scene == self:
		setup()


func setup(_context: Dictionary = {}) -> void:
	_apply_layout()

	for c in cards_container.get_children():
		c.queue_free()
	cards.clear()

	var textures: Array = _load_apps()
	print("Apps: loaded ", textures.size(), " from ", item_path)
	textures.shuffle()
	var picked: Array = []
	for i in cards_per_game:
		picked.append(textures.pick_random())
	textures = picked
	
	
	for tex in textures:
		var card := TextureRect.new()
		card.texture = tex
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		card.size = card_size
		card.pivot_offset = card_size / 2.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.set_meta("dy", 0.0)
		cards_container.add_child(card)
		cards.append(card)

	total_cards = cards.size()
	closed = 0
	focus = 0.0
	pressing = false
	drag_card = null
	time_left = time_limit
	status_label.text = "Swipe the apps up!"
	_update_counter()
	_layout(1.0)
	running = total_cards > 0


func _load_apps() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var files: PackedStringArray = DirAccess.get_files_at(item_path)
	files.sort()
	for f in files:
		var fname: String = f.trim_suffix(".import").trim_suffix(".remap")
		var lower: String = fname.to_lower()
		if seen.has(lower) or not lower.begins_with("app"):
			continue
		if not (lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".webp")):
			continue
		if not lower.get_basename().substr(3).is_valid_int():
			continue
		seen[lower] = true
		var tex = load(item_path.path_join(fname))
		if tex:
			out.append(tex)
	return out


func _apply_layout() -> void:
	var vp: Vector2 = get_viewport_rect().size

	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color.BLACK
	background.mouse_filter = Control.MOUSE_FILTER_STOP

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
	scr.bg_color = Color.BLACK
	scr.set_corner_radius_all(18)
	screen.add_theme_stylebox_override("panel", scr)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE

	wallpaper.position = Vector2.ZERO
	wallpaper.size = screen.size
	wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	cards_container.position = Vector2.ZERO
	cards_container.size = screen.size
	cards_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	card_size = Vector2(screen.size.x * card_width_ratio, screen.size.y * card_height_ratio)
	base_y = (screen.size.y - card_size.y) / 2.0

	timer_label.position = Vector2(20, 20)
	counter_label.position = Vector2(20, 50)
	status_label.position = Vector2(20, vp.y - 50)


func _process(delta: float) -> void:
	if not running:
		return

	time_left -= delta
	timer_label.text = "%.1f" % max(time_left, 0.0)
	if time_left <= 0.0:
		_finish(false)
		return

	_layout(1.0 - exp(-delta * 18.0))   # smooth sliding


func _layout(t: float) -> void:
	var spacing: float = card_size.x + card_gap
	var center_x: float = cards_container.size.x / 2.0
	for i in range(cards.size()):
		var c: Control = cards[i]
		var off: float = float(i) - focus
		var target_x: float = center_x + off * spacing - card_size.x / 2.0
		c.position.x = lerp(c.position.x, target_x, t)
		c.position.y = base_y + float(c.get_meta("dy", 0.0))
		var s: float = lerp(1.0, 0.9, min(abs(off), 1.0))
		c.scale = Vector2(s, s)
		c.modulate = Color.WHITE.darkened(min(abs(off), 1.0) * 0.25)
		c.z_index = 100 - int(abs(off) * 10.0)


func _card_at(pos: Vector2) -> Control:
	var best: Control = null
	var best_d: float = INF
	for i in range(cards.size()):
		var c: Control = cards[i]
		if c.get_global_rect().has_point(pos):
			var d: float = abs(float(i) - focus)
			if d < best_d:
				best_d = d
				best = c
	return best


func _input(event: InputEvent) -> void:
	if not running:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not screen.get_global_rect().has_point(event.position):
				return
			pressing = true
			mode = Mode.NONE
			press_pos = event.position
			start_focus = focus
			drag_card = _card_at(event.position)
		elif pressing:
			pressing = false
			_release()

	elif event is InputEventMouseMotion and pressing:
		var d: Vector2 = event.position - press_pos
		if mode == Mode.NONE and d.length() > 10.0:
			if abs(d.y) > abs(d.x) and drag_card != null:
				mode = Mode.VERTICAL
			else:
				mode = Mode.HORIZONTAL

		if mode == Mode.VERTICAL and is_instance_valid(drag_card):
			drag_card.set_meta("dy", min(d.y, 30.0))   # follows finger, can't be pulled far down
		elif mode == Mode.HORIZONTAL:
			var spacing: float = card_size.x + card_gap
			focus = clamp(start_focus - d.x / spacing, 0.0, max(0.0, float(cards.size() - 1)))


func _release() -> void:
	if mode == Mode.VERTICAL and is_instance_valid(drag_card):
		if float(drag_card.get_meta("dy", 0.0)) < -swipe_distance:
			_dismiss(drag_card)
		else:
			var c: Control = drag_card
			var tw := create_tween()
			tw.tween_method(func(v: float): 
				if is_instance_valid(c):
					c.set_meta("dy", v),
				float(c.get_meta("dy", 0.0)), 0.0, 0.15)
	elif mode == Mode.HORIZONTAL:
		_snap_focus()
	drag_card = null
	mode = Mode.NONE


func _snap_focus() -> void:
	var target: float = clamp(round(focus), 0.0, max(0.0, float(cards.size() - 1)))
	var tw := create_tween()
	tw.tween_property(self, "focus", target, 0.15)


func _dismiss(card: Control) -> void:
	cards.erase(card)
	closed += 1
	_update_counter()

	# Fly off the top and delete
	card.z_index = 200
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "position:y", -card_size.y - 60.0, 0.2)
	tw.tween_property(card, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(card.queue_free)

	_snap_focus()

	if cards.is_empty():
		_finish(true)


func _update_counter() -> void:
	counter_label.text = "Closed: %d / %d" % [closed, total_cards]


func _finish(success: bool) -> void:
	if not running:
		return
	running = false
	pressing = false
	status_label.text = "Apps: " + ("Success!" if success else "Failed!")
	if success:
		_succeed(closed)
	else:
		_fail(closed)
