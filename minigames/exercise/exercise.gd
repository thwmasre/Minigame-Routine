extends MinigameBase

@onready var bar: ProgressBar = $Bar
@onready var label: Label = $Label
@onready var countdown_label: Label = $CountdownLabel
@onready var status_label: Label = $StatusLabel
@onready var injured_label: Label = $InjuredLabel
@onready var push_button: TextureButton = $PushButton
@onready var rep_button: TextureButton = $RepButton
@onready var pose: Sprite2D = $Pose

@export var rep_idle_tex: Texture2D
@export var rep_ready_tex: Texture2D
@export var pixel_font: Font
@export var pushup_frames: Array[Texture2D]
@export var situp_frames: Array[Texture2D]
@export var squat_frames: Array[Texture2D]
@export var pullup_frames: Array[Texture2D]

var all_frames: Array = []
var rect_cache: Dictionary = {}

var rounds: Array = ["Push-up", "Sit-up", "Squat", "Pull-up"]
var round_index: int = 0
var reps_needed: int = 2
var reps_done: int = 0

var percent: float = 0.0
var push_gain: float = 8.0
var decay_rate: float = 15.0
var energy_stat: int = 100

var target_percent: int = 60

var in_hold: bool = false
var hold_timer: float = 0.0
var hold_duration: float = 2.0

var extra_pushes: int = 0
var max_extra_pushes: int = 1
var has_progress: bool = false

var zero_timer_duration: float = 3.0
var zero_timer: float = 3.0

var fill_style: StyleBoxFlat
var vignette: TextureRect


func _ready() -> void:
	pose.centered = false
	all_frames = [pushup_frames, situp_frames, squat_frames, pullup_frames]
	_style_ui()
	_make_vignette()
	if get_parent() == get_tree().root:
		setup()


func setup(context: Dictionary = {}) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	energy_stat = context.get("energy", 100)
	bar.min_value = 0
	bar.max_value = 100
	round_index = 0
	reps_done = 0
	injured_label.visible = false
	push_button.disabled = true
	rep_button.disabled = true
	set_process(false)
	_update_pose()
	_play_ready_set_go()


func _play_ready_set_go() -> void:
	status_label.text = "Ready"
	await get_tree().create_timer(0.7).timeout
	status_label.text = "Set"
	await get_tree().create_timer(0.7).timeout
	status_label.text = "Go!"
	await get_tree().create_timer(0.5).timeout
	status_label.text = ""
	push_button.disabled = false
	rep_button.disabled = false
	set_process(true)
	_new_rep()


func _new_rep() -> void:
	percent = 0.0
	in_hold = false
	extra_pushes = 0
	has_progress = false
	zero_timer = zero_timer_duration
	target_percent = randi_range(80, 95)
	bar.value = percent
	_update_pose()
	_update_labels()


func _process(delta: float) -> void:
	var decay_speed = decay_rate * (1.0 + (100.0 - energy_stat) / 100.0)

	if in_hold:
		hold_timer -= delta
		if hold_timer <= 0.0:
			in_hold = false
			percent = max(percent - 15.0, 0.0)
	else:
		percent -= decay_speed * delta
		percent = max(percent, 0.0)

		if percent <= 0.0 and has_progress:
			zero_timer -= delta
			if zero_timer <= 0.0:
				_fail_rep()
				return
		else:
			zero_timer = zero_timer_duration

		if percent >= target_percent:
			percent = target_percent
			in_hold = true
			hold_timer = hold_duration
			extra_pushes = 0

	bar.value = percent
	_update_pose()
	_update_labels()


func _on_push_button_pressed() -> void:
	if in_hold:
		extra_pushes += 1
		if extra_pushes > max_extra_pushes:
			_fail_rep()
		return

	percent = min(percent + push_gain, 100.0)
	has_progress = true


func _on_rep_button_pressed() -> void:
	if in_hold:
		_succeed_rep()
	else:
		_fail_rep()


func _succeed_rep() -> void:
	reps_done += 1
	if reps_done >= reps_needed:
		reps_done = 0
		round_index += 1
		if round_index >= rounds.size():
			_end_workout(true)
			return
	_new_rep()


func _fail_rep() -> void:
	_flash_fail()
	if randf() < 0.3:
		_end_workout(false)
	else:
		_new_rep()


func _end_workout(success: bool) -> void:
	set_process(false)
	push_button.disabled = true
	rep_button.disabled = true
	countdown_label.text = ""
	if success:
		status_label.text = "Workout complete!"
	else:
		status_label.text = ""
		injured_label.visible = true
	await get_tree().create_timer(1.5).timeout
	if success:
		_succeed(round_index * reps_needed)
	else:
		_fail(round_index * reps_needed + reps_done)


func _get_bounds(tex: Texture2D) -> Rect2i:
	var img: Image = tex.get_image()
	var min_x: int = img.get_width()
	var min_y: int = img.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			var is_bg: bool = c.a < 0.1 or (c.r > 0.9 and c.g > 0.9 and c.b > 0.9)
			if not is_bg:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i(0, 0, img.get_width(), img.get_height())
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _update_pose() -> void:
	if round_index >= all_frames.size():
		return
	var frames: Array = all_frames[round_index]
	if frames.size() == 0:
		return
	var i: int = clampi(int(percent / 100.0 * frames.size()), 0, frames.size() - 1)
	var tex: Texture2D = frames[i]
	if not rect_cache.has(tex):
		rect_cache[tex] = _get_bounds(tex)
	var r: Rect2i = rect_cache[tex]
	pose.texture = tex
	pose.offset = Vector2(-(r.position.x + r.size.x / 2), -(r.position.y + r.size.y))


func _update_labels() -> void:
	fill_style.bg_color = Color.GREEN if in_hold else Color.RED
	rep_button.texture_normal = rep_ready_tex if in_hold else rep_idle_tex

	if round_index < rounds.size():
		label.text = rounds[round_index] + "  " + str(reps_done) + "/" + str(reps_needed)

	if in_hold:
		countdown_label.text = "CLICK REP (" + str(int(ceil(hold_timer))) + ")"
	elif percent <= 0.0 and has_progress:
		countdown_label.text = "0%  Push! (" + str(int(ceil(zero_timer))) + ")"
	else:
		countdown_label.text = ""


func _style_ui() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.05, 0.05)
	bg.set_border_width_all(4)
	bg.border_color = Color.BLACK
	bg.set_corner_radius_all(0)
	bg.anti_aliasing = false

	fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color.RED
	fill_style.set_border_width_all(4)
	fill_style.border_color = Color.BLACK
	fill_style.set_corner_radius_all(0)
	fill_style.anti_aliasing = false

	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill_style)
	bar.show_percentage = false
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	for l in [label, countdown_label, status_label, injured_label]:
		l.add_theme_font_size_override("font_size", 32)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if pixel_font:
			l.add_theme_font_override("font", pixel_font)

	injured_label.add_theme_color_override("font_color", Color.RED)

func _make_vignette() -> void:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.4, 1.0])
	grad.colors = PackedColorArray([Color(1, 0, 0, 0), Color(1, 0, 0, 0.85)])

##Gradient
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
