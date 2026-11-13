extends MinigameBase

signal ride_finished(ride: String, seconds: float)

@onready var scenery: TextureRect = $Scenery
@onready var background: TextureRect = $Background
@onready var passengers: Control = $Passengers
@onready var time_label: Label = get_node_or_null("TimeLabel")
	
# ---------------- OPTIONS (change these in the Inspector) ----------------

@export_dir var item_path: String = "res://MiniG/minigames/jeep"
@export_enum("day", "dawn", "night") var time_of_day: String = "day"
@export_range(0, 2) var how_far: int = 2     # 0 = near, 1 = far, 2 = farthest
@export var swap_interval: float = 10.0      # new commuters every 10 seconds
@export var fade_time: float = 0.4           # black fade in / out
@export var bob_px: float = 3.0              # how far a passenger bobs up
@export var bob_interval: Vector2 = Vector2(0.9, 1.4)   # seconds between bob frames
@export var pair_chance: float = 0.15        # chance a seat gets a 2-person image
@export var stage_time: float = 8.0   # seconds spent on each scene (keep above 3)
# ---------------- SETTINGS (change these in the script) ----------------

# Change this ONE line to true in the go-home copy

# How many seconds each distance lasts
const DISTANCE_TIME := {"near": 10.0, "far": 20.0, "farthest": 30.0}
const DISTANCES := ["near", "far", "farthest"]

# How many people fill the bench (a 2-person image counts as 2)
const CROWD_SLOTS := {"few": 2, "fair": 4, "kinda": 5, "crowded": 8}

# Color tint of the jeep for each time of day
const TIME_TINT := {
	"day": Color.WHITE,
	"dawn": Color(1.0, 0.78, 0.62),
	"night": Color(0.45, 0.5, 0.78),
}

# The 9 rides: code -> time of day, distance, crowd level
const RIDES := {
	"dn":   {"time": "day",   "dist": "near",     "crowd": "few"},
	"dwn":  {"time": "dawn",  "dist": "near",     "crowd": "kinda"},
	"nn":   {"time": "night", "dist": "near",     "crowd": "fair"},
	"df":   {"time": "day",   "dist": "far",      "crowd": "kinda"},
	"dwf":  {"time": "dawn",  "dist": "far",      "crowd": "crowded"},
	"nf":   {"time": "night", "dist": "far",      "crowd": "kinda"},
	"dft":  {"time": "day",   "dist": "farthest", "crowd": "crowded"},
	"dwft": {"time": "dawn",  "dist": "farthest", "crowd": "crowded"},
	"nft":  {"time": "night", "dist": "farthest", "crowd": "crowded"},
}

# Where people sit on the bench. Numbers are percent of the jeep picture:
# 0 = left edge, 50 = middle (the MC), 100 = right edge.
# "y" = where the feet land (0 = top, 1 = bottom of the picture)
const STAND_ROW := {"y": 0.85, "xs": [5, 20, 30, 38, 60, 70, 85, 95]}
const MC_SEAT := {"x": 50.0, "y": 0.90, "height": 0.58}   # MC height = 58% of the jeep picture; sets everyone's size
const PAIR_REACH := 20.0     # a 2-person image needs seats within this many percent

# ---------------- VARIABLES ----------------

var singles: Array = []      # images of 1 person (c1, c2 ...)
var pairs: Array = []        # images of 2 people (c1b, c2b ...)
var mc_tex: Texture2D
var seats: Array = []
var fade: ColorRect          # black screen used for fades

var stages: Array = []       # rides we pass through, in order
var ride: String = ""
var duration: float = 0.0
var time_left: float = 0.0
var swap_timer: float = 0.0
var crowd_target: int = 0
var unit_scale: float = 1.0  # same scale for every person
var jeep_rect: Rect2         # where the jeep picture sits on screen
var running: bool = false
var swapping: bool = false

var crowd: Array = []
var last_images: Array = []


func _ready() -> void:
	# Makes the white windows of the jeep see-through so the scenery shows
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float white = step(0.95, min(t.r, min(t.g, t.b)));
	COLOR.a *= (1.0 - white);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	background.material = mat

	# Black screen on top of everything
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	fade.position = Vector2.ZERO
	fade.size = get_viewport_rect().size

	if get_tree().current_scene == self:
		setup()
		print("RIDE duration = ", duration, " | script = ", get_script().resource_path, " | stages = ", stages)

