extends MinigameBase

@onready var stack: Control = $Stack
@onready var dish_clean: TextureRect = $DishClean
@onready var dish_dirty: TextureRect = $DishDirty
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var rinse_button: Button = $RinseButton
@onready var sponge: TextureRect = $Sponge
@onready var timer_label: Label = $TimerLabel
@onready var status_label: Label = $StatusLabel

const ITEM_PATH := "res://MiniG/minigames/Scrub/ScrubImages/"
const EXT := ".png"

const DISH_SIZES := {
	"plate": Vector2(160, 160),
	"cup": Vector2(110, 110),
	"spoon": Vector2(60, 150),
	"fork": Vector2(60, 150),
}
const SCRUB_MULTIPLIER := 3.0

@export var auto_layout: bool = true      # turn off if you want to place nodes by hand
@export var sponge_size: Vector2 = Vector2(220, 220)
@export var dishes_per_game: int = 12
@export var time_limit: float = 90.0
@export var scrub_speed: float = 0.0001
@export var min_dirt_alpha: float = 0.3
@export var max_scrub_pixels_per_sec: float = 1500.0  # fastest speed that still counts
var pending_scrub: float = 0.0

enum State { PICKING, SCRUBBING, RINSE_READY, BUSY }
var state: State = State.PICKING

var time_left: float = 0.0
var running: bool = false
var scrub_progress: float = 0.0
var dishes_cleaned: int = 0
var dishes_total: int = 0
var current_button: TextureButton = null

var holding_sponge: bool = false
var grab_offset: Vector2 = Vector2.ZERO
var sponge_home: Vector2
var scrub_center: Vector2


func _ready() -> void:
	randomize()
	if get_tree().current_scene == self:
		setup()


func _apply_layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	scrub_center = vp / 2.0

	if auto_layout:
		# Pile area: left side of the screen
		stack.position = Vector2(vp.x * 0.40, vp.y * 0.35)
		stack.size = Vector2(vp.x * 0.22, vp.y * 0.38)

		# Progress bar: top center
		progress_bar.position = Vector2(vp.x * 0.3, 20)
		progress_bar.size = Vector2(vp.x * 0.4, 30)

		# Rinse button: below the scrub area
		rinse_button.size = Vector2(160, 60)
		rinse_button.position = Vector2(vp.x / 2.0 - 80, vp.y * 0.8)

		# Labels
		timer_label.position = Vector2(40, 40)
		status_label.position = Vector2(vp.x / 2.0 - 100, vp.y * 0.9)

		# Sponge: bottom rig

	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.max_value = 1.0
	progress_bar.step = 0.01
	progress_bar.show_percentage = false

	sponge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sponge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sponge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sponge.pivot_offset = sponge.size / 2.0
	sponge_home = sponge.position


func setup(_context: Dictionary = {}) -> void:
	_apply_layout()

	dishes_cleaned = 0
	time_left = time_limit
	status_label.text = ""
	dish_clean.visible = false
	dish_dirty.visible = false
	rinse_button.visible = false
	progress_bar.visible = false
	sponge.visible = true
	sponge.position = sponge_home
	sponge.rotation = 0.0
	holding_sponge = false
	_build_stack()
	state = State.PICKING
	running = true
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.8, 0.3)
	fill.set_corner_radius_all(6)
	progress_bar.add_theme_stylebox_override("fill", fill)

	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	back.set_corner_radius_all(6)
	progress_bar.add_theme_stylebox_override("background", back)

func _load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("Scrub minigame: missing file " + path)
		return null
	return load(path)

func _load_cropped(path: String) -> Texture2D:
	var tex := _load_tex(path)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img.convert(Image.FORMAT_RGBA8)
	var used: Rect2i = img.get_used_rect()
	if used.size == Vector2i.ZERO:
		return tex
	return ImageTexture.create_from_image(img.get_region(used))

func _build_stack() -> void:
	for child in stack.get_children():
		child.queue_free()

	var all_dishes: Array = []
	for kind in ["plate", "cup", "spoon", "fork"]:
		for i in range(1, 5):
			var dirty_path = ITEM_PATH + kind + str(i) + "dirty" + EXT
			var clean_path = ITEM_PATH + kind + str(i) + EXT
			if not ResourceLoader.exists(clean_path):
				clean_path = ITEM_PATH + kind + "1" + EXT
			if ResourceLoader.exists(dirty_path):
				all_dishes.append({"kind": kind, "clean": clean_path, "dirty": dirty_path})
			else:
				push_warning("Scrub minigame: missing file " + dirty_path)

	print("Scrub: found ", all_dishes.size(), " dishes. Stack size: ", stack.size)

	all_dishes.shuffle()
	dishes_total = min(dishes_per_game, all_dishes.size())

	for i in range(dishes_total):
		var d = all_dishes[i]
		var box: Vector2 = DISH_SIZES[d["kind"]]

		var btn := TextureButton.new()
		btn.texture_normal = _load_cropped(d["dirty"])
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = box
		btn.size = box
		btn.pivot_offset = box / 2.0

		var max_x = max(0.0, stack.size.x - box.x)
		var max_y = max(0.0, stack.size.y - box.y)
		btn.position = Vector2(randf_range(0.0, max_x), randf_range(0.0, max_y))
		btn.rotation = randf_range(-0.3, 0.3)

		btn.set_meta("kind", d["kind"])
		btn.set_meta("clean", d["clean"])
		btn.set_meta("dirty", d["dirty"])
		btn.pressed.connect(_on_dish_picked.bind(btn))
		stack.add_child(btn)


