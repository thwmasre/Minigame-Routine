extends MinigameBase

@onready var background: TextureRect = $Background
@export var bg_bedside: Texture2D
@export var bg_table: Texture2D
@export var bg_window: Texture2D
@onready var spot_table: Control = $SpotTable
@onready var spot_bed: Control = $SpotBed
@onready var spot_window: Control = $SpotWindow
@onready var item_button: Button = $ItemButton
@onready var choice_panel: Control = $ChoicePanel
@onready var need_button: Button = $ChoicePanel/NeedButton
@onready var trash_button: Button = $ChoicePanel/TrashButton
@onready var timer_label: Label = $ChoicePanel/TimerLabel
@onready var alarm_clock: TextureRect = $ChoicePanel/AlarmClock
@onready var spot_timer_label: Label = $SpotTimerLabel
@onready var almanac_button: Button = $AlmanacButton
@onready var almanac_panel: Control = $AlmanacPanel
@onready var almanac_label: Label = $AlmanacPanel/AlmanacLabel
@onready var almanac_image: TextureRect = $AlmanacPanel/AlmanacImage
@onready var round_label: Label = $RoundLabel
@onready var status_label: Label = $StatusLabel
@onready var spot_alarm_clock: TextureRect = $SpotAlarmClock
@export var alarm_frame1: Texture2D
@export var alarm_frame2: Texture2D

var items: Dictionary = {
	"thing1": "Thing", "thing2": "Thing", "thing3": "Thing", "thing4": "Thing",
	"thing5": "Thing", "thing6": "Thing", "thing7": "Thing", "thing8": "Thing",
	"trash1": "Trash", "trash2": "Trash", "trash3": "Trash",
	"trash4": "Trash", "trash5": "Trash", "trash6": "Trash", "trash7": "Trash",
}
var item_keys: Array = items.keys()

var areas: Array = ["Bedside", "Table", "Window"]
var area_spots: Array = []
var area_index: int = 0

var current_item_key: String = ""
var almanac_index: int = 0
var last_categories: Array = []

var deciding: bool = false
var decision_time_left: float = 20.0
var decision_time_max: float = 20.0
var fail_chance: float = 0.2

var alarm_flip_timer: float = 0.0
var alarm_showing_frame1: bool = true

var waiting_for_click: bool = false
var spot_time_left: float = 5.0
var spot_time_max: float = 5.0

var item_origin_pos: Vector2
var item_origin_scale: Vector2

var vignette: TextureRect

var area_backgrounds: Array = []


	
func _ready() -> void:
	randomize()
	area_spots = [spot_bed, spot_table, spot_window]
	area_backgrounds = [bg_bedside, bg_table, bg_window]
	item_button.pivot_offset = item_button.size / 2
	item_origin_scale = item_button.scale
	_make_vignette()


func setup(context: Dictionary = {}) -> void:
	area_index = 0
	almanac_index = 0
	last_categories = []
	choice_panel.visible = false
	almanac_panel.visible = false
	almanac_button.visible = false
	_start_round()


func _process(delta: float) -> void:
	if waiting_for_click:
		spot_time_left -= delta
		if spot_time_left <= 0.0:
			waiting_for_click = false
			spot_alarm_clock.visible = false
			_on_wrong_or_timeout()
			return

		var flip_speed = lerp(0.6, 0.08, 1.0 - (spot_time_left / spot_time_max))
		alarm_flip_timer -= delta
		if alarm_flip_timer <= 0.0:
			alarm_flip_timer = flip_speed
			alarm_showing_frame1 = not alarm_showing_frame1
			spot_alarm_clock.texture = alarm_frame1 if alarm_showing_frame1 else alarm_frame2
		return

	if not deciding:
		return

	decision_time_left -= delta
	if decision_time_left <= 0.0:
		_on_wrong_or_timeout()
		return

	var flip_speed = lerp(0.6, 0.08, 1.0 - (decision_time_left / decision_time_max))
	alarm_flip_timer -= delta
	if alarm_flip_timer <= 0.0:
		alarm_flip_timer = flip_speed
		alarm_showing_frame1 = not alarm_showing_frame1
		alarm_clock.texture = alarm_frame1 if alarm_showing_frame1 else alarm_frame2