# Called by the manager (or by _ready when you press F6)
func setup(context: Dictionary = {}) -> void:
	# 1. Work out the trip: from_far -> how_far, one step at a time (up or down)
	var tod: String = str(context.get("time_of_day", time_of_day))
	var to_i: int = clampi(int(context.get("how_far", how_far)), 0, 2)
	var from_i: int = clampi(int(context.get("from_far", 0)), 0, 2)
	var step: int = 1 if to_i >= from_i else -1
	stages.clear()
	for i in range(from_i, to_i + step, step):
		stages.append(_ride_code(tod, DISTANCES[i]))

	ride = stages[-1]
	duration = stage_time * stages.size()
	swap_interval = stage_time
	swap_timer = swap_interval
	crowd_target = CROWD_SLOTS[RIDES[stages[0]]["crowd"]]
	time_left = duration
	swapping = false

	# 2. Prepare art and positions
	_load_images()
	_set_background(stages[0])
	jeep_rect = Rect2(background.position, background.size)
	unit_scale = MC_SEAT["height"] * jeep_rect.size.y / float(mc_tex.get_height())
	_build_seats()

	# 3. Place the MC and the first crowd
	for n in passengers.get_children():
		n.queue_free()
	crowd.clear()
	last_images.clear()
	_place_person(mc_tex, jeep_rect.position.x + MC_SEAT["x"] / 100.0 * jeep_rect.size.x,
			jeep_rect.position.y + MC_SEAT["y"] * jeep_rect.size.y)
	_spawn_crowd()

	# 4. Start from black and fade in
	running = true
	fade.modulate.a = 1.0
	_fade_to(0.0)


# Finds the ride code for a time of day and distance (dn, df, dft ...)
func _ride_code(tod: String, dist: String) -> String:
	for code in RIDES:
		if RIDES[code]["time"] == tod and RIDES[code]["dist"] == dist:
			return code
	return "dn"


# Which ride we are passing through right now
func _stage_now() -> String:
	var elapsed: float = duration - time_left
	var i: int = int(elapsed / duration * stages.size())
	return stages[clampi(i, 0, stages.size() - 1)]


# ---------------- LOADING ----------------

func _load_images() -> void:
	singles.clear()
	pairs.clear()
	mc_tex = null

	var single_name := RegEx.create_from_string("^c\\d+$")    # c1, c2 ...
	var pair_name := RegEx.create_from_string("^c\\d+b$")     # c1b, c2b ...
	var seen: Dictionary = {}

	for file in DirAccess.get_files_at(item_path):
		var fname: String = file.trim_suffix(".import").trim_suffix(".remap")
		if seen.has(fname) or not fname.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			continue
		seen[fname] = true

		var base: String = fname.get_basename().to_lower()
		var tex := load(item_path.path_join(fname)) as Texture2D
		if base == "mc1":
			mc_tex = tex
		elif single_name.search(base):
			singles.append(tex)
		elif pair_name.search(base):
			pairs.append(tex)

	print("Jeep: ", singles.size(), " singles, ", pairs.size(), " pairs, mc: ", mc_tex != null)

	# Colored boxes if art is missing
	if singles.is_empty():
		for i in 8:
			singles.append(_color_box(120, 260, Color.from_hsv(i / 8.0, 0.5, 0.85)))
	if pairs.is_empty():
		for i in 3:
			pairs.append(_color_box(240, 260, Color.from_hsv(i / 3.0, 0.4, 0.75)))
	if mc_tex == null:
		mc_tex = _color_box(120, 260, Color(0.3, 0.8, 1.0))


func _color_box(w: int, h: int, color: Color) -> Texture2D:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


# A file named after the ride (dn.jpg ...) goes behind the jeep as the outside view
func _set_background(code: String) -> void:
	scenery.texture = null
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var path: String = item_path.path_join(code + "." + ext)
		if ResourceLoader.exists(path):
			scenery.texture = load(path)
			break
	background.modulate = TIME_TINT[RIDES[code]["time"]]


# ---------------- SEATS ----------------

# Turns the percent numbers into seats in screen pixels
func _build_seats() -> void:
	seats.clear()
	for percent in STAND_ROW["xs"]:
		seats.append({
			"x": jeep_rect.position.x + percent / 100.0 * jeep_rect.size.x,
			"y": jeep_rect.position.y + STAND_ROW["y"] * jeep_rect.size.y,
		})