func _on_dish_picked(btn: TextureButton) -> void:
	if state != State.PICKING or not running:
		return

	current_button = btn
	btn.visible = false

	var scrub_size: Vector2 = DISH_SIZES[btn.get_meta("kind")] * SCRUB_MULTIPLIER
	for rect in [dish_clean, dish_dirty]:
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.size = scrub_size
		rect.position = scrub_center - scrub_size / 2.0

	dish_clean.texture = _load_cropped(btn.get_meta("clean"))
	dish_dirty.texture = _load_cropped(btn.get_meta("dirty"))
	dish_dirty.modulate.a = 1.0
	dish_clean.visible = true
	dish_dirty.visible = true

	scrub_progress = 0.0
	progress_bar.value = 0.0
	progress_bar.visible = true
	rinse_button.visible = false
	sponge.visible = true
	state = State.SCRUBBING


func _process(delta: float) -> void:
	if not running:
		return

	time_left -= delta
	timer_label.text = "%.1f" % max(time_left, 0.0)
	if time_left <= 0.0:
		_finish(false)
	if state == State.SCRUBBING:
		var allowed: float = max_scrub_pixels_per_sec * delta
		var counted: float = min(pending_scrub, allowed)
		pending_scrub = 0.0

		if counted > 0.0:
			scrub_progress = min(1.0, scrub_progress + counted * scrub_speed)
			progress_bar.value = scrub_progress
			dish_dirty.modulate.a = lerp(1.0, min_dirt_alpha, scrub_progress)
			if scrub_progress >= 1.0:
				_on_scrub_complete()

func _input(event: InputEvent) -> void:
	if not running:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if sponge.visible and sponge.get_global_rect().has_point(event.position):
				holding_sponge = true
				grab_offset = sponge.global_position - event.position
				get_viewport().set_input_as_handled()
		else:
			holding_sponge = false
			sponge.rotation = 0.0

	if event is InputEventMouseMotion and holding_sponge:
		sponge.global_position = event.position + grab_offset

		if state == State.SCRUBBING:
			var sponge_center: Vector2 = sponge.get_global_rect().get_center()
			if dish_dirty.get_global_rect().has_point(sponge_center):
				pending_scrub += event.relative.length()
				sponge.rotation = sin(Time.get_ticks_msec() * 0.03) * 0.15
				var moved: float = event.relative.length()
				scrub_progress = min(1.0, scrub_progress + moved * scrub_speed)
				progress_bar.value = scrub_progress
				dish_dirty.modulate.a = lerp(1.0, min_dirt_alpha, scrub_progress)
				sponge.rotation = sin(Time.get_ticks_msec() * 0.03) * 0.15

				if scrub_progress >= 1.0:
					_on_scrub_complete()


func _on_scrub_complete() -> void:
	state = State.RINSE_READY
	holding_sponge = false
	rinse_button.visible = true
	sponge.visible = false


func _on_rinse_button_pressed() -> void:
	if state != State.RINSE_READY:
		return

	state = State.BUSY
	rinse_button.visible = false

	var tween := create_tween()
	tween.tween_property(dish_dirty, "modulate:a", 0.0, 0.6)
	tween.tween_interval(0.5)
	await tween.finished

	dish_clean.visible = false
	dish_dirty.visible = false
	progress_bar.visible = false
	current_button.queue_free()
	current_button = null
	dishes_cleaned += 1

	sponge.position = sponge_home
	sponge.rotation = 0.0
	sponge.visible = true

	if dishes_cleaned >= dishes_total:
		_finish(true)
	else:
		state = State.PICKING


func _finish(success: bool) -> void:
	running = false
	holding_sponge = false
	sponge.visible = false
	rinse_button.visible = false
	status_label.text = "Scrubbing: " + ("Success!" if success else "Failed!")
	if success:
		_succeed(dishes_cleaned)
	else:
		_fail(dishes_cleaned)