func _start_round() -> void:
	round_label.text = areas[area_index]
	background.texture = area_backgrounds[area_index]

	current_item_key = _pick_random_item()
	item_button.icon = load("res://MiniG/minigames/cleanroom/items/a" + current_item_key + ".jpg")
	item_button.expand_icon = true
	item_button.text = ""
	item_button.disabled = false
	almanac_button.visible = false

	item_origin_pos = _random_pos_in_area(area_spots[area_index])
	item_button.position = item_origin_pos
	item_button.scale = item_origin_scale

	item_button.visible = true
	choice_panel.visible = false
	deciding = false

	waiting_for_click = true
	spot_time_left = spot_time_max
	spot_alarm_clock.visible = true
	alarm_flip_timer = 0.6
	alarm_showing_frame1 = true
	spot_alarm_clock.texture = alarm_frame1


func _pick_random_item() -> String:
	var candidates: Array = item_keys.duplicate()
	if last_categories.size() >= 2 and last_categories[0] == last_categories[1]:
		var blocked_category = last_categories[0]
		candidates = candidates.filter(func(k): return items[k] != blocked_category)

	var key: String = candidates[randi() % candidates.size()]

	last_categories.append(items[key])
	if last_categories.size() > 2:
		last_categories.pop_front()

	return key


func _random_pos_in_area(area: Control) -> Vector2:
	var rect: Rect2 = Rect2(area.position, area.size)
	var max_x = rect.position.x + rect.size.x - item_button.size.x
	var max_y = rect.position.y + rect.size.y - item_button.size.y
	var x = randf_range(rect.position.x, max(rect.position.x, max_x))
	var y = randf_range(rect.position.y, max(rect.position.y, max_y))
	return Vector2(x, y)


func _on_item_button_pressed() -> void:
	if item_button.disabled:
		return

	waiting_for_click = false
	spot_alarm_clock.visible = false

	item_button.disabled = true
	choice_panel.visible = false
	deciding = false

	var viewport_size: Vector2 = get_viewport_rect().size
	var target_pos: Vector2 = viewport_size / 2 - (item_button.size * item_origin_scale * 2.0) / 2

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(item_button, "position", target_pos, 0.3)
	tween.tween_property(item_button, "scale", item_origin_scale * 8.0, 0.3)
	tween.chain().tween_callback(_show_choice)


func _show_choice() -> void:
	choice_panel.visible = true
	almanac_button.visible = true
	decision_time_left = decision_time_max
	deciding = true
	alarm_flip_timer = 0.6
	alarm_showing_frame1 = true
	alarm_clock.texture = alarm_frame1


func _on_need_button_pressed() -> void:
	_submit_answer("Thing")


func _on_trash_button_pressed() -> void:
	_submit_answer("Trash")


func _submit_answer(answer: String) -> void:
	if not deciding:
		return
	if not items.has(current_item_key):
		return
	deciding = false
	choice_panel.visible = false

	if items[current_item_key] == answer:
		area_index += 1
		if area_index >= areas.size():
			_end_session(true)
		else:
			_start_round()
	else:
		_on_wrong_or_timeout()


func _on_wrong_or_timeout() -> void:
	deciding = false
	waiting_for_click = false
	choice_panel.visible = false
	spot_alarm_clock.visible = false
	_flash_fail()

	if randf() < fail_chance:
		_end_session(false)
	else:
		_start_round()


func _end_session(success: bool) -> void:
	item_button.visible = false
	choice_panel.visible = false
	spot_timer_label.text = ""
	status_label.text = "Clean Room: " + ("Success!" if success else "Failed!")
	if success:
		_succeed(area_index)
	else:
		_fail(area_index)


func _on_almanac_button_pressed() -> void:
	almanac_panel.visible = true
	_update_almanac()


func _update_almanac() -> void:
	var key = item_keys[almanac_index]
	almanac_label.text = items[key]
	almanac_image.texture = load("res://MiniG/minigames/cleanroom/items/" + key + ".jpg")


func _on_almanac_next_pressed() -> void:
	almanac_index = (almanac_index + 1) % item_keys.size()
	_update_almanac()


func _on_almanac_prev_pressed() -> void:
	almanac_index = (almanac_index - 1 + item_keys.size()) % item_keys.size()
	_update_almanac()


func _on_almanac_close_pressed() -> void:
	almanac_panel.visible = false


func _make_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.4, 1.0])
	grad.colors = PackedColorArray([Color(1, 0, 0, 0), Color(1, 0, 0, 0.85)])

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 512
	tex.height = 512

	vignette = TextureRect.new()
	vignette.texture = tex
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	add_child(vignette)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _flash_fail() -> void:
	vignette.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(vignette, "modulate:a", 0.0, 0.6)