# ---------------- PASSENGERS ----------------

# Puts one person on screen. x = center, y = feet.
func _place_person(tex: Texture2D, x: float, y: float) -> TextureRect:
	var width: float = tex.get_width() * unit_scale
	var height: float = tex.get_height() * unit_scale

	var person := TextureRect.new()
	person.texture = tex
	person.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	person.stretch_mode = TextureRect.STRETCH_SCALE
	person.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	person.mouse_filter = Control.MOUSE_FILTER_IGNORE
	person.size = Vector2(width, height)
	person.position = Vector2(x - width / 2.0, y - height)
	passengers.add_child(person)

	person.set_meta("base_y", person.position.y)
	person.set_meta("is_up", false)
	person.set_meta("timer", randf_range(0.0, bob_interval.y))
	person.set_meta("interval", randf_range(bob_interval.x, bob_interval.y))
	return person


# Picks an image not used yet (also avoids last round's images)
func _pick_image(pool: Array, used: Array) -> Texture2D:
	var fresh := pool.filter(func(t): return not used.has(t) and not last_images.has(t))
	if fresh.is_empty():
		fresh = pool.filter(func(t): return not used.has(t))
	if fresh.is_empty():
		fresh = pool
	return fresh.pick_random()


# A free seat close by, for a 2-person image
func _find_neighbor(seat: Dictionary, free: Array) -> Dictionary:
	var reach: float = PAIR_REACH / 100.0 * jeep_rect.size.x
	var close := free.filter(func(o): return absf(o["x"] - seat["x"]) <= reach)
	return close.pick_random() if not close.is_empty() else {}


# The MC's spot is never in the seat list, so the MC is never replaced
func _spawn_crowd() -> void:
	var free: Array = seats.duplicate()
	free.shuffle()
	var used: Array = []
	var filled: int = 0

	while filled < crowd_target and not free.is_empty():
		var seat: Dictionary = free.pop_back()
		var neighbor: Dictionary = {}
		if crowd_target - filled >= 2 and randf() < pair_chance:
			neighbor = _find_neighbor(seat, free)

		if neighbor.is_empty():
			var tex := _pick_image(singles, used)
			used.append(tex)
			crowd.append(_place_person(tex, seat["x"], seat["y"]))
			filled += 1
		else:
			free.erase(neighbor)
			var tex := _pick_image(pairs, used)
			used.append(tex)
			crowd.append(_place_person(tex, (seat["x"] + neighbor["x"]) / 2.0, seat["y"]))
			filled += 2
	last_images = used


# ---------------- FADES ----------------

func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", alpha, fade_time)
	await tween.finished


# Screen goes black, scenery and crowd change, screen comes back
func _swap_crowd() -> void:
	swapping = true
	await _fade_to(1.0)

	var stage: String = _stage_now()
	_set_background(stage)
	crowd_target = CROWD_SLOTS[RIDES[stage]["crowd"]]

	for person in crowd:
		person.queue_free()
	crowd.clear()
	_spawn_crowd()
	await _fade_to(0.0)
	swapping = false


# ---------------- EACH FRAME ----------------

func _process(delta: float) -> void:
	if not running:
		return

	_bob_everyone(delta)

	time_left -= delta
	if time_label:
		time_label.text = str(ceili(max(time_left, 0.0)))

	if time_left <= 0.0:
		_finish()
		return

	if not swapping:
		swap_timer -= delta
		if swap_timer <= 0.0:
			swap_timer = swap_interval
			if time_left > 3.0:
				_swap_crowd()


# 2-frame bob: down, up, down, up (jumps, no smooth movement)
func _bob_everyone(delta: float) -> void:
	for person in passengers.get_children():
		var t: float = person.get_meta("timer") - delta
		if t <= 0.0:
			t = person.get_meta("interval")
			var up: bool = not person.get_meta("is_up")
			person.set_meta("is_up", up)
			person.position.y = person.get_meta("base_y") - (bob_px if up else 0.0)
		person.set_meta("timer", t)


# The ride fades to black and ends. Members can use ride_finished for energy/stats.
func _finish() -> void:
	running = false
	await _fade_to(1.0)
	ride_finished.emit(ride, duration)
	_succeed(int(duration))
